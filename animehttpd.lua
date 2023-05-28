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
local animedb = require "animedb"
local routes_handler = require "routes.handler"

routes_handler.set_routes {
	["^/anime/(%d+)$"] = function(ctx)
		ctx:std_header()
		ctx:std_html_head()
		ctx:send("Yay " .. ctx.route_arg[1])
		ctx:std_html_done(ctx)
	end;
	["^/res/([^/]+)$"] = require "routes.serve_file";
	["/favicon.ico$"] = 204;
	["^/$"] = require "routes.root";
}

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
	onstream = routes_handler.onstream;
	onerror = myerror;
})

-- Serve files relative to where this script lives.
-- (See routes/serve_file.lua)
myserver.webroot = rootdir

-- Assume the database lives in the same directory as this script
myserver.dbh = animedb.open(rootdir)

-- Setup signal handler that allows for cleanly shutting down the http server.
do
	local cq = assert(myserver.cq, "No cqueues for the server")
	local signal = require "cqueues.signal"
	local sl = signal.listen(signal.SIGTERM, signal.SIGINT)

	signal.block(signal.SIGTERM, signal.SIGINT)

	cq:wrap(function()
		local signo
		while true do
			signo = sl:wait()
			if signo == signal.SIGINT or signo == signal.SIGTERM then
				break
			end
		end
		signal.unblock(signal.SIGTERM, signal.SIGINT)
		myserver:close()
	end)
end

-- Manually call :listen() so that we are bound before calling :localname()
assert(myserver:listen())
do
	local bound_port = select(3, myserver:localname())
	assert(io.stderr:write(string.format("Now listening on port %d\n", bound_port)))
end

-- Start the main server loop
assert(myserver:loop())

-- Cleanup
if myserver.dbh then
	myserver.dbh:close()
	myserver.dbh = nil
end
