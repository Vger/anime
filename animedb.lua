local dbi = require "DBI"

local M = {}

function M.open()
	M.dbh = assert(dbi.Connect("SQLite3", "myanime.sqlite3"))
	return M.dbh
end

function M.create(dbh)
	local sql, stmt
	dbh = dbh or M.dbh

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

function M.close(dbh)
	dbh = dbh or M.dbh
	if not dbh then return end

	dbh:commit()
	dbh:close()
end

function M.insert_tag(tag, dbh)
	local sql, stmt, row

	dbh = dbh or M.dbh

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

return M
