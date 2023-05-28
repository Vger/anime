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
<div id="list">
<table border="0" cellpadding="0" cellspacing="0" width="100%" align="center">
<tr>
<th class="th_left">Title</th>
<th class="th">Rate</th>
<th class="th">Progress</th>
<th class="th">Tags</th>
</tr>]])

	local altrow = 1
	for row in stmt:rows(true) do
		local tags = string.gsub(row["tags"] or "", ",", ", ")
		local increase_progress = ""
		if row["watched_episodes"] < row["episodes"] then
			increase_progress = string.format([[
<a href="javascript:increase_progress(%d)">+</a>]], row["id"])
		end
		ctx:send(string.format([[
<tr class="tr%d">
<td class="td_left">%s</td>
<td class="td">%d</td>
<td class="td">%d/%d%s</td>
<td class="td_tag">%s</td>
</tr>
]], altrow,
xml_escape(row["title"]),
row["rate"],
row["watched_episodes"], row["episodes"], increase_progress,
xml_escape(tags)))
		altrow = altrow + 1
		if altrow > 2 then
			altrow = 1
		end
	end
	stmt:close()

	ctx:send("</table></div>")
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
	ctx:std_html_head([[<script src="res/list.js"></script>
<link rel="stylesheet" href="res/list.css" type="text/css"/>]], [[onload="make_tags()"]])
	root_get(ctx)
        ctx:std_html_done()
end
