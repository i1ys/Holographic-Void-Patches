local ThemePrefs = HV.LegacyPrefs
local scoreTabPlot = ... == "ScoreTab"

--- Holographic Void: Offset Plot Graph
-- Ported from spawncamping-wallhack OffsetGraph.lua
-- Shows timing offsets as colored dots on a time axis with judgment threshold lines.
-- Supports judge rescoring via OffsetPlotModification messages.
-- Supports hand-specific highlighting via ToggleHands.
-- Supports hover tooltip showing running score/stats at cursor position.

local tst = ms.JudgeScalers
local judge = math.max(1, math.min(9, PREFSMAN:GetPreference("SortBySSRNormPercent") and 4 or GetTimingDifficulty()))
local tso = tst[judge]
local plotScale = 100
local maxOffset = math.max(180, 180 * (tso or 1))

local function clampJudge()
	if judge < 1 then judge = 1 end
	if judge > 9 then judge = 9 end
end
clampJudge()

local function updateMaxOffset()
	maxOffset = math.max(180, 180 * (tso or 1)) * plotScale / 100
end

local function setPlotScale(scale)
	plotScale = math.max(5, math.min(100, scale))
	updateMaxOffset()
	MESSAGEMAN:Broadcast("JudgeDisplayChanged")
end

local dotWidth = 2
local finalSecond = 1
local plotParams
local setScoreKey
local setWidth, setHeight = 0, 0
local setRate = 1
local setMania, setChordCohesion = false, false
local handIndex = 1
local evenHands, oddHands = {"All", "L", "R"}, {"All", "L", "M", "R"}
local handLabels = {L = "Left", M = "Middle", R = "Right"}
local usingCustomWindows = false

local trendMetricModes = {
	{id = "wife", label = "Wife%"},
	{id = "grade", label = "Grade"},
	{id = "clear", label = "Clear"},
	{id = "mean", label = "Mean"},
	{id = "ma", label = "MA"},
	{id = "pa", label = "PA"},
	{id = "off", label = "Off"},
}
local trendColorModes = {
	{id = "none", label = "None"},
	{id = "grade", label = "Grade"},
	{id = "clear", label = "Clear Type"},
}

-- Load saved preferences or use defaults
local function getSavedOrDefault(prefName, defaultVal)
	if ThemePrefs and ThemePrefs.Get then
		local val = ThemePrefs.Get(prefName)
		if val ~= nil then return val end
	end
	return defaultVal
end

local savedMetricId = getSavedOrDefault("HV_OffsetGraphTrendMetric", "wife")
local trendMetricIndex = 1
for i, mode in ipairs(trendMetricModes) do
	if mode.id == savedMetricId then trendMetricIndex = i break end
end

local savedColorId = getSavedOrDefault("HV_OffsetGraphTrendColor", "none")
local trendColorModeIndex = 1
for i, mode in ipairs(trendColorModes) do
	if mode.id == savedColorId then trendColorModeIndex = i break end
end

local selectedSliceX1 = nil
local selectedSliceX2 = nil
local slicePercent = getSavedOrDefault("HV_OffsetGraphSlicePercent", 25)
local hoverModeOptions = {
	{id = "point", label = "Point"},
	{id = "slice", label = "Slice"},
}
local savedHoverId = getSavedOrDefault("HV_OffsetGraphHoverMode", "point")
local hoverModeIndex = 1
for i, mode in ipairs(hoverModeOptions) do
	if mode.id == savedHoverId then hoverModeIndex = i break end
end
local setSliceByCenterX

local function clampValue(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

local function getMouseLocalX(bg)
	if not bg or bg:GetZoomedWidth() <= 0 then return 0 end
	local x = (INPUTFILTER:GetMouseX() - bg:GetTrueX()) * setWidth / bg:GetZoomedWidth()
	return clampValue(x, 0, setWidth)
end

local function getCurrentSlicePercent()
	return slicePercent
end

-- Forward declaration (defined later after trend indices are set up)
local saveGraphPrefs

local function adjustSlicePercent(delta)
	delta = delta or 0
	slicePercent = clampValue((slicePercent or 25) + delta, 1, 100)
	if selectedSliceX1 and selectedSliceX2 then
		setSliceByCenterX((selectedSliceX1 + selectedSliceX2) / 2)
	end
	if saveGraphPrefs then saveGraphPrefs() end
	MESSAGEMAN:Broadcast("JudgeDisplayChanged")
end

local function getCurrentHoverModeId()
	return hoverModeOptions[hoverModeIndex].id
end

local function cycleHoverMode(step)
	step = step or 1
	hoverModeIndex = hoverModeIndex + step
	if hoverModeIndex > #hoverModeOptions then hoverModeIndex = 1 end
	if hoverModeIndex < 1 then hoverModeIndex = #hoverModeOptions end
	if getCurrentHoverModeId() == "point" then
		selectedSliceX1 = nil
		selectedSliceX2 = nil
	end
	if saveGraphPrefs then saveGraphPrefs() end
	MESSAGEMAN:Broadcast("JudgeDisplayChanged")
end

local function getJudgeWindows()
	local windows = HV.Judgment.GetWindows(tso)
	if usingCustomWindows and getCustomWindowConfigJudgmentWindow then
		windows.W1 = getCustomWindowConfigJudgmentWindow("TapNoteScore_W1") or windows.W1
		windows.W2 = getCustomWindowConfigJudgmentWindow("TapNoteScore_W2") or windows.W2
		windows.W3 = getCustomWindowConfigJudgmentWindow("TapNoteScore_W3") or windows.W3
		windows.W4 = getCustomWindowConfigJudgmentWindow("TapNoteScore_W4") or windows.W4
		windows.W5 = getCustomWindowConfigJudgmentWindow("TapNoteScore_W5") or windows.W5
	end
	return windows
end

local judgmentKeys = {"W1", "W2", "W3", "W4", "W5", "Miss"}

local plotEvents, prefixes = {}, {}
local middleColumn = 1.5
local oddColumns = false
local handStats = {}
local comboBreaks = {}

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function isTapType(kind)
	return kind == "TapNoteType_Tap" or kind == "TapNoteType_HoldHead" or kind == "TapNoteType_Lift"
end

local function rangeStats(first, last)
	local before, after = prefixes[first - 1], prefixes[last]
	if not after or first > last then return end
	local stats = {notes = after.notes - before.notes, judgments = {}}
	for i, key in ipairs(judgmentKeys) do
		stats.judgments[key] = after[i] - before[i]
	end
	local hits = after.hits - before.hits
	if hits > 0 then
		local sum = after.sum - before.sum
		stats.mean = sum / hits
		if hits > 1 then
			local squares = after.squares - before.squares
			stats.sd = math.sqrt(math.max(0, (squares - sum * sum / hits) / (hits - 1)))
		end
	end
	if not usingCustomWindows and not setMania and stats.notes > 0 then
		stats.wife = (after.points - before.points) / (stats.notes * 2) * 100
	end
	return stats
end

local function buildPlot(params)
	plotEvents, prefixes, handStats = {}, {}, {}
	comboBreaks = {total = 0, L = 0, M = 0, R = 0}
	if not params.steps then return end
	local timing = params.steps:GetTimingData()
	local rows, offsets = params.nrv or {}, params.dvt or {}
	local tracks, types, misses = params.ctt or {}, params.ntt or {}, params.misses or {}
	local windows = getJudgeWindows()
	local recordedMisses, inputMisses = {}, {}
	local useWife = not usingCustomWindows and not setMania

	local function add(row, track, offset, isMiss)
		if not finite(row) then return end
		local time = timing:GetElapsedTimeFromNoteRow(row)
		if not finite(time) then return end
		if not finite(track) or track < 0 then track = nil end
		local bucket = isMiss and "Miss" or HV.Judgment.ClassifyOffset(offset, windows)
		-- Etterna's standard Wife3 miss weight is -5.5 points.
		local points = useWife and (isMiss and -5.5 or wife3(math.abs(offset), tso)) or 0
		plotEvents[#plotEvents + 1] = {
			time = math.max(0, time), row = row, track = track, offset = offset,
			miss = isMiss, bucket = bucket, points = points, order = #plotEvents + 1,
		}
	end

	local function recordMiss(source, row, track)
		if not finite(row) then return end
		local entry = source[row] or {tracks = {}, count = 0}
		if not finite(track) or track < 0 then
			entry.count = entry.count + 1
		elseif not entry.tracks[track] then
			entry.tracks[track] = true
			entry.count = entry.count + 1
		end
		source[row] = entry
	end

	for i, row in ipairs(rows) do
		local offset, kind = offsets[i], types[i]
		if finite(row) and finite(offset) and (#types == 0 or isTapType(kind)) then
			if math.abs(offset) >= 1000 then
				recordMiss(recordedMisses, row, tracks[i])
			elseif math.abs(offset) <= 180.001 then
				add(row, tracks[i], offset, false)
			end
		end
	end

	-- Newer input replays can store misses separately from legacy sentinels.
	for _, miss in ipairs(misses) do
		if not miss.noteType or isTapType(miss.noteType) then
			recordMiss(inputMisses, miss.row, miss.track)
		end
	end
	for row, input in pairs(inputMisses) do
		local recorded = recordedMisses[row]
		if recorded then
			input.count = math.max(input.count, recorded.count)
			for track in pairs(recorded.tracks) do input.tracks[track] = true end
		end
		recordedMisses[row] = input
	end
	for row, missesAtRow in pairs(recordedMisses) do
		local known = 0
		for track in pairs(missesAtRow.tracks) do
			add(row, track, nil, true)
			known = known + 1
		end
		-- Unknown lanes may already be represented by a known lane at this row.
		for _ = known + 1, missesAtRow.count do add(row, nil, nil, true) end
	end

	table.sort(plotEvents, function(a, b)
		if a.time ~= b.time then return a.time < b.time end
		if a.row ~= b.row then return a.row < b.row end
		return a.order < b.order
	end)

	local tally = {0, 0, 0, 0, 0, 0, notes = 0, points = 0, hits = 0, sum = 0, squares = 0}
	prefixes[0] = tally
	for i, event in ipairs(plotEvents) do
		local nextTally = {
			notes = i, points = tally.points + event.points,
			hits = tally.hits, sum = tally.sum, squares = tally.squares,
		}
		for j, key in ipairs(judgmentKeys) do
			nextTally[j] = tally[j] + (event.bucket == key and 1 or 0)
		end
		if event.offset ~= nil then
			nextTally.hits = tally.hits + 1
			nextTally.sum = tally.sum + event.offset
			nextTally.squares = tally.squares + event.offset * event.offset
		end
		local brokeCombo = event.bucket == "W4" or event.bucket == "W5" or event.bucket == "Miss"
		if brokeCombo then comboBreaks.total = comboBreaks.total + 1 end
		if event.track ~= nil then
			local side = event.track < middleColumn and "L" or (event.track == middleColumn and "M" or "R")
			if brokeCombo then comboBreaks[side] = comboBreaks[side] + 1 end
			local hand = handStats[side] or {notes = 0, points = 0}
			hand.notes = hand.notes + 1
			hand.points = hand.points + event.points
			handStats[side] = hand
		end
		prefixes[i], tally = nextTally, nextTally
	end
end

local function countThrough(time, inclusive)
	local left, right = 1, #plotEvents
	while left <= right do
		local middle = math.floor((left + right) / 2)
		local event = plotEvents[middle]
		if event.time < time or (inclusive and event.time == time) then
			left = middle + 1
		else
			right = middle - 1
		end
	end
	return right
end

local function getHandWife(side)
	local hand = handStats[side]
	if hand and not usingCustomWindows and not setMania and not setChordCohesion then
		return hand.points / (hand.notes * 2) * 100
	end
end

local function setPlotScaleToWorstHit()
	local worst = 0
	for _, event in ipairs(plotEvents) do
		if event.offset ~= nil then worst = math.max(worst, math.abs(event.offset)) end
	end
	if worst > 0 then
		setPlotScale(math.ceil(worst / math.max(180, 180 * tso) * 100))
	end
end

local function xForTime(seconds)
	return clampValue(seconds / finalSecond, 0, 1) * setWidth
end

local function timeForX(x)
	return x / setWidth * finalSecond
end

local function getClearTypeFromCounts(judgments)
	local w2 = judgments.W2 or 0
	local w3 = judgments.W3 or 0
	local w4 = judgments.W4 or 0
	local w5 = judgments.W5 or 0
	local miss = judgments.Miss or 0
	local cb = w4 + w5 + miss

	if cb > 0 then
		if cb == 1 then return "ClearType_MF" end
		if cb < 10 then return "ClearType_SDCB" end
		return "ClearType_Clear"
	end

	if w3 > 0 then
		if w3 == 1 then return "ClearType_BF" end
		if w3 < 10 then return "ClearType_SDG" end
		return "ClearType_FC"
	end

	if w2 > 0 then
		if w2 == 1 then return "ClearType_WF" end
		if w2 < 10 then return "ClearType_SDP" end
		return "ClearType_PFC"
	end

	return "ClearType_MFC"
end

local function gradeToNumeric(grade)
	local s = tostring(grade or "")
	local tier = tonumber(s:match("Tier(%d+)"))
	if tier then
		tier = clampValue(tier, 1, 17)
		return ((17 - tier) / 16) * 100
	end
	if s:find("Failed") then return 0 end
	return 0
end

local function clearTypeToNumeric(clearType)
	local level = getClearTypeLevel and getClearTypeLevel(clearType) or 18
	level = clampValue(level, 1, 19)
	return ((19 - level) / 18) * 100
end

local function getCurrentTrendMetricId()
	return trendMetricModes[trendMetricIndex].id
end

local function getCurrentTrendColorModeId()
	return trendColorModes[trendColorModeIndex].id
end

saveGraphPrefs = function()
	if ThemePrefs and ThemePrefs.Set then
		ThemePrefs.Set("HV_OffsetGraphTrendMetric", trendMetricModes[trendMetricIndex].id)
		ThemePrefs.Set("HV_OffsetGraphTrendColor", trendColorModes[trendColorModeIndex].id)
		ThemePrefs.Set("HV_OffsetGraphSlicePercent", slicePercent)
		ThemePrefs.Set("HV_OffsetGraphHoverMode", hoverModeOptions[hoverModeIndex].id)
	end
end

local function cycleTrendMetric(step)
	step = step or 1
	trendMetricIndex = trendMetricIndex + step
	if trendMetricIndex > #trendMetricModes then trendMetricIndex = 1 end
	if trendMetricIndex < 1 then trendMetricIndex = #trendMetricModes end
	if saveGraphPrefs then saveGraphPrefs() end
	MESSAGEMAN:Broadcast("JudgeDisplayChanged")
end

local function cycleTrendColorMode(step)
	step = step or 1
	trendColorModeIndex = trendColorModeIndex + step
	if trendColorModeIndex > #trendColorModes then trendColorModeIndex = 1 end
	if trendColorModeIndex < 1 then trendColorModeIndex = #trendColorModes end
	if saveGraphPrefs then saveGraphPrefs() end
	MESSAGEMAN:Broadcast("JudgeDisplayChanged")
end

local function currentHand()
	return (oddColumns and oddHands or evenHands)[handIndex]
end

local function metricValue(metric, stats, grade, clear)
	if metric == "wife" then return stats.wife end
	if metric == "grade" then return grade and gradeToNumeric(grade) end
	if metric == "clear" then return clear and clearTypeToNumeric(clear) end
	if metric == "mean" then return stats.mean end
	if setMania then return nil end
	local judgments = stats.judgments
	if metric == "ma" and judgments.W2 > 0 then return judgments.W1 / judgments.W2 end
	if metric == "pa" and judgments.W3 > 0 then return judgments.W2 / judgments.W3 end
end

setSliceByCenterX = function(centerX)
	if setWidth <= 0 then return end
	local width = clampValue(setWidth * getCurrentSlicePercent() / 100, 1, setWidth)
	selectedSliceX1 = clampValue(centerX - width / 2, 0, setWidth - width)
	selectedSliceX2 = selectedSliceX1 + width
end

local function formatStat(value, format)
	return value == nil and "-" or string.format(format, value)
end

local function formatHover(x)
	local stats, label
	if getCurrentHoverModeId() == "slice" and selectedSliceX1 and selectedSliceX2 then
		local from, to = timeForX(selectedSliceX1), timeForX(selectedSliceX2)
		stats = rangeStats(countThrough(from, false) + 1, countThrough(to, true))
		label = string.format("%.2fs-%.2fs", from / setRate, to / setRate)
	else
		local time = timeForX(x)
		stats = rangeStats(1, countThrough(time, true))
		label = string.format("%.2fs", time / setRate)
	end
	if not stats then return label .. " | 0 taps" end
	local j = stats.judgments
	label = label .. string.format(" | %d %s\nwife: %s | mean: %s | sd: %s",
		stats.notes, stats.notes == 1 and "tap" or "taps",
		formatStat(stats.wife, "%.2f%%"), formatStat(stats.mean, "%+.2fms"), formatStat(stats.sd, "%.2fms"))
	if setMania then return label end
	return label .. string.format("\n%d | %d | %d | %d | %d | %d",
		j.W1, j.W2, j.W3, j.W4, j.W5, j.Miss)
end

local function fitY(y)
	return -1 * y / maxOffset * setHeight / 2
end

local function setOffsetVerts(vt, x, y, c)
	vt[#vt + 1] = {{x - dotWidth/2, y + dotWidth/2, 0}, c}
	vt[#vt + 1] = {{x + dotWidth/2, y + dotWidth/2, 0}, c}
	vt[#vt + 1] = {{x + dotWidth/2, y - dotWidth/2, 0}, c}
	vt[#vt + 1] = {{x - dotWidth/2, y - dotWidth/2, 0}, c}
end

local function HighlightUpdaterThing(self)
	if self:IsVisible() then
		self:GetChild("Background"):playcommand("Highlight")
	end
end

local baralpha = 0.4

-- HV color scheme
local frameBG = color("0.06,0.06,0.06,0.95")
local brightText = color("1,1,1,1")
local dimText = brightText
local accentColor = HVColor.Accent
local subText = brightText

local t = Def.ActorFrame{
	InitCommand = function(self)
		self:RunCommandsOnChildren(function(self)
			local params = {width = 0, height = 0, song = nil, steps = nil, nrv = {}, dvt = {}, ctt = {}, ntt = {}, columns = 4}
			self:playcommand("Update", params)
		end)
	end,
	OnCommand = function(self)
		local screen = SCREENMAN:GetTopScreen()
		if scoreTabPlot then
			self:SetUpdateFunction(HighlightUpdaterThing)
		elseif screen and (screen:GetName() == "ScreenEvaluationNormal" or screen:GetName() == "ScreenNetEvaluation") then
			local ok, allowHovering = pcall(function()
				return not screen:ScoreUsedInvalidModifier()
			end)
			if ok and allowHovering then
				self:SetUpdateFunction(HighlightUpdaterThing)
			end
		end
	end,
	BeginCommand = function(self)
		local screen = SCREENMAN:GetTopScreen()
		if not screen then return end
		screen:AddInputCallback(function(event)
			local parent = self:GetParent()
			if not self:GetVisible() or (parent and not parent:GetVisible())
				or not event or not event.DeviceInput then return false end
			local btn = event.DeviceInput.button

			if event.type == "InputEventType_FirstPress" and btn == "DeviceButton_left mouse button" then
				local metricLabel = self:GetChild("TrendMetricLabel")
				local metricBg = self:GetChild("TrendMetricBg")
				local colorLabel = self:GetChild("TrendColorLabel")
				local colorBg = self:GetChild("TrendColorBg")
				local hoverModeLabel = self:GetChild("HoverModeLabel")
				local hoverModeBg = self:GetChild("HoverModeBg")
				local sliceMinusLabel = self:GetChild("SliceMinusLabel")
				local sliceMinusBg = self:GetChild("SliceMinusBg")
				local slicePercentLabel = self:GetChild("SlicePercentLabel")
				local slicePercentBg = self:GetChild("SlicePercentBg")
				local slicePlusLabel = self:GetChild("SlicePlusLabel")
				local slicePlusBg = self:GetChild("SlicePlusBg")
				if (metricLabel and isOver(metricLabel)) or (metricBg and isOver(metricBg)) then
					cycleTrendMetric(1)
					return true
				end
				if (colorLabel and isOver(colorLabel)) or (colorBg and isOver(colorBg)) then
					cycleTrendColorMode(1)
					return true
				end
				if (hoverModeLabel and isOver(hoverModeLabel)) or (hoverModeBg and isOver(hoverModeBg)) then
					cycleHoverMode(1)
					return true
				end
				if ((sliceMinusLabel and isOver(sliceMinusLabel)) or (sliceMinusBg and isOver(sliceMinusBg))) and getCurrentHoverModeId() == "slice" then
					adjustSlicePercent(-1)
					return true
				end
				if (slicePercentLabel and isOver(slicePercentLabel)) or (slicePercentBg and isOver(slicePercentBg)) then
					return true
				end
				if ((slicePlusLabel and isOver(slicePlusLabel)) or (slicePlusBg and isOver(slicePlusBg))) and getCurrentHoverModeId() == "slice" then
					adjustSlicePercent(1)
					return true
				end
			end

			local bg = self:GetChild("Background")
			if not bg or not isOver(bg) then return false end

			if event.type == "InputEventType_FirstPress" and btn == "DeviceButton_mousewheel up" then
				setPlotScale(plotScale - 5)
				return true
			elseif event.type == "InputEventType_FirstPress" and btn == "DeviceButton_mousewheel down" then
				setPlotScale(plotScale + 5)
				return true
			elseif event.type == "InputEventType_FirstPress" and btn == "DeviceButton_left mouse button" then
				if getCurrentHoverModeId() == "slice" then
					setSliceByCenterX(getMouseLocalX(bg))
					MESSAGEMAN:Broadcast("JudgeDisplayChanged")
				else
					setPlotScaleToWorstHit()
				end
				return true
			elseif not scoreTabPlot and event.type == "InputEventType_FirstPress" and btn == "DeviceButton_right mouse button" then
				if selectedSliceX1 and selectedSliceX2 then
					selectedSliceX1 = nil
					selectedSliceX2 = nil
					MESSAGEMAN:Broadcast("JudgeDisplayChanged")
				else
					setPlotScale(100)
				end
				return true
			elseif event.type == "InputEventType_FirstPress" and btn == "DeviceButton_middle mouse button" then
				cycleTrendMetric(1)
				return true
			elseif event.type == "InputEventType_FirstPress" and btn == "DeviceButton_x1 mouse button" then
				cycleTrendColorMode(1)
				return true
			elseif event.type == "InputEventType_FirstPress" and btn == "DeviceButton_x2 mouse button" then
				cycleTrendColorMode(-1)
				return true
			elseif event.type == "InputEventType_FirstPress" and btn == "DeviceButton_left ctrl" then
				adjustSlicePercent(1)
				return true
			end
			return false
		end)
	end,
	OffsetPlotModificationMessageCommand = function(self, params)
		if setScoreKey and (params.Name == "PrevJudge" or params.Name == "NextJudge" or params.Name == "ResetJudge") then return end
		if params.Name == "PrevJudge" and judge > 1 then
			judge = judge - 1
			clampJudge()
			tso = tst[judge]
		elseif params.Name == "NextJudge" and judge < 9 then
			judge = judge + 1
			clampJudge()
			tso = tst[judge]
		elseif params.Name == "ToggleHands" and next(handStats) ~= nil and not setChordCohesion then
			local hands = oddColumns and oddHands or evenHands
			local direction = params.Direction == -1 and -1 or 1
			handIndex = (handIndex - 1 + direction) % #hands + 1
		elseif params.Name == "NextTrendMetric" then
			cycleTrendMetric(1)
			return
		elseif params.Name == "PrevTrendMetric" then
			cycleTrendMetric(-1)
			return
		elseif params.Name == "NextTrendColor" then
			cycleTrendColorMode(1)
			return
		elseif params.Name == "PrevTrendColor" then
			cycleTrendColorMode(-1)
			return
		end
		if params.Name == "ResetJudge" then
			judge = PREFSMAN:GetPreference("SortBySSRNormPercent") and 4 or GetTimingDifficulty()
			clampJudge()
			tso = tst[judge]
		end
		if params.Name ~= "ResetJudge" and params.Name ~= "PrevJudge"
			and params.Name ~= "NextJudge" and params.Name ~= "ToggleHands"
			and params.Name ~= "NextTrendMetric" and params.Name ~= "PrevTrendMetric"
			and params.Name ~= "NextTrendColor" and params.Name ~= "PrevTrendColor" then return end
		updateMaxOffset()
		MESSAGEMAN:Broadcast("JudgeDisplayChanged")
	end,
	LoadedCustomWindowMessageCommand = function(self)
		if scoreTabPlot then return end
		usingCustomWindows = true
		self:queuecommand("Update")
	end,
	UnloadedCustomWindowMessageCommand = function(self)
		if scoreTabPlot then return end
		usingCustomWindows = false
		self:queuecommand("Update")
	end
}
local function checkParams(params)
	if type(params) == "table" and params.width ~= nil then return params end
	return plotParams or {width = 0, height = 0}
end

-- Plot BG
t[#t+1] = Def.Quad{
	Name = "Background",
	InitCommand = function(self)
		self:halign(0):valign(0):diffuse(frameBG)
	end,
	UpdateCommand = function(self, params)
		params = checkParams(params)
		plotParams = params
		if params.scoreKey ~= setScoreKey then
			setScoreKey = params.scoreKey
			selectedSliceX1, selectedSliceX2 = nil, nil
		end
		if params.judge then
			judge = params.judge
			clampJudge()
			tso = tst[judge]
			updateMaxOffset()
		end
		setWidth, setHeight = params.width, params.height
		setRate = finite(params.rate) and params.rate > 0 and params.rate or 1
		setChordCohesion, setMania = params.chordCohesion, params.mania
		if params.customWindows ~= nil then usingCustomWindows = params.customWindows end
		local columns = params.columns or 4
		if oddColumns ~= (columns % 2 ~= 0) then handIndex = 1 end
		oddColumns, middleColumn = columns % 2 ~= 0, (columns - 1) / 2
		buildPlot(params)
		finalSecond = math.max(0.001, params.lastSecond or (params.song and params.song:GetLastSecond()) or 0,
			plotEvents[#plotEvents] and plotEvents[#plotEvents].time or 0)
		self:zoomto(params.width, params.height)
	end,
	HighlightCommand = function(self)
		local bar = self:GetParent():GetChild("PosBar")
		local txt = self:GetParent():GetChild("PosText")
		local bg = self:GetParent():GetChild("PosBG")
		local mx = INPUTFILTER:GetMouseX()
		local my = INPUTFILTER:GetMouseY()
		local x = self:GetTrueX()
		local y = self:GetTrueY()
		local w = self:GetZoomedWidth()
		local h = self:GetZoomedHeight()
		local ha = self.GetHAlign and self:GetHAlign() or 0
		local va = self.GetVAlign and self:GetVAlign() or 0
		
		local hovered = setWidth > 0 and w > 0 and h > 0
			and mx >= x - w * ha and mx <= x + w * (1 - ha)
			and my >= y - h * va and my <= y + h * (1 - va)
		local xpos = hovered and getMouseLocalX(self)
		if getCurrentHoverModeId() == "slice" then
			if hovered then setSliceByCenterX(xpos)
			else selectedSliceX1, selectedSliceX2 = nil, nil end
		end

		local activeX1 = selectedSliceX1
		local activeX2 = selectedSliceX2

		local sliceQuad = self:GetParent():GetChild("SliceSelection")
		local sliceLeftLine = self:GetParent():GetChild("SliceLeftLine")
		local sliceRightLine = self:GetParent():GetChild("SliceRightLine")
		if sliceQuad and activeX1 and activeX2 and (activeX2 - activeX1) >= 1 then
			sliceQuad:visible(true)
			sliceQuad:x(activeX1)
			sliceQuad:zoomto(activeX2 - activeX1, setHeight)
			if sliceLeftLine then
				sliceLeftLine:visible(true):x(activeX1)
				sliceLeftLine:zoomto(1, setHeight)
			end
			if sliceRightLine then
				sliceRightLine:visible(true):x(activeX2)
				sliceRightLine:zoomto(1, setHeight)
			end
		else
			if sliceQuad then sliceQuad:visible(false) end
			if sliceLeftLine then sliceLeftLine:visible(false) end
			if sliceRightLine then sliceRightLine:visible(false) end
		end

		if hovered then
			bar:visible(true):x(xpos)
			txt:visible(true):settext(formatHover(xpos))
			local width, height = txt:GetZoomedWidth() + 4, txt:GetZoomedHeight() + 4
			local right = math.max(width, xpos)
			txt:xy(right - 2, setHeight - 2)
			bg:visible(true):xy(right, setHeight):zoomto(width, height)
		else
			bar:visible(false)
			txt:visible(false)
			bg:visible(false)
		end
	end
}

-- Plot center horizontal line removed per user request

-- Slice highlight
t[#t+1] = Def.Quad {
	Name = "SliceSelection",
	InitCommand = function(self)
		self:halign(0):valign(0):visible(false):diffuse(HVColor.Accent):diffusealpha(0.16)
	end,
	UpdateCommand = function(self, params)
		params = checkParams(params)
		if selectedSliceX1 and selectedSliceX2 then
			local x1 = math.min(selectedSliceX1, selectedSliceX2)
			local x2 = math.max(selectedSliceX1, selectedSliceX2)
			if getCurrentHoverModeId() == "slice" and x2 - x1 >= 1 then
				self:visible(true):x(x1):zoomto(x2 - x1, params.height)
			else
				self:visible(false)
			end
		else
			self:visible(false)
		end
	end,
	JudgeDisplayChangedMessageCommand = function(self) self:queuecommand("Update") end
}

-- Button background helper (defined here so it's available for all control actors below)
local function buttonBg(name, xFunc, yOffset, width, hAlign)
	return Def.Quad {
		Name = name .. "Bg",
		InitCommand = function(self)
			self:halign(hAlign or 0):valign(0):diffuse(color("#2A2A2A")):diffusealpha(0.9)
		end,
		UpdateCommand = function(self, params)
			params = checkParams(params)
			self:xy(xFunc(params), params.height + yOffset)
			self:zoomto(width or 70, 18)
		end,
		JudgeDisplayChangedMessageCommand = function(self) self:queuecommand("Update") end
	}
end

t[#t+1] = buttonBg("HoverMode", function(p) return 5 end, 28, 65, 0)

t[#t+1] = LoadFont("Common Normal") .. {
	Name = "HoverModeLabel",
	InitCommand = function(self)
		self:halign(0):valign(0.5):zoom(0.35):diffuse(brightText)
	end,
	UpdateCommand = function(self, params)
		params = checkParams(params)
		self:xy(8, params.height + 35)
		self:settextf("Hover: %s", hoverModeOptions[hoverModeIndex].label)
	end,
	JudgeDisplayChangedMessageCommand = function(self) self:queuecommand("Update") end
}

t[#t+1] = buttonBg("SliceMinus", function(p) return p.width - 105 end, 28, 20, 0)

t[#t+1] = LoadFont("Common Normal") .. {
	Name = "SliceMinusLabel",
	InitCommand = function(self)
		self:halign(0.5):valign(0.5):zoom(0.40):diffuse(brightText):settext("-")
	end,
	UpdateCommand = function(self, params)
		params = checkParams(params)
		self:xy(params.width - 95, params.height + 37)
		if getCurrentHoverModeId() == "slice" then
			self:diffusealpha(1)
		else
			self:diffusealpha(0.45)
		end
	end,
	JudgeDisplayChangedMessageCommand = function(self) self:queuecommand("Update") end
}

t[#t+1] = buttonBg("SlicePercent", function(p) return p.width - 63 end, 28, 40, 0)

t[#t+1] = LoadFont("Common Normal") .. {
	Name = "SlicePercentLabel",
	InitCommand = function(self)
		self:halign(0.5):valign(0.5):zoom(0.35):diffuse(brightText)
	end,
	UpdateCommand = function(self, params)
		params = checkParams(params)
		self:xy(params.width - 43, params.height + 37)
		if getCurrentHoverModeId() == "slice" then
			self:diffusealpha(1)
			self:settextf("%d%%", getCurrentSlicePercent())
		else
			self:diffusealpha(0.45)
			self:settext("--")
		end
	end,
	JudgeDisplayChangedMessageCommand = function(self) self:queuecommand("Update") end
}

t[#t+1] = buttonBg("SlicePlus", function(p) return p.width - 20 end, 28, 20, 0)

t[#t+1] = LoadFont("Common Normal") .. {
	Name = "SlicePlusLabel",
	InitCommand = function(self)
		self:halign(0.5):valign(0.5):zoom(0.40):diffuse(brightText):settext("+")
	end,
	UpdateCommand = function(self, params)
		params = checkParams(params)
		self:xy(params.width - 10, params.height + 37)
		if getCurrentHoverModeId() == "slice" then
			self:diffusealpha(1)
		else
			self:diffusealpha(0.45)
		end
	end,
	JudgeDisplayChangedMessageCommand = function(self) self:queuecommand("Update") end
}

t[#t+1] = Def.Quad {
	Name = "SliceLeftLine",
	InitCommand = function(self)
		self:halign(0):valign(0):visible(false):diffuse(HVColor.Accent):diffusealpha(0.7)
	end,
	UpdateCommand = function(self, params)
		params = checkParams(params)
		if selectedSliceX1 and selectedSliceX2 then
			local x1 = math.min(selectedSliceX1, selectedSliceX2)
			local x2 = math.max(selectedSliceX1, selectedSliceX2)
			if getCurrentHoverModeId() == "slice" and x2 - x1 >= 1 then
				self:visible(true):x(x1):zoomto(1, params.height)
			else
				self:visible(false)
			end
		else
			self:visible(false)
		end
	end,
	JudgeDisplayChangedMessageCommand = function(self) self:queuecommand("Update") end
}

t[#t+1] = Def.Quad {
	Name = "SliceRightLine",
	InitCommand = function(self)
		self:halign(0):valign(0):visible(false):diffuse(HVColor.Accent):diffusealpha(0.7)
	end,
	UpdateCommand = function(self, params)
		params = checkParams(params)
		if selectedSliceX1 and selectedSliceX2 then
			local x1 = math.min(selectedSliceX1, selectedSliceX2)
			local x2 = math.max(selectedSliceX1, selectedSliceX2)
			if getCurrentHoverModeId() == "slice" and x2 - x1 >= 1 then
				self:visible(true):x(x2):zoomto(1, params.height)
			else
				self:visible(false)
			end
		else
			self:visible(false)
		end
	end,
	JudgeDisplayChangedMessageCommand = function(self) self:queuecommand("Update") end
}

-- Judgment threshold lines (symmetric)
local thresholdKeys = {"W1", "W2", "W3", "W4", "W5"}
local function getThresholdLine(index)
	local fit = getJudgeWindows()[thresholdKeys[index]]
	if usingCustomWindows and customOffsetToJudgeColor and getCurrentCustomWindowConfigJudgmentWindowTable then
		local customWindows = getCurrentCustomWindowConfigJudgmentWindowTable()
		if customWindows then return fit, customOffsetToJudgeColor(fit + 1, customWindows) end
	end
	local palette = HV.Color.GetJudgmentPalette()
	return fit, palette[thresholdKeys[index + 1]]
end

for i = 1, #thresholdKeys - 1 do
	-- Upper line
	t[#t + 1] = Def.Quad {
		InitCommand = function(self) self:halign(0):valign(0) end,
		UpdateCommand = function(self, params)
			params = checkParams(params)
			self:zoomto(params.width, 1)
			
			local fit, c = getThresholdLine(i)
			local visible = math.abs(fit) <= maxOffset
			self:visible(visible)
			if visible then
				self:diffuse(c):diffusealpha(baralpha)
				self:y(fitY(fit) + params.height / 2)
			end
		end,
		JudgeDisplayChangedMessageCommand = function(self) self:queuecommand("Update") end
	}
	-- Lower line (mirror)
	t[#t + 1] = Def.Quad {
		InitCommand = function(self) self:halign(0):valign(0) end,
		UpdateCommand = function(self, params)
			params = checkParams(params)
			self:zoomto(params.width, 1)
			
			local fit, c = getThresholdLine(i)
			local visible = math.abs(fit) <= maxOffset
			self:visible(visible)
			if visible then
				self:diffuse(c):diffusealpha(baralpha)
				self:y(fitY(-fit) + params.height / 2)
			end
		end,
		JudgeDisplayChangedMessageCommand = function(self) self:queuecommand("Update") end
	}
end

-- Position bar for hover
t[#t+1] = Def.Quad {
	Name = "PosBar",
	InitCommand = function(self)
		self:visible(false):zoomto(2, setHeight):diffuse(color("0.5,0.5,0.5,1")):valign(0)
	end,
	UpdateCommand = function(self, params)
		params = checkParams(params)
		self:zoomto(2, params.height)
	end
}

-- Late ms text
t[#t+1] = LoadFont("Common Normal")..{
	InitCommand = function(self) self:zoom(0.42):halign(0):valign(1):diffuse(dimText) end,
	UpdateCommand = function(self)
		self:xy(5, -5):settextf("Late (+%d ms)", maxOffset)
	end,
	JudgeDisplayChangedMessageCommand = function(self) self:queuecommand("Update") end
}

-- Early ms text
t[#t+1] = LoadFont("Common Normal")..{
	InitCommand = function(self) self:zoom(0.42):halign(0):valign(1):diffuse(dimText) end,
	UpdateCommand = function(self, params)
		params = checkParams(params)
		self:xy(5, params.height - 5):settextf("Early (-%d ms)", maxOffset)
	end,
	JudgeDisplayChangedMessageCommand = function(self) self:queuecommand("Update") end
}

-- Trend line control labels
t[#t+1] = buttonBg("TrendMetric", function(p) return 5 end, 12, 80, 0)

t[#t+1] = LoadFont("Common Normal") .. {
	Name = "TrendMetricLabel",
	InitCommand = function(self)
		self:halign(0):valign(0.5):zoom(0.35):diffuse(brightText)
	end,
	UpdateCommand = function(self, params)
		params = checkParams(params)
		self:xy(8, params.height + 20)
		self:settextf("Trend: %s", trendMetricModes[trendMetricIndex].label)
	end,
	JudgeDisplayChangedMessageCommand = function(self) self:queuecommand("Update") end
}

t[#t+1] = LoadFont("Common Normal") .. {
	Name = "TrendRange",
	InitCommand = function(self) self:zoom(0.3):diffuse(dimText) end,
	UpdateCommand = function(self, params)
		params = checkParams(params)
		self:xy(params.width / 2, params.height + 20)
	end,
}

t[#t+1] = buttonBg("TrendColor", function(p) return p.width - 5 end, 12, 80, 1)

t[#t+1] = LoadFont("Common Normal") .. {
	Name = "TrendColorLabel",
	InitCommand = function(self)
		self:halign(1):valign(0.5):zoom(0.35):diffuse(brightText)
	end,
	UpdateCommand = function(self, params)
		params = checkParams(params)
		self:xy(params.width - 8, params.height + 20)
		self:settextf("Color: %s", trendColorModes[trendColorModeIndex].label)
	end,
	JudgeDisplayChangedMessageCommand = function(self) self:queuecommand("Update") end
}

-- Hand highlight info text
t[#t+1] = LoadFont("Common Normal") .. {
	InitCommand = function(self) self:zoom(0.35):diffuse(brightText):settext("") end,
	UpdateCommand = function(self, params)
		params = checkParams(params)
		self:xy(params.width / 2, -48)
		if not next(handStats) or setChordCohesion then
			self:settext("")
		elseif currentHand() ~= "All" then
			local side = currentHand()
			self:settextf("%s: %s", handLabels[side], formatStat(getHandWife(side), "%.4f%%"))
			self:diffuse(accentColor)
		else
			self:settext(scoreTabPlot and "" or "UP / DOWN TO TOGGLE HIGHLIGHTS")
			self:diffuse(subText)
		end
	end,
	JudgeDisplayChangedMessageCommand = function(self) self:queuecommand("Update") end
}

-- Early/Late distribution indicator
t[#t+1] = LoadFont("Common Normal") .. {
	InitCommand = function(self) self:zoom(0.35):halign(1):valign(1):diffuse(dimText) end,
	UpdateCommand = function(self, params)
		params = checkParams(params)
		self:xy(params.width - 5, -5)
		local early = 0
		local late = 0
		for _, event in ipairs(plotEvents) do
			local off = event.offset
			if off and off < 0 then early = early + 1
			elseif off and off > 0 then late = late + 1 end
		end
		if early + late > 0 then
			self:settextf("Early: %d (%.1f%%) | Late: %d (%.1f%%)", 
				early, early / (early + late) * 100,
				late, late / (early + late) * 100)
		else
			self:settext("")
		end
	end,
	JudgeDisplayChangedMessageCommand = function(self) self:queuecommand("Update") end
}

-- CB Display (Stacked above Delta Hand on Right)
t[#t+1] = LoadFont("Common Normal") .. {
	InitCommand = function(self) self:zoom(0.4):halign(1):valign(1):diffuse(brightText) end,
	UpdateCommand = function(self, params)
		params = checkParams(params)
		self:xy(params.width - 5, -5 - 20)
		if #plotEvents == 0 then self:settext(""); return end
		local text = string.format("CB: %d", comboBreaks.total)
		if not setChordCohesion and next(handStats) ~= nil then
			text = text .. string.format(" (L:%d  R:%d", comboBreaks.L, comboBreaks.R)
			if oddColumns then text = text .. string.format("  M:%d", comboBreaks.M) end
			text = text .. ")"
		end
		self:settext(text)
	end,
	JudgeDisplayChangedMessageCommand = function(self) self:queuecommand("Update") end
}

-- Delta Hand Display (recorded tap Wife percentage points)
t[#t+1] = LoadFont("Common Normal") .. {
	InitCommand = function(self) self:zoom(0.4):halign(1):valign(1):diffuse(brightText) end,
	UpdateCommand = function(self, params)
		params = checkParams(params)
		self:xy(params.width - 5, -15)
		local leftWife, rightWife, middleWife = getHandWife("L"), getHandWife("R"), getHandWife("M")
		if not leftWife or not rightWife or (oddColumns and not middleWife) then
			self:settext("")
			return
		end
		if oddColumns then
			local scores = {L = leftWife, M = middleWife, R = rightWife}
			local sides = {"L", "M", "R"}
			table.sort(sides, function(a, b)
				if scores[a] == scores[b] then return a < b end
				return scores[a] > scores[b]
			end)
			self:settextf("Δ Hand: %s %.4f", table.concat(sides, ">"), scores[sides[1]] - scores[sides[3]])
		else
			self:settextf("Δ Hand: %s %.4f", leftWife > rightWife and ">" or "<", math.abs(leftWife - rightWife))
		end
	end,
	JudgeDisplayChangedMessageCommand = function(self) self:queuecommand("Update") end
}

-- THE DOTS (ActorMultiVertex)
t[#t+1] = Def.ActorMultiVertex{
	UpdateCommand = function(self, params)
		params = checkParams(params)
		local verts = {}

		local palette = HV.Color.GetJudgmentPalette()
		local windows = HV.Judgment.GetWindows(tso, HV.EmulateRidiculousEnabled())
		local customWindows = usingCustomWindows and getCurrentCustomWindowConfigJudgmentWindowTable
			and getCurrentCustomWindowConfigJudgmentWindowTable()
		local highlightedHand = currentHand()
		for _, event in ipairs(plotEvents) do
			local sourceColor
			if not event.miss and customWindows and customOffsetToJudgeColor then
				sourceColor = customOffsetToJudgeColor(event.offset, customWindows)
			else
				local bucket = event.miss and "Miss" or HV.Judgment.ClassifyOffset(event.offset, windows)
				sourceColor = palette[bucket]
			end
			sourceColor = sourceColor or accentColor
			local x = xForTime(event.time)
			local alpha = 1
			local track = event.track
			if highlightedHand ~= "All" and track and not setChordCohesion then
				local side = track < middleColumn and "L" or (track == middleColumn and "M" or "R")
				if highlightedHand ~= side then alpha = 0.1 end
			end
			local color = {sourceColor[1], sourceColor[2], sourceColor[3], alpha}
			if event.miss then
				color[4] = math.min(alpha, 0.3)
				verts[#verts + 1] = {{x - dotWidth/4, params.height, 0}, color}
				verts[#verts + 1] = {{x + dotWidth/4, params.height, 0}, color}
				verts[#verts + 1] = {{x + dotWidth/4, 0, 0}, color}
				verts[#verts + 1] = {{x - dotWidth/4, 0, 0}, color}
			else
				local y = fitY(event.offset) + params.height / 2
				setOffsetVerts(verts, x, y, color)
			end
		end

		self:SetVertices(verts)
		self:SetDrawState{Mode = "DrawMode_Quads", First = 1, Num = #verts}
	end,
	JudgeDisplayChangedMessageCommand = function(self) self:queuecommand("Update") end
}

-- Advance the cumulative trend once per simultaneous group.
t[#t+1] = Def.ActorMultiVertex{
	Name = "TrendLine",
	UpdateCommand = function(self, params)
		params = checkParams(params)
		local verts, points = {}, {}
		local metric = getCurrentTrendMetricId()
		local colorMode = getCurrentTrendColorModeId()
		local lo, hi = math.huge, -math.huge
		if metric ~= "off" then
			for i, event in ipairs(plotEvents) do
				if not plotEvents[i + 1] or plotEvents[i + 1].time ~= event.time then
					local stats = rangeStats(1, i)
					local grade = stats.wife and getWifeGradeTier(stats.wife)
					local clear = not setMania and getClearTypeFromCounts(stats.judgments)
					local value = metricValue(metric, stats, grade, clear)
					if finite(value) then
						points[#points + 1] = {x = xForTime(event.time), value = value, grade = grade, clear = clear}
						lo, hi = math.min(lo, value), math.max(hi, value)
					end
				end
			end
		end

		local function segment(x1, y1, x2, y2, color)
			local dx, dy = x2 - x1, y2 - y1
			local length = math.sqrt(dx * dx + dy * dy)
			if length <= 0.0001 then return end
			local nx, ny = -dy / length * 0.8, dx / length * 0.8
			verts[#verts + 1] = {{x1 - nx, y1 - ny, 0}, color}
			verts[#verts + 1] = {{x1 + nx, y1 + ny, 0}, color}
			verts[#verts + 1] = {{x2 + nx, y2 + ny, 0}, color}
			verts[#verts + 1] = {{x2 - nx, y2 - ny, 0}, color}
		end
		local function y(value)
			if metric == "mean" then
				return fitY(clampValue(value, -maxOffset, maxOffset)) + params.height / 2
			end
			if hi == lo then return params.height / 2 end
			return 1 + (hi - value) / (hi - lo) * math.max(0, params.height - 2)
		end
		for i = 2, #points do
			local from, to = points[i - 1], points[i]
			local tint = accentColor
			if colorMode == "grade" and to.grade then tint = HVColor.GetGradeColor(to.grade) end
			if colorMode == "clear" and to.clear then tint = getClearTypeColor(to.clear) or accentColor end
			local color = {tint[1], tint[2], tint[3], 0.92}
			segment(from.x, y(from.value), to.x, y(from.value), color)
			segment(to.x, y(from.value), to.x, y(to.value), color)
		end

		self:SetVertices(verts)
		self:SetDrawState{Mode = "DrawMode_Quads", First = 1, Num = #verts}
		local caption = self:GetParent():GetChild("TrendRange")
		if not caption then return end
		if metric == "off" then
			caption:settext("")
		elseif #points < 2 then
			caption:settext("Scale: -")
		elseif metric == "wife" then
			caption:settextf("Scale: %.2f%% - %.2f%%", lo, hi)
		elseif metric == "mean" then
			caption:settextf("Scale: %+.0f - %+.0f ms", -maxOffset, maxOffset)
		elseif metric == "ma" or metric == "pa" then
			caption:settextf("Scale: %.2f:1 - %.2f:1", lo, hi)
		else
			caption:settext("Scale: relative rank")
		end
	end,
	JudgeDisplayChangedMessageCommand = function(self) self:queuecommand("Update") end
}

-- Tooltip BG
t[#t+1] = Def.Quad {
	Name = "PosBG",
	InitCommand = function(self)
		self:valign(1):halign(1):zoomto(30, 30):diffuse(color(".06,.06,.06,.9")):visible(false)
	end
}

-- Tooltip text
t[#t+1] = LoadFont("Common Normal") .. {
	Name = "PosText",
	InitCommand = function(self)
		self:valign(1):halign(1):zoom(0.3):diffuse(color("0.8,0.8,0.8,1"))
	end
}

return t
