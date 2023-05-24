#! /usr/bin/env nix-shell
--[[
#! nix-shell -i lua --packages "lua.withPackages(ps: with ps; [ basexx binaryheap compat53 cqueues fifo lpeg lpeg_patterns luaossl luadbi-sqlite3 ])"
]]

local port = arg[1] or 8000

-- Adapt the search path for lua modules, in order to use the
-- http-server library located in sub-directory lua-http
package.path = package.path .. ";./lua-http/?.lua"

local http_server = require "http.server"
local http_headers = require "http.headers"
local http_util = require "http.util"
local lpeg = require "lpeg"
local uri_pattern = require "lpeg_patterns.uri".uri_reference * lpeg.P(-1)
local animedb = require "animedb"
local dbh = nil

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

local function handle_get(stream, path, query)
	local sql, stmt, row, filtertag
	dbh = dbh or animedb.open()

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

	if filtertag == nil then
		sql = [[
SELECT l.title AS title,
l.episodes AS episodes,
l.rate AS rate,
l.watched_episodes AS watched_episodes,
GROUP_CONCAT(t.tag) AS tags
FROM mylist l
LEFT JOIN mytags mt ON l.id = mt.listid
LEFT JOIN tags t ON mt.tagid = t.id
GROUP BY title ORDER BY title;]]
		stmt = assert(dbh:prepare(sql))
		assert(stmt:execute())
	else
		local numincludes = filtertag.include and #filtertag.include or 0
		local numexcludes = filtertag.exclude and #filtertag.exclude or 0
		local execvars = {}
		sql = [[
SELECT l.title AS title,
l.episodes AS episodes,
l.rate AS rate,
l.watched_episodes AS watched_episodes,
GROUP_CONCAT(t.tag) AS tags
FROM mylist l
JOIN mytags mt ON l.id = mt.listid
JOIN tags t ON mt.tagid = t.id
]]

		if numincludes > 0 then
			sql = sql .. string.format([[
WHERE l.id IN
(SELECT listid
FROM mytags mt
JOIN tags t ON mt.tagid = t.id
WHERE t.tag IN (%s))
]], string.rep(',?', numincludes):sub(2))
			for i=1, numincludes do
				execvars[#execvars + 1] = filtertag.include[i]
			end
		end
		if numexcludes > 0 then
			sql = sql .. ((numincludes > 0) and " AND " or " WHERE ") .. string.format([[
l.id NOT IN
(SELECT listid
FROM mytags mt
JOIN tags t ON mt.tagid = t.id
WHERE t.tag IN (%s))
]], string.rep(',?', numexcludes):sub(2))
			for i=1, numexcludes do
				execvars[#execvars + 1] = filtertag.exclude[i]
			end
		end
		sql = sql .. "GROUP BY title ORDER BY title;"
		stmt = assert(dbh:prepare(sql))
		assert(stmt:execute(table.unpack(execvars)))
	end

	assert(stream:write_chunk([[
<table>
<tr>
<th>Title</th>
<th>Rate</th>
<th>Progress</th>
<th>Tags</th>
</tr>]], false))

	for row in stmt:rows(true) do
		assert(stream:write_chunk(string.format([[
<tr>
<td>%s</td>
<td>%d</td>
<td>%d/%d</td>
<td>%s</td>
</tr>
]], xml_escape(row["title"]), row["rate"], row["watched_episodes"], row["episodes"], xml_escape(row["tags"])), false))
	end
	stmt:close()

	assert(stream:write_chunk([[
</table>
]], false))
end

local function myreply(myserver, stream)
	-- Get headers
	local req_headers = assert(stream:get_headers())
	local req_method = req_headers:get ":method"
	local path = req_headers:get(":path") or ""

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
	local res_headers = http_headers.new()
	res_headers:append(":status", nil)

	if req_method ~= "GET" and req_method ~= "HEAD" then
		res_headers:upsert(":status", "405")
		assert(stream:write_headers(res_headers, true))
		return
	end

	local uri_table = assert(uri_pattern:match(path), "invalid path")
	path = http_util.decodeURI(uri_table.path)
	query = uri_table.query
	if path:find("favicon.ico$") then
		res_headers:upsert(":status", "404")
		assert(stream:write_headers(res_headers, true))
		return
	end

	res_headers:upsert(":status", "200")
	res_headers:append("content-type", "text/html; charset=utf-8")

	-- Send headers to client
	assert(stream:write_headers(res_headers, req_method == "HEAD"))
	if req_method == "HEAD" then
		return
	end
	assert(stream:write_chunk([[
<!DOCTYPE html>
<html>
<head>
</head>
<body>]], false))
	handle_get(stream, path, query)
assert(stream:write_chunk([[
</body>
</html>
	]], true))
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
