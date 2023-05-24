#! /usr/bin/env nix-shell
--[[
#! nix-shell -i lua --packages "lua.withPackages(ps: with ps; [ luaexpat luadbi-sqlite3 ])"
]]

local lxp = require "lxp"
local animedb = require "animedb"

local function trim(s)
	return s:match("^%s*(.-)%s*$")
end

local function fixnumber(s)
	if type(s) == "number" then
		return s
	end
	if type(s) == "string" then
		local success, value, num

		s = trim(s)
		if s:find("^-?%d+$") == nil then
			return nil
		end
		num = tonumber(s)
		success, value = pcall(string.format, "%d", num)
		if success and value == s then
			return num
		end
		return s
	end
	return nil
end

local animeinfo = nil
local currtag = nil
local keep_tags = {
	["my_score"] = true,
	["my_tags"] = true,
	["my_watched_episodes"] = true,
	["my_status"] = true,
	["series_animedb_id"] = true,
	["series_title"] = true,
	["series_type"] = true,
	["series_episodes"] = true,
}

local add_anime

local function validate_animeninfo(animeinfo)
	if type(animeinfo) ~= "table" then
		return false
	end
	if type(animeinfo["series_title"]) ~= "string" then
		return false
	end
	if type(animeinfo["series_type"]) ~= "string" then
		return false
	end
	animeinfo["series_animedb_id"] = fixnumber(animeinfo["series_animedb_id"])
	if animeinfo["series_animedb_id"] == nil then
		return false
	end
	animeinfo["series_episodes"] = fixnumber(animeinfo["series_episodes"]) or 0
	animeinfo["my_score"] = fixnumber(animeinfo["my_score"]) or 0
	if animeinfo["my_score"] < 0 or animeinfo["my_score"] > 10 then
		return false
	end
	if animeinfo["my_tags"] ~= nil then
		if type(animeinfo["my_tags"]) ~= "string" then
			return false
		end
	else
		animeinfo["my_tags"] = ""
	end
	if animeinfo["my_status"] ~= nil then
		if type(animeinfo["my_status"]) ~= "string" then
			return false
		end
	else
		animeinfo["my_status"] = ""
	end
	animeinfo["my_watched_episodes"] = fixnumber(animeinfo["my_watched_episodes"]) or 0
	return true
end

local skipped = 0
callbacks = {
	StartElement = function(parser, name)
		if name == "anime" then
			animeinfo = {}
		elseif animeinfo == nil then
			return
		else
			currtag = name
		end
	end,
	EndElement = function(parser, name)
		if name == "anime" then
			if validate_animeninfo(animeinfo) then
				add_anime(animeinfo)
			else
				skipped = skipped + 1
			end
			animeinfo = nil
		elseif animeinfo ~= nil and animeinfo[name] ~= nil then
			animeinfo[name] = trim(animeinfo[name])
		end
		currtag = nil
	end,
	CharacterData = function(parser, data)
		if keep_tags[currtag] == true then
			if animeinfo[currtag] == nil then
				animeinfo[currtag] = data
			else
				animeinfo[currtag] = animeinfo[currtag] .. data
			end
		end
	end
}

local function import_reader(filename)
	p = lxp.new(callbacks)
	if filename == nil then
		error("No filename specified")
	end

	for l in io.lines(filename) do  -- iterate lines
		p:parse(l)          -- parses the line
		p:parse("\n")       -- parses the end of line
	end
	p:parse()               -- finishes the document
	p:close()

	if skipped > 0 then
		print("Skipped " .. skipped .. " entries")
	end
end

local function import_handler(dbh, animeinfo)
	local sql, stmt, animetype, animeid, statustype, tagid, mylistid, tag

	seriestype = animedb.insert_tag(animeinfo["series_type"], dbh)
	statustype = animedb.insert_tag(animeinfo["my_status"], dbh)

	animeid = animeinfo["series_animedb_id"]
	sql = "INSERT OR REPLACE INTO mylist(id, title, episodes, series_type, rate, watched_episodes, status) VALUES (?, ?, ?, ?, ?, ?, ?)"
	stmt = assert(dbh:prepare(sql))
	assert(stmt:execute(animeid, animeinfo["series_title"], animeinfo["series_episodes"], seriestype, animeinfo["my_score"], animeinfo["my_watched_episodes"], statustype))
	stmt:close()

	sql = "INSERT OR IGNORE INTO mytags(listid, tagid) VALUES (?, ?)"
	stmt = assert(dbh:prepare(sql))
	for tag in string.gmatch(animeinfo["my_tags"], "[^,]+") do
		tag = trim(tag)
		tagid = animedb.insert_tag(tag, dbh)
		assert(stmt:execute(animeid, tagid))
	end
	stmt:close()
end

do
	local dbh = animedb.open()

	animedb.create(dbh)

	add_anime = function(animeinfo)
		import_handler(dbh, animeinfo)
	end

	import_reader(arg[1])

	animedb.close(dbh)
end
