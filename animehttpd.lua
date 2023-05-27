#! /usr/bin/env nix-shell
--[[
#! nix-shell -i lua --packages "lua.withPackages(ps: with ps; [ basexx binaryheap compat53 cqueues fifo lpeg lpeg_patterns luafilesystem luaossl luadbi-sqlite3 ])"
]]

local rootdir = arg[0]:match("^(.*)/[^/]*$")
local port = arg[1] or 8000

-- If running this program from another directory, then adapt the
-- search path to look in the same directory as this script.
if rootdir ~= "." then
	package.path = package.path .. ";" .. rootdir .. "/?.lua"
end

-- Adapt the search path for lua modules, in order to use the
-- http-server library located in sub-directory lua-http
package.path = package.path .. ";" .. rootdir .. "/lua-http/?.lua"

local http_server = require "http.server"
local http_headers = require "http.headers"
local http_util = require "http.util"
local lpeg = require "lpeg"
local uri_pattern = require "lpeg_patterns.uri".uri_reference * lpeg.P(-1)
local animedb = require "animedb"
local dbh = nil
local lfs = require "lfs"

-- Escape special characters when outputting the html page.
local xml_escape
do
	local escape_table = {
		["'"] = "&apos;";
		["\""] = "&quot;";
		["<"] = "&lt;";
		[">"] = "&gt;";
		["&"] = "&amp;";
	}
	function xml_escape(str)
		str = string.gsub(str or "", "['&<>\"]", escape_table)
		str = string.gsub(str, "[%c\r\n]", function(c)
			return string.format("&#x%x;", string.byte(c))
		end)
		return str
	end
end

local parse_http_date
do
	local diff

	local months = {
		["Jan"] = 1,
		["Feb"] = 2,
		["Mar"] = 3,
		["Apr"] = 4,
		["May"] = 5,
		["Jun"] = 6,
		["Jul"] = 7,
		["Aug"] = 8,
		["Sep"] = 9,
		["Oct"] = 10,
		["Nov"] = 11,
		["Dec"] = 12
	}

	local function timediff()
		-- Use current time (in epoch seconds) as fixed time point, and find
		-- out the time representation both for UTC+0 and local timezone.
		local now = os.time()
		local tm_local = os.date("*t", now)
		local tm_utc = os.date("!*t", now)

		-- View the above 2 broken-down time representation as if they're
		-- local time. This gives the second difference between UTC+0 and
		-- local timezone. Daylight saving's time is considered if it's
		-- in effect.
		tm_local.isdst = nil
		local t1 = os.time(tm_utc)
		local t2 = os.time(tm_local)
		return t1 - t2
	end

	-- Only need to calculate the timezone difference once.
	diff = timediff()

	function parse_http_date(date)
		local day, month, year, hour, min, sec = string.match(date, "^%S%S%S, (%d+) (%S%S%S) (%d%d%d%d) (%d%d):(%d%d):(%d%d)")
		-- Construct time representation. Since the wanted timezone is UTC+0,
		-- daylight saving's time is hardcoded to false.
		local timeinfo = {
			["day"] = tonumber(day),
			["month"] = months[month],
			["year"] = tonumber(year),
			["hour"] = tonumber(hour),
			["min"] = tonumber(min),
			["sec"] = tonumber(sec),
			["isdst"] = false
		}
		local localtime = os.time(timeinfo)
		return localtime - diff
	end

end

-- Send standard http headers to client
local function std_header(ctx, end_stream)
	ctx.res_headers:upsert(":status", "200")
	ctx.res_headers:append("content-type", "text/html; charset=utf-8")
	ctx.res_headers:append("cache-control", "no-cache")
	assert(ctx.stream:write_headers(ctx.res_headers, end_stream or false))
end

-- Send a chunk of the html page to client
local function send_bodychunk(ctx, chunk, end_stream)
	if ctx.stream.state == "idle" then
		std_header(ctx)
		assert(ctx.stream.state ~= "idle")
	end
	assert(ctx.stream:write_chunk(chunk, end_stream or false))
end

local function std_html_head(ctx, headdata)
	send_bodychunk(ctx, string.format([[<!DOCTYPE html>
<html>
<head>%s
</head>
<body>]], headdata or ""))
end

local function std_html_done(ctx)
	assert(ctx.stream:write_chunk([[
</body>
</html>
]], true))
end

local function root_get(ctx)
	local stream, query = ctx.stream, ctx.query
	local row, filtertag
	dbh = dbh or animedb.open(rootdir)

	if query ~= nil then
		for k, v in http_util.query_args(query) do
			if k == "e" and v ~= nil then
				filtertag = filtertag or {}
				filtertag.exclude = filtertag.exclude or {}
				filtertag.exclude[#filtertag.exclude + 1] = v
			end
			if k == "i" and v ~= nil then
				filtertag = filtertag or {}
				filtertag.include = filtertag.include or {}
				filtertag.include[#filtertag.include + 1] = v
			end
		end
	end

	stmt = animedb.get_list(filtertag, dbh)

	send_bodychunk(ctx, [[
<table>
<tr>
<th>Title</th>
<th>Rate</th>
<th>Progress</th>
<th>Tags</th>
</tr>]])

	for row in stmt:rows(true) do
		local tags = string.gsub(row["tags"] or "", ",", ", ")
		local increase_progress = ""
		if row["watched_episodes"] < row["episodes"] then
			increase_progress = string.format([[
<a href="javascript:increase_progress(%d)">+</a>]], row["id"])
		end
		send_bodychunk(ctx, string.format([[
<tr>
<td>%s</td>
<td>%d</td>
<td>%d/%d%s</td>
<td>%s</td>
</tr>
]], xml_escape(row["title"]), row["rate"], row["watched_episodes"], row["episodes"], increase_progress, xml_escape(tags)))
	end
	stmt:close()

	send_bodychunk(ctx, "</table>")
end

local function resource_handler(ctx)
	local req_method, stream, res_headers, file = ctx.req_method, ctx.stream, ctx.res_headers, ctx.route_arg[1]

	local file_path = rootdir .. "/res/" .. file
	local fd = io.open(file_path)
	if not fd then
		res_headers:upsert(":status", "404")
		assert(stream:write_headers(res_headers, false))
		return
	end

	local mod_since = ctx.req_headers:get("if-modified-since")
	if mod_since ~= nil then
		mod_since = parse_http_date(mod_since)
	end

	local attr = lfs.attributes(file_path)
	local mod_time = attr["modification"]
	if mod_since and mod_time <= mod_since then
		res_headers:upsert(":status", "304")
	else
		res_headers:upsert(":status", "200")
		mod_since = nil
	end
	res_headers:append("date", http_util.imf_date())
	res_headers:append("last-modified", http_util.imf_date(mod_time))
	res_headers:append("cache-control", "no-cache")
	res_headers:append("content-length", string.format("%d", attr["size"]))
	if file:match(".js$") then
		res_headers:append("content-type", "application/javascript")
	elseif file:match(".css$") then
		res_headers:append("content-type", "text/css")
	end
	assert(stream:write_headers(res_headers, false))

	if req_method == "HEAD" or mod_since then
		return
	end
	assert(stream:write_body_from_file(fd))
	fd:close()
end

local function root_handler(ctx)
	local req_method = ctx.req_method
	if req_method == "GET" or req_method == "HEAD" then
		std_header(ctx, req_method == "HEAD")
	else
		return
	end
	if req_method == "HEAD" then
		return
	end
	std_html_head(ctx, [[
<script src="res/list.js"></script>
]])
	root_get(ctx)
        std_html_done(ctx)
end

local routes = {
	["^/anime/(%d+)$"] = function(ctx)
		std_header(ctx)
		std_html_head(ctx)
		send_bodychunk(ctx, "Yay " .. ctx.route_arg[1])
		std_html_done(ctx)
	end,
	["^/res/([^/]+)$"] = resource_handler,
	["/favicon.ico$"] = 204,
	["^/$"] = root_handler
}

local function myreply(myserver, stream)
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
	handler_func { stream = stream,
		req_method = req_method,
		req_headers = req_headers,
		res_headers = res_headers,
		path = path,
		query = query,
		route_arg = route_arg
	}
	if stream.state == "idle" then
		res_headers:upsert(":status", "405")
		assert(stream:write_headers(res_headers, true))
		return
	end
end

local function myerror(myserver, context, op, err, errno)
	local msg = op .. " on " .. tostring(context) .. " failed"
	if err then
		msg = msg .. ": " .. tostring(err)
	end
	assert(io.stderr:write(msg, "\n"))
end

local myserver = assert(http_server.listen {
	host = "localhost";
	port = port;
	onstream = myreply;
	onerror = myerror;
})

-- Manually call :listen() so that we are bound before calling :localname()
assert(myserver:listen())
do
	local bound_port = select(3, myserver:localname())
	assert(io.stderr:write(string.format("Now listening on port %d\n", bound_port)))
end
-- Start the main server loop
assert(myserver:loop())
