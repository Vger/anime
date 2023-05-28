local lfs = require "lfs"
local parse_http_date = require "parse_http_date"
local http_util = require "http.util"

local function handle_file(ctx, fd, file_path)
	local mod_since = ctx.req_headers:get("if-modified-since")
	if mod_since ~= nil then
		mod_since = parse_http_date(mod_since)
	end

	local res_headers = ctx.res_headers

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
	if file_path:match(".js$") then
		res_headers:append("content-type", "application/javascript")
	elseif file_path:match(".css$") then
		res_headers:append("content-type", "text/css")
	end
	ctx:send_headers(false)

	if req_method == "HEAD" or mod_since then
		return
	end
	ctx:send_file(fd)
end

return function(ctx)
	local file_path = string.format("%s/res/%s", ctx.server.webroot, ctx.route_arg[1])
	local fd = io.open(file_path, "rb")
	if not fd then
		ctx.res_headers:upsert(":status", "404")
		ctx:send_headers(true)
		return
	end

	local success, rc = pcall(handle_file, ctx, fd, file_path)
	fd:close()
	assert(success, rc)
	return rc
end
