local escape_table = {
	["'"] = "&apos;";
	["\""] = "&quot;";
	["<"] = "&lt;";
	[">"] = "&gt;";
	["&"] = "&amp;";
}

-- Escape special characters when outputting the html page.
return function(str)
	str = string.gsub(str or "", "['&<>\"]", escape_table)
	str = string.gsub(str, "[%c\r\n]", function(c)
		return string.format("&#x%x;", string.byte(c))
	end)
	return str
end
