local ThemePrefs = HV.LegacyPrefs

--- Holographic Void: Etterna Utility Functions
-- Consolidates grade calculation, clear types, score retrieval,
-- rate management, timing stats, and judge rescoring.
-- Ported with adaptation from spawncamping-wallhack.

------------------------------------------------------------
-- ROUNDING HELPERS
------------------------------------------------------------
notShit = notShit or {}
function notShit.floor(x, y)
	y = 10 ^ (y or 0)
	return math.floor(x * y) / y
end
function notShit.ceil(x, y)
	y = 10 ^ (y or 0)
	return math.ceil(x * y) / y
end
function notShit.round(x, y)
	y = 10 ^ (y or 0)
	return math.floor(x * y + 0.5) / y
end

------------------------------------------------------------
-- RATE MANAGEMENT
------------------------------------------------------------
function getCurRateValue()
	return notShit.round(GAMESTATE:GetSongOptionsObject("ModsLevel_Current"):MusicRate(), 3)
end

function getCurRate()
	local mods = GAMESTATE:GetSongOptionsString()
	if string.find(mods, "Haste") ~= nil then
		return "Haste"
	elseif string.find(mods, "xMusic") == nil then
		return "1.0x"
	else
		return (string.match(mods, "%d+%.%d+xMusic")):sub(1, -6)
	end
end

function getCurRateString()
	local r = string.format("%.2f", getCurRateValue()):gsub("%.?0+$", "") .. "x"
	if r == "1x" then r = "1.0x" end
	if r == "2x" then r = "2.0x" end
	return r
end

function getCurRateDisplayString()
	return getRateDisplayString(getCurRateString())
end

function getRateDisplayString(x)
	if x == "1x" then x = "1.0x"
	elseif x == "2x" then x = "2.0x" end
	return x .. "Music"
end

function changeMusicRate(amount)
    --local amount=amount/5
	local curRate = getCurRateValue()
	local newRate = curRate + amount
	if newRate <= 3 and newRate >= 0.05 then
		GAMESTATE:GetSongOptionsObject("ModsLevel_Preferred"):MusicRate(curRate + amount)
		GAMESTATE:GetSongOptionsObject("ModsLevel_Song"):MusicRate(curRate + amount)
		GAMESTATE:GetSongOptionsObject("ModsLevel_Current"):MusicRate(curRate + amount)
		MESSAGEMAN:Broadcast("CurrentRateChanged", {rate = newRate, oldRate = curRate})
	end
end

------------------------------------------------------------
-- GRADE CALCULATION & CUSTOM NAMES
------------------------------------------------------------
local function trimGradeLabel(s)
	if type(s) ~= "string" then return "" end
	local out, count, i = "", 0, 1
	while i <= #s and count < 5 do
		local c = s:byte(i)
		local n = (c < 128 and 1) or (c < 224 and 2) or (c < 240 and 3) or 4
		out = out .. s:sub(i, i + n - 1)
		i = i + n
		count = count + 1
	end
	return out
end

local gradeDefaults = {}
do
	local ok, data = pcall(dofile, "Scripts/CustomGrades.lua")
	if ok and type(data) == "table" then gradeDefaults = data end
end
if next(gradeDefaults) == nil then
	local fallback = {"AAAAA", "AAAA:", "AAAA.", "AAAA", "AAA:", "AAA.", "AAA", "AA:", "AA.", "AA", "A:", "A.", "A", "B", "C", "D"}
	for i, value in ipairs(fallback) do gradeDefaults[string.format("Grade_Tier%02d", i)] = value end
	gradeDefaults.Grade_Tier17, gradeDefaults.Grade_Failed, gradeDefaults.Grade_None = "Grade_Tier17", "F", "None"
end
local gradeConfigPath = HV.Config.SaveDirectory .. "/CustomGrades.lua"
local gradeConfig = nil
if FILEMAN:DoesFileExist(gradeConfigPath) then
	local f = RageFileUtil.CreateRageFile()
	if f:Open(gradeConfigPath, 1) then
		local chunk = loadstring(f:Read())
		if chunk then local ok, data = pcall(chunk); if ok and type(data) == "table" then gradeConfig = data end end
		f:Close()
	end
	f:destroy()
end
HV.CustomGrades = {}
for key, value in pairs(gradeDefaults) do HV.CustomGrades[key] = trimGradeLabel((gradeConfig and gradeConfig[key]) or value) end
function HV.GetTitleChoiceNames()
	local names = "Start,Multi,ColorTheme,PackDownloader,Options,Quit"
	local enabled = ThemePrefs.Get("HV_UseCustomGrades")
	if enabled == true or enabled == "true" then names = names .. ",CustomGrades" end
	return names
end

function HV.SaveCustomGrades()
	if FILEMAN.CreateDir then FILEMAN:CreateDir(HV.Config.SaveDirectory) end
	local f = RageFileUtil.CreateRageFile()
	if f:Open(gradeConfigPath, 2) then
		local out = "return {\n"
		for key, value in pairs(HV.CustomGrades) do out = out .. string.format("\t[%q] = %q,\n", key, trimGradeLabel(value)) end
		f:Write(out .. "}\n"); f:Close()
	end
	f:destroy()
end

function HV.GetGradeName(grade)
	if not grade then return "" end
	-- Safely extract the short name (e.g. "Tier01", "Failed")
	-- grade may be "Grade_Tier09" (full enum) or "Tier09" (already short)
	local s = grade:gsub("^Grade_", "")
	local key = "Grade_" .. s

	local pref = ThemePrefs.Get("HV_UseCustomGrades")
	if (pref == "true" or pref == true) and HV.CustomGrades[key] then
		return HV.CustomGrades[key]
	end

	-- Safe fallback for THEME:GetString
	if THEME:HasString("Grade", s) then
		return THEME:GetString("Grade", s)
	end

	-- Manual fallback mapping if THEME:HasString is somehow unreliable or missing
	local fallbacks = {
		Tier01 = "AAAAA", Tier02 = "AAAA:", Tier03 = "AAAA.", Tier04 = "AAAA",
		Tier05 = "AAA:", Tier06 = "AAA.", Tier07 = "AAA", Tier08 = "AA:",
		Tier09 = "AA.", Tier10 = "AA", Tier11 = "A:", Tier12 = "A.",
		Tier13 = "A", Tier14 = "B", Tier15 = "C", Tier16 = "D",
		Failed = "F", None = "None"
	}
	return fallbacks[s] or s
end

WifeTiers = {
	Grade_Tier01 = 0.999935, Grade_Tier02 = 0.9998, Grade_Tier03 = 0.9997,
	Grade_Tier04 = 0.99955,  Grade_Tier05 = 0.999,  Grade_Tier06 = 0.998,
	Grade_Tier07 = 0.997,    Grade_Tier08 = 0.99,   Grade_Tier09 = 0.965,
	Grade_Tier10 = 0.93,     Grade_Tier11 = 0.9,    Grade_Tier12 = 0.85,
	Grade_Tier13 = 0.8,      Grade_Tier14 = 0.7,    Grade_Tier15 = 0.6,
	Grade_Tier16 = 0.0,
}

WifeTierList = {
	"Grade_Tier01","Grade_Tier02","Grade_Tier03","Grade_Tier04",
	"Grade_Tier05","Grade_Tier06","Grade_Tier07","Grade_Tier08",
	"Grade_Tier09","Grade_Tier10","Grade_Tier11","Grade_Tier12",
	"Grade_Tier13","Grade_Tier14","Grade_Tier15","Grade_Tier16"
}

function isMidGrade(grade)
	return grade == "Grade_Tier02" or grade == "Grade_Tier03"
		or grade == "Grade_Tier05" or grade == "Grade_Tier06"
		or grade == "Grade_Tier08" or grade == "Grade_Tier09"
		or grade == "Grade_Tier11" or grade == "Grade_Tier12"
end

function getGradeFamilyForMidGrade(grade)
	if grade == "Grade_Tier02" or grade == "Grade_Tier03" then return "Grade_Tier04"
	elseif grade == "Grade_Tier05" or grade == "Grade_Tier06" then return "Grade_Tier07"
	elseif grade == "Grade_Tier08" or grade == "Grade_Tier09" then return "Grade_Tier10"
	elseif grade == "Grade_Tier11" or grade == "Grade_Tier12" then return "Grade_Tier14"
	else return grade end
end

function gradeFamilyToBetterGrade(grade)
	if grade == "Grade_Tier04" then return "Grade_Tier01"
	elseif grade == "Grade_Tier07" then return "Grade_Tier04"
	elseif grade == "Grade_Tier10" then return "Grade_Tier07"
	elseif grade == "Grade_Tier14" then return "Grade_Tier10"
	else
		if grade == "Grade_Tier01" then return grade
		else return string.format("Grade_Tier%02d", (tonumber(grade:sub(-2)) - 1)) end
	end
end

function getEtternaGrade(wifePct)
	if not wifePct then return "Failed" end
	local pct = wifePct / 100
	if pct >= 0.999935 then return "Tier01"
	elseif pct >= 0.9998 then return "Tier02"
	elseif pct >= 0.9997 then return "Tier03"
	elseif pct >= 0.99955 then return "Tier04"
	elseif pct >= 0.999 then return "Tier05"
	elseif pct >= 0.998 then return "Tier06"
	elseif pct >= 0.997 then return "Tier07"
	elseif pct >= 0.99 then return "Tier08"
	elseif pct >= 0.965 then return "Tier09"
	elseif pct >= 0.93 then return "Tier10"
	elseif pct >= 0.9 then return "Tier11"
	elseif pct >= 0.85 then return "Tier12"
	elseif pct >= 0.8 then return "Tier13"
	elseif pct >= 0.7 then return "Tier14"
	elseif pct >= 0.6 then return "Tier15"
	elseif pct >= 0.0 then return "Tier16"
	else return "Tier17" end
end

function getWifeGradeTier(percent)
	percent = percent / 100
	local midgrades = PREFSMAN:GetPreference("UseMidGrades")
	for _, v in pairs(WifeTierList) do
		if not midgrades and isMidGrade(v) then
			-- skip
		elseif percent > WifeTiers[v] then
			return v
		end
	end
	return "Grade_Tier16"
end

function getMaxNotes(pn)
	local steps = GAMESTATE:GetCurrentSteps()
	if steps then
		return steps:GetRadarValues(pn):GetValue("RadarCategory_Notes")
	end
	return 0
end

function getMaxScore(pn)
	return getMaxNotes(pn) * 2
end

function getGradeThreshold(pn, grade)
	local maxScore = getMaxScore(pn)
	if grade == "Grade_Failed" then return 0
	else return math.ceil(maxScore * (WifeTiers[grade] or 0)) end
end

function getNearbyGrade(pn, wifeScore, grade)
	local midgrades = PREFSMAN:GetPreference("UseMidGrades")
	if grade == "Grade_Tier01" then return grade, 0
	elseif grade == "Grade_Failed" then return "Grade_Tier16", wifeScore
	elseif grade == "Grade_None" then return "Grade_Tier16", 0
	else
		local nextGrade
		if not midgrades then
			local grd = getGradeFamilyForMidGrade(grade)
			nextGrade = gradeFamilyToBetterGrade(grd)
		else
			nextGrade = string.format("Grade_Tier%02d", (tonumber(grade:sub(-2)) - 1))
		end
		local gradeScore = getGradeThreshold(pn, grade)
		local nextGradeScore = getGradeThreshold(pn, nextGrade)
		local curGradeDiff = wifeScore - gradeScore
		local nextGradeDiff = wifeScore - nextGradeScore
		if math.abs(curGradeDiff) < math.abs(nextGradeDiff) then
			return grade, curGradeDiff
		else
			return nextGrade, nextGradeDiff
		end
	end
end

------------------------------------------------------------
-- CLEAR TYPE SYSTEM (IIDX-style)
------------------------------------------------------------
local clearTypeNames = {
	[4]="ClearType_MFC", [5]="ClearType_WF", [6]="ClearType_SDP",
	[7]="ClearType_PFC", [8]="ClearType_BF", [9]="ClearType_SDG",
	[10]="ClearType_FC", [12]="ClearType_MF", [13]="ClearType_SDCB",
	[14]="ClearType_EXHC", [15]="ClearType_HClear", [16]="ClearType_Clear",
	[17]="ClearType_EClear", [18]="ClearType_AClear", [19]="ClearType_Failed",
	[20]="ClearType_Invalid", [21]="ClearType_Noplay", [22]="ClearType_None",
}

local clearTypeReverse = {}
for k, v in pairs(clearTypeNames) do clearTypeReverse[v] = k end

------------------------------------------------------------
-- INVALIDATING MODIFIERS DETECTION
------------------------------------------------------------
function GetInvalidatingMods(pn)
	local ps = GAMESTATE:GetPlayerState(pn)
	if not ps then return {} end

	local mods = {}
	local modStr = ps:GetPlayerOptionsString("ModsLevel_Current"):lower()

	-- Remove mods (note-reduction)
	local checks = {
		["no mines"] = "NoMines", ["nomines"] = "NoMines",
		["no holds"] = "NoHolds", ["noholds"] = "NoHolds",
		["no rolls"] = "NoRolls", ["norolls"] = "NoRolls",
		["no hands"] = "NoHands", ["nohands"] = "NoHands",
		["no jumps"] = "NoJumps", ["nojumps"] = "NoJumps",
		["no lifts"] = "NoLifts", ["nolifts"] = "NoLifts",
		["no quads"] = "NoQuads", ["noquads"] = "NoQuads",
		["no stretch"] = "NoStretch", ["nostretch"] = "NoStretch",
		["no fakes"] = "NoFakes", ["nofakes"] = "NoFakes",
		["little"] = "Little",
		-- Insert mods (note-addition)
		["wide"] = "Wide", ["big"] = "Big", ["quick"] = "Quick",
		["bmrize"] = "BMRize", ["skippy"] = "Skippy",
		-- Pattern Transform mods
		["echo"] = "Echo", ["stomp"] = "Stomp", ["jackjs"] = "JackJS",
		["anchorjs"] = "AnchorJS", ["icyworld"] = "IcyWorld",
		-- Turn mods (multi-word first to avoid partial matches)
		["soft shuffle"] = "SoftShuffle", ["softshuffle"] = "SoftShuffle",
		["super shuffle"] = "SuperShuffle", ["supershuffle"] = "SuperShuffle",
		["hran shuffle"] = "HRanShuffle", ["hranshuffle"] = "HRanShuffle",
		["shuffle"] = "Shuffle",
		["backwards"] = "Backwards",
		-- Hold Transform mods
		["planted"] = "Planted", ["floored"] = "Floored",
		["twister"] = "Twister", ["holdrolls"] = "HoldRolls",
		["hold releases"] = "HoldReleases", ["holdreleases"] = "HoldReleases",
	}

	for pattern, name in pairs(checks) do
		if modStr:find(pattern) then
			table.insert(mods, name)
		end
	end

	-- Left/Right turns: use word-boundary frontier pattern to avoid false positives
	if modStr:find("%f[%a]left%f[%A]") then table.insert(mods, "TurnLeft") end
	if modStr:find("%f[%a]right%f[%A]") then table.insert(mods, "TurnRight") end

	-- Additive Mines: 'mines' present but NOT as 'no mines'
	if modStr:find("mines") and not modStr:find("no mines") then
		table.insert(mods, "Mines")
	end

	-- Gameplay Aids
	if getAutoplay and getAutoplay() ~= 0 then table.insert(mods, "Autoplay") end
	if GAMESTATE:IsPracticeMode() then table.insert(mods, "PracticeMode") end

	return mods
end

function IsScoreInvalid(score)
	if not score then return false end

	local mods = ""
	if score.GetModifiers then
		mods = score:GetModifiers():lower()
	elseif score.GetTapNoteScores then
		-- For live PlayerStageStats, check current game state
		if getAutoplay and getAutoplay() ~= 0 then return true end
		if GAMESTATE:IsPracticeMode() then return true end
		mods = GAMESTATE:GetPlayerState(PLAYER_1):GetPlayerOptionsString("ModsLevel_Current"):lower()
	else
		return false
	end

	local invalidating = {
		"no mines", "no holds", "no rolls", "no hands",
		"no jumps", "no lifts", "no quads", "no stretch",
		"no fakes", "little", "wide", "big", "quick",
		"bmrize", "skippy", "echo", "stomp", "jackjs",
		"anchorjs", "icyworld", "autoplay", "practice",
		-- Turns
		"backwards", "soft shuffle", "super shuffle", "hran shuffle", "shuffle",
		-- Hold Transforms
		"planted", "floored", "twister", "holdrolls", "hold releases",
	}
	for _, m in ipairs(invalidating) do
		if mods:find(m) or mods:find(m:gsub("%s+", "")) then return true end
	end
	-- Left/Right turns (word boundary)
	if mods:find("%f[%a]left%f[%A]") then return true end
	if mods:find("%f[%a]right%f[%A]") then return true end

	-- Additive mines/holds/rolls
	if mods:find("mines") and not mods:find("no mines") and not mods:find("nomines") then return true end
	if mods:find("holds") and not mods:find("no holds") and not mods:find("noholds") then return true end
	if mods:find("rolls") and not mods:find("no rolls") and not mods:find("norolls") then return true end

	-- 2. J4 Check (Legacy/Fallback)
	-- If the score is somehow flagged by engine, we can check here

	return false
end

function getClearTypeText(ct)
	return THEME:GetString("ClearTypes", ct)
end

function getClearTypeShortText(ct)
	-- If there's no specific short string, fallback to full
	if THEME:HasString("ClearTypesShort", ct) then
		return THEME:GetString("ClearTypesShort", ct)
	end
	return THEME:GetString("ClearTypes", ct)
end

local tapJudgmentKeys = {"W1", "W2", "W3", "W4", "W5", "Miss"}

local function readTapJudgments(score)
	local getTapScore = score.GetTapNoteScore or score.GetTapNoteScores
	if not getTapScore then return end
	local counts = {}
	for _, key in ipairs(tapJudgmentKeys) do
		counts[key] = getTapScore(score, "TapNoteScore_" .. key) or 0
	end
	return counts
end

function getClearLevel(pn, steps, score)
	if not score or not steps then return 21 end
	local chordCohesion
	if score.GetChordCohesion then
		chordCohesion = score:GetChordCohesion()
	else
		chordCohesion = not GAMESTATE:CountNotesSeparately()
	end
	local category = chordCohesion and "RadarCategory_TapsAndHolds" or "RadarCategory_Notes"
	local expectedTaps = steps:GetRadarValues(pn):GetValue(category)
	return getClearTypeLevel("ClearType_" .. getDetailedClearType(score, nil, expectedTaps))
end

function getClearType(pn, steps, score)
	return clearTypeNames[getClearLevel(pn, steps, score)]
end

function getClearTypeLevel(ct)
	return clearTypeReverse[ct] or 21
end


function getClearTypeColor(ct)
	return HVColor.GetClearTypeColor(ct) or color("1,1,1,1")
end

function getHighestClearType(pn, steps, scoreList, ignore)
	if steps == nil then return clearTypeNames[21] end
	local highest = 21
	if scoreList ~= nil then
		for i = 1, #scoreList do
			if i ~= ignore then
				local hScore = scoreList[i]
				if hScore ~= nil then
					local cl = getClearLevel(pn, steps, hScore)
					if cl ~= 20 then
						highest = math.min(highest, cl)
					end
				end
			end
		end
	end
	return clearTypeNames[highest]
end

------------------------------------------------------------
-- CLEAR TYPE (Detailed, from PSS)
------------------------------------------------------------
function getDetailedClearType(score, counts, expectedTaps)
	if not score then return "Failed" end
	if IsScoreInvalid(score) then return "Invalid" end
	local getGrade = score.GetWifeGrade or score.GetGrade
	local grade = getGrade and getGrade(score)
	if not grade or grade == "Grade_Failed" or grade == "Grade_None" then return "Failed" end

	counts = counts or readTapJudgments(score)
	if not counts then return "Failed" end
	local tapBreaks = counts.W4 + counts.W5 + counts.Miss
	if expectedTaps and counts.W1 + counts.W2 + counts.W3 + tapBreaks ~= expectedTaps then
		return "Invalid"
	end

	if tapBreaks > 0 then
		if tapBreaks == 1 then return "MF" end
		if tapBreaks < 10 then return "SDCB" end
		return "Clear"
	end

	if counts.W3 == 1 then return "BF" end
	if counts.W3 > 0 then return counts.W3 < 10 and "SDG" or "FC" end
	if counts.W2 == 1 then return "WF" end
	if counts.W2 > 0 then return counts.W2 < 10 and "SDP" or "PFC" end
	return "MFC"
end

------------------------------------------------------------
-- SCORE RETRIEVAL & COMPARISON
------------------------------------------------------------
function GetDisplayScore()
	local pn = PLAYER_1
	local steps = GAMESTATE:GetCurrentSteps()
	if not steps then return nil end

	local currentRateValue = getCurRateValue()
	local rateTable = getRateTable(pn, steps)
	if not rateTable then return nil end

	-- 1. Try current rate first
	local currentRateStr = getCurRateString()
	local currentScores = rateTable[currentRateStr]
	if currentScores and #currentScores > 0 then
		-- Use J4-normalized comparison to find the best for this rate
		local bestOfRate = nil
		local bestOfRatePct = -math.huge
		for i = 1, #currentScores do
			local s = currentScores[i]
			if not IsScoreInvalid(s) then
				local p = getJ4NormalizedPercentage(s)
				if p > bestOfRatePct then
					bestOfRatePct = p
					bestOfRate = s
				end
			end
		end
		return bestOfRate
	end

	-- 2. No scores for current rate, find the closest one
	local closestRate = nil
	local minDiff = math.huge
	local bestScore = nil
	local bestScorePct = -math.huge

	for rateStr, scores in pairs(rateTable) do
		if scores and #scores > 0 then
			local rNum = tonumber((rateStr:gsub("x", ""))) or 0
			local diff = math.abs(rNum - currentRateValue)

			-- Find the best score for this specific rate first
			local bestInThisRate = nil
			local bestInThisRatePct = -math.huge
			for i = 1, #scores do
				local s = scores[i]
				if not IsScoreInvalid(s) then
					local p = getJ4NormalizedPercentage(s)
					if p > bestInThisRatePct then
						bestInThisRatePct = p
						bestInThisRate = s
					end
				end
			end

			if bestInThisRate and diff < minDiff then
				minDiff = diff
				closestRate = rateStr
				bestScore = bestInThisRate
				bestScorePct = bestInThisRatePct
			elseif bestInThisRate and math.abs(diff - minDiff) < 0.0001 then
				-- If rates are equally close, pick the one with better J4 normalized percentage
				if bestInThisRatePct > bestScorePct then
					bestScore = bestInThisRate
					bestScorePct = bestInThisRatePct
				end
			end
		end
	end

	return bestScore
end

function getScoreGrade(score)
	if score ~= nil then return score:GetWifeGrade()
	else return "Grade_None" end
end

function getScore(score, steps, percent)
	if percent == nil then percent = true end
	if score ~= nil and steps ~= nil then
		local pn = GAMESTATE:GetEnabledPlayers()[1]
		local notes = steps:GetRadarValues(pn):GetValue("RadarCategory_Notes")
		if percent then return score:GetWifeScore()
		else return score:GetWifeScore() * notes * 2 end
	end
	return 0
end

function getScoreComboBreaks(score)
	if score == nil then return 0 end
	return score:GetTapNoteScore("TapNoteScore_W4")
		+ score:GetTapNoteScore("TapNoteScore_W5")
		+ score:GetTapNoteScore("TapNoteScore_Miss")
end

function getScoreMaxCombo(score)
	if score == nil then return 0 end
	return score:GetMaxCombo()
end

function getHighScoreIndex(hsTable, score)
	if hsTable == nil then return 0 end
	for i, hs in ipairs(hsTable) do
		if hs:GetDate() == score:GetDate() and
			math.abs(hs:GetWifeScore() - score:GetWifeScore()) < 0.0001 then
			return i
		end
	end
	return 0
end

-- Rate table: returns {["1.0x"] = {score1, score2, ...}, ...}
function getRateTable(pn, steps)
	pn = pn or GAMESTATE:GetEnabledPlayers()[1]
	steps = steps or GAMESTATE:GetCurrentSteps()
	if not steps then return nil end
	local ck = steps:GetChartKey()
	if not ck then return nil end
	local sl = SCOREMAN:GetScoresByKey(ck)
	if sl == nil then return nil end
	local o = {}
	for k, v in pairs(sl) do
		o[k] = v:GetScores()
	end
	return o
end

function getScoreTable(pn, rate, steps)
	if not rate then rate = "1.0x" end
	local rtTable = getRateTable(pn, steps)
	if not rtTable then return nil end
	return rtTable[rate]
end

function getRate(score)
	if score == nil then return "1.0x" end
	local r = string.format("%.2f", score:GetMusicRate()):gsub("%.?0+$", "") .. "x"
	if r == "1x" then r = "1.0x" end
	if r == "2x" then r = "2.0x" end
	return r
end

function getBestScore(pn, ignore, rate, percent)
	if not rate then rate = "1.0x" end
	local highest = -math.huge
	local bestScore
	local hsTable = getScoreTable(pn, rate)
	if hsTable ~= nil and #hsTable >= 1 then
		for k, v in ipairs(hsTable) do
			if k ~= ignore then
				local indexScore = hsTable[k]
				if indexScore ~= nil and not IsScoreInvalid(indexScore) then
					local temp = getJ4NormalizedPercentage(indexScore)
					if temp >= highest then
						highest = temp
						bestScore = indexScore
					end
				end
			end
		end
	end
	return bestScore
end

function getBestMissCount(pn, ignore, rate)
	if not rate then rate = "1.0x" end
	local lowest = math.huge
	local bestScore
	local hsTable = getScoreTable(pn, rate)
	if hsTable ~= nil and #hsTable >= 1 then
		for i = 1, #hsTable do
			if i ~= ignore then
				local indexScore = hsTable[i]
				if indexScore ~= nil and not IsScoreInvalid(indexScore) then
					if indexScore:GetGrade() ~= "Grade_Failed" then
						local temp = getScoreComboBreaks(indexScore)
						if temp < lowest then
							lowest = temp
							bestScore = indexScore
						end
					end
				end
			end
		end
	end
	return bestScore
end

function getBestMaxCombo(pn, ignore, rate)
	if not rate then rate = "1.0x" end
	local highest = 0
	local bestScore
	local hsTable = getScoreTable(pn, rate)
	if hsTable ~= nil and #hsTable >= 1 then
		for i = 1, #hsTable do
			if i ~= ignore then
				local indexScore = hsTable[i]
				if indexScore ~= nil and not IsScoreInvalid(indexScore) then
					local temp = getScoreMaxCombo(indexScore)
					if temp > highest then
						highest = temp
						bestScore = indexScore
					end
				end
			end
		end
	end
	return bestScore
end

------------------------------------------------------------
-- TIMING STATISTICS
------------------------------------------------------------
function wifeMean(t)
	local c = #t
	local m = 0
	if c == 0 then
		return 0
	end
	local o = 0
	for i = 1, c do
		-- ignore EO misses and replay mines
		if t[i] ~= 1000 and t[i] ~= -1100 then
			o = o + t[i]
		else
			m = m + 1
		end
	end
	return o / (c - m)
end

function wifeAbsMean(t)
	local c = #t
	local m = 0
	if c == 0 then
		return 0
	end
	local o = 0
	for i = 1, c do
		-- ignore EO misses and replay mines
		if t[i] ~= 1000 and t[i] ~= -1100 then
			o = o + math.abs(t[i])
		else
			m = m + 1
		end
	end
	return o / (c - m)
end

function wifeSd(t)
	local u = wifeMean(t)
	local u2 = 0
	local m = 0
	for i = 1, #t do
		-- ignore EO misses and replay mines
		if t[i] ~= 1000 and t[i] ~= -1100 then
			u2 = u2 + (t[i] - u) ^ 2
		else
			m = m + 1
		end
	end
	if (#t - 1 - m) <= 0 then return 0 end
	return math.sqrt(u2 / (#t - 1 - m))
end

function wifeRange(t)
	local x, y = 10000, 0
	for i = 1, #t do
		if math.abs(t[i]) <= 180 then		-- some replays (online ones i think?) are flagging misses as 1100 for some reason
			if math.abs(t[i]) < math.abs(x) then
				x = t[i]
			end
			if math.abs(t[i]) > math.abs(y) then
				y = t[i]
			end
		end
	end
	return x, y
end

function wifeMax(t)
	local _, y = wifeRange(t)
	return math.abs(y)
end

------------------------------------------------------------
-- JUDGE RESCORING
------------------------------------------------------------
-- For Window-based Scoring

function getRescoredJudge(offsetVector, judgeScale, judge)
	if type(offsetVector) ~= "table" then return 0 end

	local target = tapJudgmentKeys[tonumber(judge) or 1]
	if not target then return 0 end
	local windows = HV.Judgment.GetWindows(ms.JudgeScalers[judgeScale])
	local count = 0
	for _, value in ipairs(offsetVector) do
		local offset = tonumber(value)
		if offset and HV.Judgment.ClassifyOffset(offset, windows) == target then
			count = count + 1
		end
	end
	return count
end

-- erf constants
local a1 =  0.254829592
local a2 = -0.284496736
local a3 =  1.421413741
local a4 = -1.453152027
local a5 =  1.061405429
local p  =  0.3275911

function erf(x)
	-- Save the sign of x
	local sign = 1
	if x < 0 then
		sign = -1
	end
	x = math.abs(x)

	-- A&S formula 7.1.26
	local t = 1.0/(1.0 + p*x)
	local y = 1.0 - (((((a5*t + a4)*t) + a3)*t + a2)*t + a1)*t*math.exp(-x*x)

	return sign*y
end

function wife3(maxms, ts, version)
	maxms = tonumber(maxms) or 0
	ts = ts or 1.0
	local max_points = 2
	local miss_weight = -5.5
	local fullScoreWindow = 5 * ts
	local max_boo_weight = 180 * ts
	local ts_pow = 0.75
	local zero = 65 * (ts^ts_pow)
	local dev = 22.7 * (ts^ts_pow)

	-- case handling
	if maxms <= fullScoreWindow then
		return max_points
	elseif maxms <= zero then			-- ma/pa region, exponential
			return max_points * erf((zero - maxms) / dev)
	elseif maxms <= max_boo_weight then -- cb region, linear
		return (maxms - zero) * miss_weight / (max_boo_weight - zero)
	else							-- we can just set miss values manually
		return miss_weight			-- technically the max boo is always 180 above j4 however this is immaterial to the
	end								-- purpose of the scoring curve, which is to assign point values
end

function getRescoredWife3Judge(version, judgeScale, rst, useCurrent)
	if type(rst) ~= "table" then return 0 end
	local tso = ms.JudgeScalers
	local ts = (tso and tso[judgeScale]) or 1.0
	local totalPoints, replayMisses = 0, 0
	local dvt = rst["dvt"]

	if type(dvt) == "table" then
		for i = 1, #dvt do
			local offset = tonumber(dvt[i])
			if offset and math.abs(offset) <= 180.001 then
				totalPoints = totalPoints + wife3(math.abs(offset), ts, version)
			elseif offset and math.abs(offset) >= 1000 and offset ~= -1100 then
				replayMisses = replayMisses + 1
			end
		end
	end

	totalPoints = totalPoints - math.max(replayMisses, tonumber(rst.misses) or 0) * 5.5

	-- Penalize holds, rolls, and mines.

	totalPoints = totalPoints + (math.max(0, tonumber(rst["holdsMissed"]) or 0) * -4.5)
	totalPoints = totalPoints + (math.max(0, tonumber(rst["rollsMissed"]) or 0) * -4.5)
	totalPoints = totalPoints + (math.max(0, tonumber(rst["minesHit"]) or 0) * -7)

	-- Use notesPassed for live percentage, totalNotes for evaluation.
	local maxNotes = 0
	if useCurrent then
		maxNotes = math.max(0, tonumber(rst["notesPassed"]) or 0)
	else
		maxNotes = math.max(0, tonumber(rst["totalNotes"]) or 0)
		maxNotes = math.max(maxNotes, tonumber(rst["notesPassed"]) or 0)
		-- For evaluation, we must penalize unplayed notes (from failing early) as misses.
		local unplayed = math.max(0, maxNotes - (tonumber(rst["notesPassed"]) or 0))
		totalPoints = totalPoints - (unplayed * 5.5) -- unhit notes are unhit
	end

	if maxNotes <= 0 then return 0 end
	local maxPoints = maxNotes * 2

	return math.min((totalPoints / maxPoints) * 100.0, 100), totalPoints, maxPoints
end

function HV.IsReplayPlayback()
	local state = GAMESTATE and GAMESTATE:GetPlayerState(PLAYER_1)
	return state and state.GetPlayerController and state:GetPlayerController() == "PlayerController_Replay"
end

function HV.GetOnlineReplayPlayerName()
	if HV.OnlineReplayActive then
		return HV.OnlineReplayName or "Online Player"
	end
end

function getMainBPM(song, steps)
	if not song then return 0 end
	local bpms = song:GetDisplayBpms(true)
	if not bpms or not bpms[1] then return 0 end
	if bpms[1] == bpms[2] then return bpms[1] end
	local timing = song:GetTimingData()
	local lastSecond = 0
	if steps and steps.GetLastSecond then
		local ok, value = pcall(function() return steps:GetLastSecond() end)
		if ok then lastSecond = tonumber(value) or 0 end
	end
	if lastSecond <= 0 and song.GetLastSecond then
		local ok, value = pcall(function() return song:GetLastSecond() end)
		if ok then lastSecond = tonumber(value) or 0 end
	end
	if not timing or lastSecond <= 0 then return bpms[1] end
	local durations = {}
	local sampleStep = 0.1
	for second = 0, math.max(0, lastSecond - sampleStep), sampleStep do
		local beat = timing:GetBeatFromElapsedTime(second + sampleStep / 2)
		local bpm = timing:GetBPMAtBeat(beat)
		if bpm and bpm > 0 then
			local key = math.round(bpm * 1000) / 1000
			durations[key] = (durations[key] or 0) + sampleStep
		end
	end
	local main, longest = bpms[1], 0
	for bpm, duration in pairs(durations) do
		if duration > longest then main, longest = bpm, duration end
	end
	return main
end

function HV.GetReplayCurrentWifePercentage(pss)
	if not pss then return nil end
	local notesPassed = 0
	for _, judgment in ipairs({"W1", "W2", "W3", "W4", "W5", "Miss"}) do
		local ok, count = pcall(pss.GetTapNoteScores, pss, "TapNoteScore_" .. judgment)
		if ok then notesPassed = notesPassed + (tonumber(count) or 0) end
	end
	if notesPassed > 0 and type(pss.GetWifePoints) == "function" then
		local ok, points = pcall(pss.GetWifePoints, pss)
		if ok and tonumber(points) then
			return (tonumber(points) / (notesPassed * 2)) * 100
		end
	end
	return nil
end

local function hvNonNegativeCount(value)
	value = tonumber(value) or 0
	if value < 0 then return 0 end
	return value
end

local function hvCallNumber(obj, methodName, ...)
	if obj and type(obj[methodName]) == "function" then
		local ok, value = pcall(obj[methodName], obj, ...)
		if ok then
			return hvNonNegativeCount(value)
		end
	end
	return 0
end

local function hvTapCount(obj, scoreName)
	local value = hvCallNumber(obj, "GetTapNoteScores", scoreName)
	if value > 0 then return value end
	return hvCallNumber(obj, "GetTapNoteScore", scoreName)
end

local function hvHoldCount(obj, scoreName)
	local value = hvCallNumber(obj, "GetHoldNoteScores", scoreName)
	if value > 0 then return value end
	return hvCallNumber(obj, "GetHoldNoteScore", scoreName)
end

local function hvReplayVector(replay, methodName)
	if replay and type(replay[methodName]) == "function" then
		local ok, value = pcall(replay[methodName], replay)
		if ok and type(value) == "table" then
			return value
		end
	end
	return {}
end

function getRescoreElements(pss, score, offsets)
	local o = {}

	-- Base counts from PlayerStageStats (Live Stats)
	if pss then
		local ok, offsets = pcall(function() return pss:GetOffsetVector() end)
		o["dvt"] = ok and type(offsets) == "table" and offsets or {}
		o["misses"] = hvTapCount(pss, "TapNoteScore_Miss")
		o["holdsMissed"] = hvHoldCount(pss, "HoldNoteScore_LetGo") + hvHoldCount(pss, "HoldNoteScore_MissedHold")
		o["rollsMissed"] = 0
		o["minesHit"] = hvTapCount(pss, "TapNoteScore_HitMine")

		-- Count hits
		local hits = 0
		for _, name in ipairs({"W1","W2","W3","W4","W5"}) do
			hits = hits + hvTapCount(pss, "TapNoteScore_"..name)
		end
		o["tapsHit"] = hits
		o["notesPassed"] = hits + o["misses"]

		local steps = GAMESTATE:GetCurrentSteps()
		local radar = steps and steps:GetRadarValues(PLAYER_1)
		o["totalHolds"] = hvNonNegativeCount(radar and radar:GetValue("RadarCategory_Holds"))
		o["totalRolls"] = hvNonNegativeCount(radar and radar:GetValue("RadarCategory_Rolls"))
		o["totalMines"] = hvNonNegativeCount(radar and radar:GetValue("RadarCategory_Mines"))
		o["totalNotes"] = hvNonNegativeCount(radar and radar:GetValue("RadarCategory_Notes"))
		if o["totalNotes"] <= 0 then
			o["totalNotes"] = o["notesPassed"]
		end
	elseif score then
		-- Use the Score-based retrieval (Moved from SelectMusic for global use)
		return getRescoreElementsFromScore(score, offsets)
	end

	return o
end

function getRescoreElementsFromScore(score, offsets)
	if not score then return end
	if not offsets then
		if not score.HasReplayData or not score:HasReplayData() or not score.GetReplay then return end
		local replay = score:GetReplay()
		if not replay or not replay:LoadAllData() then return end

		local vector = hvReplayVector(replay, "GetOffsetVector")
		local types = hvReplayVector(replay, "GetTapNoteTypeVector")
		offsets = {}
		for i, offset in ipairs(vector) do
			local kind = types[i]
			if #types == 0 or kind == "TapNoteType_Tap" or kind == "TapNoteType_HoldHead" or kind == "TapNoteType_Lift" then
				offsets[#offsets + 1] = offset
			end
		end
	end
	local o = {dvt = offsets}

	o["misses"] = hvTapCount(score, "TapNoteScore_Miss")
	o["holdsMissed"] = hvHoldCount(score, "HoldNoteScore_LetGo") + hvHoldCount(score, "HoldNoteScore_MissedHold")
	o["rollsMissed"] = 0
	o["minesHit"] = hvTapCount(score, "TapNoteScore_HitMine")

	local hits = 0
	for _, name in ipairs({"W1","W2","W3","W4","W5"}) do
		hits = hits + hvTapCount(score, "TapNoteScore_"..name)
	end
	o["tapsHit"] = hits
	o["notesPassed"] = hits + o["misses"]

	local steps = score.GetChartKey and SONGMAN:GetStepsByChartKey(score:GetChartKey())
	local radar = steps and steps:GetRadarValues(PLAYER_1)
	o["totalHolds"] = hvNonNegativeCount(radar and radar:GetValue("RadarCategory_Holds"))
	if o["totalHolds"] <= 0 then
		o["totalHolds"] = hvHoldCount(score, "HoldNoteScore_Held") + o["holdsMissed"]
	end
	o["totalRolls"] = hvNonNegativeCount(radar and radar:GetValue("RadarCategory_Rolls"))
	o["totalMines"] = hvNonNegativeCount(radar and radar:GetValue("RadarCategory_Mines"))
	if o["totalMines"] <= 0 then
		o["totalMines"] = hvTapCount(score, "TapNoteScore_AvoidMine") + o["minesHit"]
	end
	o["totalNotes"] = hvNonNegativeCount(radar and radar:GetValue("RadarCategory_Notes"))
	if o["totalNotes"] <= 0 then
		o["totalNotes"] = o["notesPassed"]
	end

	return o
end

function HV.Score.GetDisplayJudgments(score, judge)
	if not judge or HV.Score.GetPlayedJudge(score) == judge then return readTapJudgments(score) end
	local rst = getRescoreElementsFromScore(score)
	local hits = rst and HV.Judgment.GetReplayHits(rst.dvt, nil, rst.tapsHit)
	if hits then return HV.Judgment.RescoreHits(hits, rst.misses, judge) end
end

function HV.Score.GetDisplayTally(score, judge)
	local counts = HV.Score.GetDisplayJudgments(score, judge)
	if not counts then return "-" end
	local tally = {}
	for i, key in ipairs(tapJudgmentKeys) do tally[i] = counts[key] end
	return table.concat(tally, " | "), counts
end

------------------------------------------------------------
-- OSU!MANIA TAP RESCORING
------------------------------------------------------------
HV.ManiaJudgementNames = {"MAX", "300", "200", "100", "50", "MISS"}
HV.ManiaJudgementPoints = {320, 300, 200, 100, 50, 0}
-- Score V1 accuracy: MAX and 300 both worth 1.0 (denominator 300 per note)
HV.ManiaJudgementAccuracy = {1, 1, 2 / 3, 1 / 3, 1 / 6, 0}
-- Score V2 accuracy: denominator is 305; MAX=305, 300=300, 200=200, 100=100, 50=50, MISS=0
HV.ManiaJudgementAccuracyV2 = {305/305, 300/305, 200/305, 100/305, 50/305, 0}
HV.ManiaState = HV.ManiaState or {enabled = false, od = 8.0, useScoreV2 = false}

function HV.ResetManiaMode()
	HV.ManiaState.enabled = false
	HV.ManiaState.od = 8.0
	HV.ManiaState.useScoreV2 = false
end

function HV.ToggleManiaMode()
	HV.ManiaState.enabled = not HV.ManiaState.enabled
	return HV.ManiaState.enabled
end

function HV.ToggleManiaScoreV2()
	HV.ManiaState.useScoreV2 = not HV.ManiaState.useScoreV2
	return HV.ManiaState.useScoreV2
end

function HV.SetManiaOD(value)
	HV.ManiaState.od = math.max(0, math.min(11, math.floor((tonumber(value) or 8) * 10 + 0.5) / 10))
	return HV.ManiaState.od
end

function HV.GetOrderedReplayTapOffsets(score, judgeByOldestNote)
	local replay = score:GetReplay()
	if not replay then return {}, false end
	pcall(function() replay:LoadAllData() end)
	local offsets = hvReplayVector(replay, "GetOffsetVector") or {}
	local rows = hvReplayVector(replay, "GetNoteRowVector") or {}
	local tracks = hvReplayVector(replay, "GetTrackVector") or {}
	local types = hvReplayVector(replay, "GetTapNoteTypeVector") or {}
	local taps = {}
	for i, offset in ipairs(offsets) do
		local typ = types[i]
		if #types == 0 or typ == "TapNoteType_Tap" or typ == "TapNoteType_HoldHead" or typ == "TapNoteType_Lift" then
			taps[#taps + 1] = {
				offset = tonumber(offset) or 0,
				row = tonumber(rows[i]) or i,
				track = tonumber(tracks[i]) or i,
				index = i
			}
		end
	end
	if judgeByOldestNote then
		table.sort(taps, function(a, b)
			if a.row == b.row then return a.track < b.track end
			return a.row < b.row
		end)
	end
	local orderedOffsets = {}
	for _, tap in ipairs(taps) do orderedOffsets[#orderedOffsets + 1] = tap.offset end
	return orderedOffsets, judgeByOldestNote == true, taps
end

function HV.GetOsuManiaRescore(score, od, judgeByOldestNote)
	od = math.max(0, math.min(11, tonumber(od) or 8))
	local offsets, reprioritized = HV.GetOrderedReplayTapOffsets(score, judgeByOldestNote)
	-- ScoreV2's PERFECT window changes slope at OD 5 while remaining
	-- continuous: 22.4 - 0.6*OD through OD 5, then 24.9 - 1.1*OD.
	-- ScoreV1 used a flat 16ms MAX window regardless of OD.
	local perfectWindow
	if HV.ManiaState.useScoreV2 then
		perfectWindow = od <= 5 and (22.4 - 0.6 * od) or (24.9 - 1.1 * od)
	else
		perfectWindow = 16
	end
	local maxErrors = {perfectWindow, 64 - 3 * od, 97 - 3 * od, 127 - 3 * od, 151 - 3 * od, 188 - 3 * od}
	local counts = {0, 0, 0, 0, 0, 0}
	local points, accuracy = 0, 0
	for _, offset in ipairs(offsets) do
		local error = math.floor(math.abs(offset) + 0.5)
		local judgement = 6
		for i = 1, 5 do
			if error <= math.floor(maxErrors[i] + 0.5) then judgement = i; break end
		end
		counts[judgement] = counts[judgement] + 1
		points = points + HV.ManiaJudgementPoints[judgement]
		local accTable = HV.ManiaState.useScoreV2 and HV.ManiaJudgementAccuracyV2 or HV.ManiaJudgementAccuracy
		accuracy = accuracy + accTable[judgement]
	end
	return {
		od = od, counts = counts, points = points,
		maxPoints = #offsets * 320,
		accuracy = #offsets > 0 and (accuracy / #offsets) or 0,
		windows = maxErrors, reprioritized = reprioritized
	}
end

function getJ4NormalizedPercentage(score)
	if not score then return 0, false end
	local wife = score:GetWifeScore() * 100
	-- The native HighScore binding already returns its stored J4 value in this mode.
	if PREFSMAN:GetPreference("SortBySSRNormPercent") or HV.Score.GetPlayedJudge(score) == 4 then
		return wife, true
	end

	local rst = getRescoreElementsFromScore(score)
	local hits = rst and HV.Judgment.GetReplayHits(rst.dvt, nil, rst.tapsHit)
	if hits then
		rst.dvt = hits
		local percent = getRescoredWife3Judge(3, 4, rst)
		return percent, true
	end
	return wife, false
end

------------------------------------------------------------
-- JUDGMENT HELPERS
------------------------------------------------------------
function getJudgeStrings(tns)
	return THEME:GetString("TapNoteScore", ToEnumShortString(tns))
end

-- Song length color (from sc-wh) -- unused for now?
function getSongLengthColor(len)
	if len > 600 then return color("#ff3333")
	elseif len > 300 then return color("#ffaa33")
	elseif len > 120 then return color("#ffff33")
	else return color("#cccccc") end
end

-- Common BPM from BPM+time list
function getCommonBPM(bpmsAndTimes, lastBeat)
	if not bpmsAndTimes or #bpmsAndTimes == 0 then return 0 end
	-- Simplified: return the BPM that takes up the most time
	local bpmDurations = {}
	for i = 1, #bpmsAndTimes do
		local bpm = bpmsAndTimes[i][2]
		local startBeat = bpmsAndTimes[i][1]
		local endBeat = lastBeat
		if i < #bpmsAndTimes then
			endBeat = bpmsAndTimes[i + 1][1]
		end
		local dur = endBeat - startBeat
		bpmDurations[bpm] = (bpmDurations[bpm] or 0) + dur
	end
	local maxDur = 0
	local commonBPM = 0
	for bpm, dur in pairs(bpmDurations) do
		if dur > maxDur then
			maxDur = dur
			commonBPM = bpm
		end
	end
	return commonBPM
end

-- NOTE: getAvatarPath() is provided by _fallback/Scripts/12 AssetsUtils.lua
-- Do NOT override it here. It uses the assetsConfig system (per-GUID).

------------------------------------------------------------
-- MISC ACTOR HELPERS
------------------------------------------------------------
function Alpha(c, a)
	return {c[1], c[2], c[3], a}
end

function Saturation(c, s)
	if type(c) ~= "table" then return c end
	local r, g, b = c[1] or 0, c[2] or 0, c[3] or 0
	local gray = r * 0.299 + g * 0.587 + b * 0.114
	return {gray + (r - gray) * s, gray + (g - gray) * s, gray + (b - gray) * s, c[4] or 1}
end

function SecondsToMSS(s)
	if not s or s < 0 then return "0:00" end
	return string.format("%d:%02d", math.floor(s / 60), math.floor(s % 60))
end

HV.GameplaySessionValid = false

function HV.GetPlayerName(pn)
	pn = pn or PLAYER_1
	local onlineName = (pn == PLAYER_1) and DLMAN:GetUsername() or ""
	if onlineName and onlineName ~= "" then
		return onlineName
	end
	local profile = PROFILEMAN:GetProfile(pn)
	if profile then
		local name = profile:GetDisplayName()
		if name and name ~= "" then return name end
	end
	return "Player " .. (pn == PLAYER_1 and "1" or "2")
end

Trace("Holographic Void: 08 EtternaUtils.lua loaded (expanded).")
