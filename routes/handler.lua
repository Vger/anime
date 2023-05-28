--[[
-- Main functionality for looking up handlers for different URIs.
--
-- Also adds some convenience methods for sending data back to http client.
--]]
local M = {}

local http_headers = require "http.headers"
local lpeg = require "lpeg"
local uri_pattern = require "lpeg_patterns.uri".uri_reference * lpeg.P(-1)
local http_util = require "http.util"

local routes = {}

local route_methods = {}

local route_mt = {
	__index = route_methods
}

local function empty_iterator()
	return nil
end

function route_methods:query_args()
	if self.query ~= nil then
		return http_util.query_args(self.query)
	else
		return empty_iterator
	end
end

-- Send standard http headers to client
function route_methods:std_header(end_stream)
	self.res_headers:upsert(":status", "200")
	self.res_headers:append("content-type", "text/html; charset=utf-8")
	self.res_headers:append("cache-control", "no-cache")
	assert(self.stream:write_headers(self.res_headers, end_stream or false))
end

-- Send http headers to client
function route_methods:send_headers(end_stream)
	assert(self.stream:write_headers(self.res_headers, end_stream or false))
end

-- Send chunk of data to client
function route_methods:send(chunk, end_stream)
	assert(self.stream:write_chunk(chunk, end_stream or false))
end

-- Send file to client
function route_methods:send_file(fd)
	assert(self.stream:write_body_from_file(fd))
end

-- Send html head to client and starts a html body
function route_methods:std_html_head(headdata, bodyattr)
	headdata = headdata or ""
	bodyattr = bodyattr or ""
	self:send(string.format([[<!DOCTYPE html>
<html>
<head>%s
</head>
<body%s%s>]], headdata, bodyattr ~= "" and " " or "", bodyattr))
end

-- Finish off html body and the html document
function route_methods:std_html_done()
	self:send("\n</body>\n</html>", true)
end

-- Get available routes (handlers for different URIs)
function M.get_routes()
	return routes
end

-- Set routes (handlers for different URIs)
function M.set_routes(new_routes)
	if type(new_routes) == "table" then
		routes = new_routes
	else
		routes = {}
	end
end

-- The main handler that is being called by http server and that deals with
-- incoming http request.
--
-- It dispatches handling depending on the URI in the request.
function M.onstream(myserver, stream)
	-- Get headers
	local req_headers = assert(stream:get_headers())
	local req_method = req_headers:get ":method"
	local path = req_headers:get(":path") or ""
	local query
	local res_headers

	-- Log request to stdout
	assert(io.stdout:write(string.format('[%s] "%s %s HTTP/%g"  "%s" "%s"\n',
		os.date("%d/%b/%Y:%H:%M:%S %z"),
		req_method or "",
		path,
		stream.connection.version,
		req_headers:get("referer") or "-",
		req_headers:get("user-agent") or "-"
	)))

	-- Build response headers
	res_headers = http_headers.new()
	res_headers:append(":status", nil)

	if req_method ~= "GET" and req_method ~= "HEAD" and req_method ~= "POST" then
		res_headers:upsert(":status", "405")
		assert(stream:write_headers(res_headers, true))
		return
	end

	local uri_table = assert(uri_pattern:match(path), "invalid path")
	path = http_util.decodeURI(uri_table.path)

	-- Go through all routes to find handler.
	local handler_func, route_arg = nil, nil
	for pat, cand in pairs(routes) do
		route_arg = { path:match(pat) }
		if route_arg[1] ~= nil then
			handler_func = cand
			break
		end
	end

	if not handler_func then
		res_headers:upsert(":status", "404")
		assert(stream:write_headers(res_headers, true))
		return
	end

	if type(handler_func) == "number" then
		res_headers:upsert(":status", string.format("%d", handler_func))
		assert(stream:write_headers(res_headers, true))
		return
	end

	query = uri_table.query
	local ctx = setmetatable({
		stream = stream,
		server = myserver,
		req_method = req_method,
		req_headers = req_headers,
		res_headers = res_headers,
		path = path,
		query = query,
		route_arg = route_arg
	}, route_mt)
	handler_func(ctx)
	if stream.state == "idle" then
		res_headers:upsert(":status", "405")
		assert(stream:write_headers(res_headers, true))
		return
	end
end

return M
