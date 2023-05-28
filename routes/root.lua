-- Escape special characters when outputting the html page.
local xml_escape = require "xml_escape"

local function root_get(ctx)
	local dbh, row, filtertag = ctx.server.dbh

	for k, v in ctx:query_args() do
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

	stmt = dbh:get_list(filtertag)

	ctx:send([[
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
		ctx:send(string.format([[
<tr>
<td>%s</td>
<td>%d</td>
<td>%d/%d%s</td>
<td>%s</td>
</tr>
]], xml_escape(row["title"]), row["rate"], row["watched_episodes"], row["episodes"], increase_progress, xml_escape(tags)))
	end
	stmt:close()

	ctx:send("</table>")
end

return function(ctx)
	local req_method = ctx.req_method
	if req_method == "HEAD" then
		ctx:std_header(true)
		return
	end
	if req_method ~= "GET" then
		return
	end
	ctx:std_header()
	ctx:std_html_head([[<script src="res/list.js"></script>]])
	root_get(ctx)
        ctx:std_html_done()
end
