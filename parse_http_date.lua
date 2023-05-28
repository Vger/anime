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

-- Parse http date that appears in some headers
return function(date)
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
