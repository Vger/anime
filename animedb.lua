local dbi = require "DBI"

local M = {}

local animedb_methods = {}

local animedb_mt = {
	__index = animedb_methods
}

function M.open(dir)
	dir = dir or "."
	local dbh = assert(dbi.Connect("SQLite3", dir .. "/myanime.sqlite3"))
	return setmetatable({
		dbh = dbh
	}, animedb_mt)
end

function animedb_methods:create()
	local dbh, sql, stmt = self.dbh

	sql = "CREATE TABLE IF NOT EXISTS tags (id INTEGER PRIMARY KEY, tag TEXT NOT NULL);"
	stmt = assert(dbh:prepare(sql))
	assert(stmt:execute())
	stmt:close()

	sql = "CREATE UNIQUE INDEX IF NOT EXISTS idx_tags ON tags (tag);"
	stmt = assert(dbh:prepare(sql))
	assert(stmt:execute())
	stmt:close()

	sql = "CREATE TABLE IF NOT EXISTS mylist (id INTEGER PRIMARY KEY, title TEXT NOT NULL COLLATE NOCASE, episodes INTEGER, series_type INTEGER, rate INTEGER, watched_episodes INTEGER, status INTEGER, FOREIGN KEY(series_type) REFERENCES tags(id), FOREIGN KEY(status) REFERENCES tags(id));"
	stmt = assert(dbh:prepare(sql))
	assert(stmt:execute())
	stmt:close()

	sql = "CREATE TABLE IF NOT EXISTS mytags (listid INTEGER, tagid INTEGER, FOREIGN KEY(listid) REFERENCES mylist(id), FOREIGN KEY(tagid) REFERENCES tags(id), PRIMARY KEY(listid, tagid));"
	stmt = assert(dbh:prepare(sql))
	assert(stmt:execute())
	stmt:close()

	dbh:commit()
end

function animedb_methods:close()
	local dbh = self.dbh
	if not dbh then return end

	dbh:commit()
	dbh:close()
	self.dbh = nil
end

function animedb_methods:insert_tag(tag)
	local dbh, sql, stmt, row = self.dbh

	sql = "SELECT id FROM tags WHERE tag=?"
	stmt = assert(dbh:prepare(sql))
	assert(stmt:execute(tag))

	row = stmt:fetch(false)
	if row and row[1] then
		return row[1]
	end
	stmt:close()

	sql = "INSERT INTO tags(tag) VALUES(?)"
	stmt = assert(dbh:prepare(sql))
	assert(stmt:execute(tag))

	return dbh:last_id()
end

-- Get sqlite3 statement that lists all anime titles belonging to user.
-- Optionally include/exclude entries based on tags.
function animedb_methods:get_list(filtertag)
	local dbh, sql, stmt = self.dbh

	if filtertag == nil then
		sql = [[
SELECT l.id AS id,
l.title AS title,
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
SELECT l.id AS id,
l.title AS title,
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
	return stmt
end

return M
