local ThemePrefs = HV.LegacyPrefs
local getReplayPlotVectors = LoadActor("../ReplayPlotVectors.lua")

--- Holographic Void: ScreenEvaluation Decorations
-- Full-featured evaluation screen ported from spawncamping-wallhack.
-- Features: Life/Combo graphs, Avatar+Player info, Grade+Score with rescoring (needs testing to ensure nothing breaks),
--   ClearType comparison, Tap/Hold/Mine judgments, Timing stats (mean/sd),
--   CB L/R breakdown, Paginated Local/Online Scoreboard, Full Offset Plot.

local song = GAMESTATE:GetCurrentSong()
local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats()
local steps = GAMESTATE:GetCurrentSteps()
local pn = GAMESTATE:GetEnabledPlayers()[1]
local profile = PROFILEMAN:GetProfile(pn)

-- Autoplay results are not player scores.  Keep this local to the evaluation
-- screen so autoplay can still be used normally during gameplay.
local function isAutoplayEvaluation()
	-- Replay evaluations (including online replays) are playback of an
	-- existing score.  Their replay/controller metadata may contain
	-- autoplay-like values, but they must never be treated as autoplay runs.
	if HV.IsReplayPlayback and HV.IsReplayPlayback() then return false end
	if HV.OnlineReplayActive == true or HV.OnlineEvaluationActive == true then return false end

	-- A score opened from Song Select's Scores tab is a historical score
	-- view, not the result of the current gameplay session.  This gate keeps
	-- the persistent autoplay setting from affecting those evaluations.
	if HV.GameplaySessionValid ~= true then return false end

	if type(getAutoplay) == "function" then
		local ok, value = pcall(getAutoplay)
		if ok and tonumber(value) and tonumber(value) ~= 0 then return true end
	end
	if GAMESTATE.IsAutoplay then
		local ok, value = pcall(GAMESTATE.IsAutoplay, GAMESTATE)
		if ok and value == true then return true end
	end
	for _, player in ipairs(GAMESTATE:GetEnabledPlayers() or {}) do
		local state = GAMESTATE:GetPlayerState(player)
		if state and state.GetPlayerController then
			local ok, controller = pcall(state.GetPlayerController, state)
			if ok and tostring(controller):lower():find("autoplay", 1, true) then return true end
		end
	end
	local stageScore = pss and pss.GetHighScore and pss:GetHighScore()
	if stageScore and stageScore.GetModifiers then
		local ok, mods = pcall(stageScore.GetModifiers, stageScore)
		if ok and tostring(mods):lower():find("autoplay", 1, true) then return true end
	end
	return false
end

local scoringVoided = isAutoplayEvaluation()
HV.EvaluationScoringVoided = scoringVoided

if scoringVoided then
	return Def.ActorFrame {
		Def.Quad {
			InitCommand = function(self)
				self:xy(SCREEN_CENTER_X, SCREEN_CENTER_Y)
					:zoomto(SCREEN_WIDTH, SCREEN_HEIGHT)
					:diffuse(color("0.01,0.01,0.02,0.94"))
			end
		},
		LoadFont("Common Large") .. {
			InitCommand = function(self)
				self:xy(SCREEN_CENTER_X, SCREEN_CENTER_Y):zoom(1.1)
					:diffuse(HVColor.Accent):settext("Why are you lying to yourself?")
			end
		}
	}
end

local isReplay = HV.IsReplayPlayback() or HV.OnlineReplayActive == true
local openingScore = HV.Score.GetEvaluationOpeningScore(steps, pss, isReplay)
local curScore = openingScore
local stageOffsets = {
	rows = pss:GetNoteRowVector(),
	tracks = pss:GetTrackVector(),
	types = pss:GetTapNoteTypeVector(),
	offsets = pss:GetOffsetVector(),
	taps = pss:GetTotalTaps(),
}
local stageRadar
local noteTypeRadars = {"RadarCategory_Holds", "RadarCategory_Rolls", "RadarCategory_Lifts", "RadarCategory_Mines"}
if (isReplay and openingScore) or (not isReplay and HV.GameplaySessionValid == true) then
	stageRadar = {actual = {}, possible = {}}
	local actual, possible = pss:GetRadarActual(), pss:GetRadarPossible()
	for _, radar in ipairs(noteTypeRadars) do
		stageRadar.actual[radar] = actual:GetValue(radar)
		stageRadar.possible[radar] = possible:GetValue(radar)
	end
	for _, radar in ipairs({"RadarCategory_Notes", "RadarCategory_TapsAndHolds"}) do
		stageRadar.possible[radar] = possible:GetValue(radar)
	end
end

local function openingStageRadar()
	if not stageRadar then return end
	if curScore == openingScore or (curScore and openingScore and curScore:GetScoreKey() == openingScore:GetScoreKey()) then
		return stageRadar
	end
end

local function evaluationWifeScore()
	if scoringVoided then return 0 end
	if curScore and curScore.GetWifeScore then return curScore:GetWifeScore() or 0 end
	return pss:GetWifeScore() or 0
end
local function evaluationGrade()
	if scoringVoided then return "Grade_None" end
	if curScore and curScore.GetWifeGrade then return curScore:GetWifeGrade() end
	return pss:GetWifeGrade()
end

local function evaluationTapCount(name)
	if scoringVoided then return 0 end
	if curScore and curScore.GetTapNoteScore then return curScore:GetTapNoteScore(name) or 0 end
	return pss:GetTapNoteScores(name)
end

local function evaluationHoldCount(name)
	if scoringVoided then return 0 end
	if curScore and curScore.GetHoldNoteScore then return curScore:GetHoldNoteScore(name) or 0 end
	return pss:GetHoldNoteScores(name)
end

local judge = 4
local playedJudge = 4
local normalized = PREFSMAN:GetPreference("SortBySSRNormPercent")
local inMulti = Var("LoadingScreen") == "ScreenNetEvaluation"
local judges = {"TapNoteScore_W1", "TapNoteScore_W2", "TapNoteScore_W3", "TapNoteScore_W4", "TapNoteScore_W5", "TapNoteScore_Miss"}

-- Rescoring/offset plot state
local nrv, dvt, ctt, ntt, totalTaps
local plotMisses
local offsetStats
local rescore = {}
local usingCustomWindows = false
local lastSnapshot = nil
local showRATally = false
local maniaRescore = nil
local refreshEvaluationDisplays
local clearRatioCache

local openingIsOnline = HV.OnlineEvaluationActive == true or HV.OnlineReplayActive == true
local selectedOnline = openingIsOnline
local function isOnlineEvaluation()
	return selectedOnline
end

-- This is here to make sure that osu!mania state doesn't leak into the normal score display
HV.ResetManiaMode()

local function isManiaModeEnabled()
	return HV.ManiaState and HV.ManiaState.enabled == true
end

local function editManiaOD()
	if not isManiaModeEnabled() then return end
	easyInputStringOKCancel(
		"osu!mania OD (0.0 - 11.0)", 4, false,
		function(value)
			local od = tonumber(value)
			if od then
				HV.SetManiaOD(math.max(0, math.min(11, od)))
				if refreshEvaluationDisplays then refreshEvaluationDisplays() end
			end
		end,
		nil,
		string.format("%.1f", HV.ManiaState and HV.ManiaState.od or 8)
	)
end

local function roundTo(value, places)
	if value == nil then return 0 end
	if notShit and type(notShit.round) == "function" then
		return notShit.round(value, places)
	end
	local scale = 10 ^ (places or 0)
	return math.floor(value * scale + 0.5) / scale
end

local function getJudgeForScore(score)
	if isOnlineEvaluation() then return 4 end
	return HV.Score.GetPlayedJudge(score) or (score and 4 or GetTimingDifficulty())
end

local function nativeWifeJudge()
	return normalized and curScore and 4 or playedJudge
end

local function defaultJudge()
	return math.max(4, math.min(9, nativeWifeJudge()))
end

local formatWifePercent = HV.Score.FormatEvaluationWifePercent

local evalModShorthands = {
	-- Turn
	["Mirror"] = "MIR", ["Back"] = "BAK", ["Left"] = "LFT", ["Right"] = "RGT",
	["Shuffle"] = "SHU", ["SoftShuffle"] = "SSH", ["SuperShuffle"] = "XSH",
	-- Appearance
	["Hidden"] = "HID", ["Sudden"] = "SUD", ["Stealth"] = "STL", ["Blink"] = "BLK", ["RandomVanish"] = "RVN",
	-- Hide
	["Dark"] = "DRK", ["Blind"] = "BLN", ["Cover"] = "COV",
	-- Remove
	["NoMines"] = "NOM", ["NoHolds"] = "NOH", ["NoRolls"] = "NOR", ["NoLifts"] = "NOL", ["NoFakes"] = "NOF",
	-- Other
	["Reverse"] = "REV", ["Mines"] = "MNS",
}

local function formatEvalSpeedMode(mode, speed)
	mode = mode or "C"
	speed = speed or 400
	if mode == "x" then
		return string.format("%.2fx", speed / 100)
	end
	return mode .. tostring(speed)
end

local function formatEvalRateValue(rate)
	local formatted = string.format("%.2f", tonumber(rate) or 1):gsub("%.?0+$", "") .. "x"
	if formatted == "1x" then formatted = "1.0x" end
	if formatted == "2x" then formatted = "2.0x" end
	return formatted
end

local function hasEvaluationAssistEnabled(po, modStr)
	local normalizedModStr = (modStr or ""):lower():gsub("[%s_]+", "")
	if po then
		if po.AssistClap and po:AssistClap() then return true end
		if po.AssistTick and po:AssistTick() then return true end
	end
	return string.find(normalizedModStr, "assistclap")
		or string.find(normalizedModStr, "assisttick")
		or string.find(normalizedModStr, "autoplay")
end

local function setDPTextActors(wholeActor, decimalActor, dp, precision)
	local roundedDp = roundTo(dp, precision)
	local format = "%0." .. precision .. "f"
	local formatted = string.format(format, roundedDp)
	local whole, decimal = formatted:match("^(%-?%d+)%.(%d+)$")
	if wholeActor and whole then
		wholeActor:settext(whole)
	end
	if decimalActor and decimal then
		decimalActor:settext("." .. decimal)
		decimalActor:x(wholeActor:GetWidth() * wholeActor:GetZoom() + 1)
	end
end

local function wifePercentAtJudge(targetJudge)
	if targetJudge == nativeWifeJudge() then return evaluationWifeScore() * 100 end
	if rescore.data then return getRescoredWife3Judge(3, targetJudge, rescore.data) end
end

local function refreshRescoredPercentage()
	rescore.counts, rescore.percent, rescore.earned, rescore.possible = nil, nil, nil, nil
	maniaRescore = nil
	if scoringVoided then return end
	if HV.ManiaState and HV.ManiaState.enabled then
		maniaRescore = HV.GetOsuManiaRescore(curScore, HV.ManiaState.od, true)
		rescore.percent = maniaRescore.accuracy * 100
		return
	end

	if judge ~= playedJudge and rescore.data then
		rescore.counts = HV.Judgment.RescoreHits(rescore.data.dvt, rescore.data.misses, judge)
	end
	if judge ~= nativeWifeJudge() then
		rescore.percent, rescore.earned, rescore.possible = wifePercentAtJudge(judge)
	end
end

local function displayedWifePercent()
	if rescore.percent ~= nil then return rescore.percent end
	if judge == nativeWifeJudge() then return evaluationWifeScore() * 100 end
end

function calculateCustomWindowScore(configName, rst)
	if not customWindowsConfig or not rst then return 0 end
	local config = customWindowsConfig:get_data().customWindowConfigs[configName]
	if not config then return 0 end
	
	local pts = 0
	local dvt = rst.dvt
	
	local curveFunc = config.customWindowCurveFunction
	local worths = config.customWindowWorths
	local windows = config.customWindowWindows
	
	local function getCurveWorth(offset)
		if curveFunc then return curveFunc(offset / 1000) end
		if worths and windows then
			local ms = math.abs(offset)
			if ms <= (windows.W1 or 22.5) then return worths.W1 or 2
			elseif ms <= (windows.W2 or 45) then return worths.W2 or 2
			elseif ms <= (windows.W3 or 90) then return worths.W3 or 1
			elseif ms <= (windows.W4 or 135) then return worths.W4 or 0
			elseif ms <= (windows.W5 or 180) then return worths.W5 or -4
			else return worths.Miss or -8 end
		end
		return 0
	end
	
	-- Calculate tap/hit points
	if dvt then
		for i=1, #dvt do
			pts = pts + getCurveWorth(dvt[i])
		end
	end
	
	-- Penalty for unplayed notes
	local missWorth = 0
	if worths and worths.Miss then missWorth = worths.Miss
	elseif curveFunc then missWorth = curveFunc(1.000) end
	if not missWorth or missWorth == 0 then missWorth = -8 end
	
	local maxNotes = math.max(0, tonumber(rst.totalNotes) or 0)
	maxNotes = math.max(maxNotes, tonumber(rst.notesPassed) or 0)
	local unplayed = math.max(0, maxNotes - (tonumber(rst.notesPassed) or 0))
	pts = pts + (unplayed * missWorth)
	
	-- Hold/Roll scoring
	local holdWorths = config.customWindowHoldWorths or {}
	local heldWorth = holdWorths.Held or 0
	local letGoWorth = holdWorths.LetGo or -4.5
	local missedHoldWorth = holdWorths.Missed or -4.5
	
	local totalHolds = rst.totalHolds or 0
	local totalRolls = rst.totalRolls or 0
	local totalLongNotes = totalHolds + totalRolls
	local longNotesMissed = (rst.holdsMissed or 0) + (rst.rollsMissed or 0)
	
	-- Penalize missed long notes
	pts = pts + (longNotesMissed * missedHoldWorth)
	-- Reward successfully held long notes
	pts = pts + (totalLongNotes - longNotesMissed) * heldWorth
	
	-- Mine penalties
	local mineHitWorth = config.customWindowMineHitWorth or -2
	pts = pts + (rst.minesHit or 0) * mineHitWorth
	
	-- Max points calculation
	local tapTypeWorths = config.customWindowTapNoteTypeWorths or {}
	local tapWorth = tapTypeWorths.Tap or 2
	local holdHeadWorth = tapTypeWorths.HoldHead or 2
	local liftWorth = tapTypeWorths.Lift or tapWorth
	local mineWorth = tapTypeWorths.Mine or 0
	
	-- RadarCategory_Notes = Taps + HoldHeads + RollHeads + Lifts
	-- We approximate RollHeads as using HoldHead worth
	local others = maxNotes - totalLongNotes
	if others < 0 then others = 0 end
	
	local maxPts = (others * tapWorth) + (totalLongNotes * holdHeadWorth)
	-- Plus completion points for every long note
	maxPts = maxPts + (totalLongNotes * heldWorth)
	-- Plus mine points if hit (usually 0)
	local totalMines = rst.totalMines or 0
	maxPts = maxPts + (totalMines * mineWorth)
	
	if maxPts <= 0 then return 0 end
	return math.max(0, math.min(100, (pts / maxPts) * 100)), pts, maxPts
end


local function updateVectors()
	plotMisses = nil
	if scoringVoided then
		nrv, dvt, ctt, ntt, totalTaps = {}, {}, {}, {}, 0
		offsetStats = {}
		return
	end
	local vectors = getReplayPlotVectors(curScore)

	if vectors then
		nrv, dvt, ctt, ntt, plotMisses = vectors.nrv, vectors.dvt, vectors.ctt, vectors.ntt, vectors.misses
		totalTaps = 0
		if ntt then
			for _, typ in ipairs(ntt) do
				if typ == "TapNoteType_Tap" or typ == "TapNoteType_HoldHead" or typ == "TapNoteType_Lift" then
					totalTaps = totalTaps + 1
				end
			end
		end
	elseif curScore == openingScore then
		nrv, ctt, ntt, dvt, totalTaps = stageOffsets.rows, stageOffsets.tracks, stageOffsets.types, stageOffsets.offsets, stageOffsets.taps
	else
		nrv, ctt, ntt, dvt, totalTaps = {}, {}, {}, {}, 0
	end
	if HV.ManiaState and HV.ManiaState.enabled and curScore and curScore.GetReplay then
		local orderedOffsets, _, orderedTaps = HV.GetOrderedReplayTapOffsets(curScore, true)
		if orderedTaps then
			dvt, nrv, ctt, ntt = {}, {}, {}, {}
			plotMisses = nil
			for i, tap in ipairs(orderedTaps) do
				dvt[i] = orderedOffsets[i]
				nrv[i] = tap.row
				ctt[i] = tap.track
				ntt[i] = "TapNoteType_Tap"
			end
		end
	end
	offsetStats = HV.Judgment.GetEvaluationOffsetStats(dvt, ntt)
	rescore.data = nil
	if not (HV.ManiaState and HV.ManiaState.enabled) then
		local hits = 0
		for _, key in ipairs({"W1", "W2", "W3", "W4", "W5"}) do
			hits = hits + evaluationTapCount("TapNoteScore_" .. key)
		end
		local offsets = HV.Judgment.GetReplayHits(dvt, ntt, hits)
		-- An all-miss replay and an absent replay both have no hit offsets.
		if offsets and (vectors or curScore == openingScore) then
			local data
			if curScore then data = getRescoreElements(nil, curScore, offsets)
			elseif curScore == openingScore then data = getRescoreElements(pss) end
			if data then
				data.dvt = offsets
				rescore.data = data
			end
		end
	end
end

refreshEvaluationDisplays = function()
	updateVectors()
	clearRatioCache()
	refreshRescoredPercentage()
	MESSAGEMAN:Broadcast("RefreshJudgeDisplay")
	MESSAGEMAN:Broadcast("ManiaModeChanged")
end

local function formatEvaluationPercent(pct)
	if isManiaModeEnabled() then return string.format("%.2f%%", roundTo(pct, 2)) end
	return formatWifePercent(pct)
end

-- osu!mania ScoreV1 long-form score, ported from Fatigue.
-- This is deliberately separate from the 320-point accuracy rescore: osu!'s
-- displayed score is normalized to 1,000,000 and includes combo bonus.
local function getOsuManiaLongScore()
	if not maniaRescore then return 0 end
	local counts = maniaRescore.counts or {}
	local maxScore, totalTaps = 1000000, (steps and steps:GetRadarValues(pn):GetValue("RadarCategory_Notes") or 0)
	local holds = 0
	if pss and pss.GetRadarPossible then
		holds = (pss:GetRadarPossible():GetValue("RadarCategory_Holds") or 0)
			+ (pss:GetRadarPossible():GetValue("RadarCategory_Rolls") or 0)
	end
	local totalNotes = math.max(1, totalTaps + holds)
	local w1, w2, w3, w4, w5, miss = counts[1] or 0, counts[2] or 0, counts[3] or 0, counts[4] or 0, counts[5] or 0, counts[6] or 0
	local helds = evaluationHoldCount("HoldNoteScore_Held")
	local letGos = evaluationHoldCount("HoldNoteScore_LetGo")
	local baseValue = w1 * 320 + w2 * 300 + w3 * 200 + w4 * 100 + w5 * 50 + helds * 320
	local baseScore = (maxScore * 0.5 / totalNotes) * (baseValue / 320)
	local bonusValue, combo = 0, 100
	local bonus = {{32, 2}, {32, 1}, {16, -8}, {8, -24}, {4, -44}}
	if dvt and #dvt > 0 then
		for _, offset in ipairs(dvt) do
			local e = math.abs(offset or math.huge)
			local j = e <= 16 and 1 or (e <= 64 - 3 * HV.ManiaState.od and 2 or (e <= 97 - 3 * HV.ManiaState.od and 3 or (e <= 127 - 3 * HV.ManiaState.od and 4 or (e <= 151 - 3 * HV.ManiaState.od and 5 or 6))))
			if j == 6 then combo = 0 else bonusValue = bonusValue + bonus[j][1] * math.sqrt(combo) / 320; combo = math.max(0, math.min(100, combo + bonus[j][2])) end
		end
	end
	for _ = 1, miss + letGos + math.max(0, totalTaps - (w1 + w2 + w3 + w4 + w5 + miss) - math.max(0, #dvt)) do combo = 0 end
	for _ = 1, helds do bonusValue = bonusValue + 32 * math.sqrt(combo) / 320; combo = math.min(100, combo + 2) end
	return math.max(0, math.min(maxScore, math.floor(baseScore + (maxScore * 0.5 / totalNotes) * bonusValue + 0.5)))
end

local function formatOsuManiaLongScore(score)
	local value = tostring(math.max(0, math.floor(tonumber(score) or 0)))
	while true do
		local replaced
		value, replaced = value:gsub("^(%-?%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then break end
	end
	return value
end

local function getOsuManiaGrade(accuracy, rescoreData)
	accuracy = tonumber(accuracy) or 0
	-- ScoreV2: X rank requires every hit to be 300 or MAX (no 200/100/50/miss)
	if HV.ManiaState and HV.ManiaState.useScoreV2 and rescoreData and rescoreData.counts then
		local c = rescoreData.counts
		if (c[3] or 0) == 0 and (c[4] or 0) == 0 and (c[5] or 0) == 0 and (c[6] or 0) == 0 then
			return "X"
		end
	-- ScoreV1: X rank requires 100% accuracy
	elseif accuracy >= 100 then
		return "X"
	end
	if accuracy >= 95 then return "S" end
	if accuracy >= 90 then return "A" end
	if accuracy >= 80 then return "B" end
	if accuracy >= 70 then return "C" end
	return "D"
end

local maniaGradeColors = {
	X = color("#FFD700"),
	S = color("#FFA500"),
	A = color("#32CD32"),
	B = color("#4DA6FF"),
	C = color("#B56BFF"),
	D = color("#FF4D5A")
}

local function getOsuManiaGradeColor(grade)
	return maniaGradeColors[grade] or brightText
end
playedJudge = getJudgeForScore(curScore)
judge = defaultJudge()
updateVectors()
refreshRescoredPercentage()

-- Local timing helpers (to avoid nil global issues if scripts haven't reloaded)
local function localWifeMean(dvt) return wifeMean(dvt) end
local function localWifeAbsMean(dvt) return wifeAbsMean(dvt) end
local function localWifeSd(dvt) return wifeSd(dvt) end
local function localWifeMax(dvt) return wifeMax(dvt) end

local function getKeycountLabelForSteps(curSteps)
	if not curSteps then return nil end

	local st = tostring(curSteps:GetStepsType() or ""):lower()
	local stepsTypeToKeys = {
		stepstype_dance_single = 4,
		stepstype_dance_double = 8,
		stepstype_pump_single = 5,
		stepstype_pump_halfdouble = 6,
		stepstype_pump_double = 10,
		stepstype_kb7_single = 7,
		stepstype_beat_single5 = 5,
		stepstype_beat_single7 = 7,
		stepstype_popn_five = 5,
		stepstype_popn_nine = 9,
	}

	local keys = stepsTypeToKeys[st]
	if not keys then
		local style = GAMESTATE:GetCurrentStyle()
		if style and style.ColumnsPerPlayer then
			keys = tonumber(style:ColumnsPerPlayer())
		end
	end

	if not keys or keys <= 0 then return nil end
	return tostring(math.floor(keys + 0.5)) .. "K"
end

-- LA/RA Ratio calculation (ported from Til Death)
-- Calculates Ludicrous Attack and Ridiculous Attack ratios from replay offsets
local function calculateRatios(score)
	if scoringVoided then return -1, -1, -1, -1, 0, 0 end
	local replay = score:GetReplay()
	if not replay then return -1, -1, -1, -1 end
	pcall(function() replay:LoadAllData() end)
	local offsetTable = replay:GetOffsetVector()
	local typeTable = replay:GetTapNoteTypeVector()
	if not offsetTable or #offsetTable == 0 or not typeTable or #typeTable == 0 then
		return -1, -1, -1, -1
	end

	-- Define judgment windows based on current judge
	local marvWindow = 22.5 * (ms.JudgeScalers[judge] or 1)
	local raThreshold = marvWindow / 2
	local laThreshold = raThreshold / 2

	local ludic = 0
	local ridicLA = 0
	local ridic = 0
	local marvRA = 0

	for i, o in ipairs(offsetTable) do
		if typeTable[i] == "TapNoteType_Tap" or typeTable[i] == "TapNoteType_HoldHead" then
			local off = math.abs(o) -- Already ms
			if off <= raThreshold then
				ridic = ridic + 1
			elseif off <= marvWindow then
				marvRA = marvRA + 1
			end
			if off <= laThreshold then
				ludic = ludic + 1
			elseif off <= raThreshold then
				ridicLA = ridicLA + 1
			end
		end
	end

	local ra = marvRA > 0 and (ridic / marvRA) or -1
	local la = ridicLA > 0 and (ludic / ridicLA) or -1
	return ra, la, ridic, marvRA, ludic, ridicLA
end

local hjudges = {"HoldNoteScore_Held","HoldNoteScore_LetGo","HoldNoteScore_MissedHold"}
-- Cache for RA/LA ratios to avoid repeated replay loading
local cachedRatios = nil
clearRatioCache = function() cachedRatios = nil end
local function getRatios()
	if not cachedRatios then
		local ra, la, ridic, marvRA, ludic, ridicLA = calculateRatios(curScore)
		cachedRatios = {ra, la, ridic, marvRA, ludic, ridicLA}
	end
	return unpack(cachedRatios)
end

local songTotalNotes = steps:GetRadarValues(pn):GetValue("RadarCategory_Notes")
local songMaxPoints = songTotalNotes * 2

local function failedProgressText()
	local count = 0
	for _, name in ipairs({"W1", "W2", "W3", "W4", "W5", "Miss"}) do
		count = count + evaluationTapCount("TapNoteScore_" .. name)
	end

	-- Combo segments can weight the saved judgments, so they cannot give a
	-- percentage of unweighted chart notes or rows.
	for _, segment in ipairs(steps:GetTimingData():GetCombos(true)) do
		if segment[2] ~= 1 or segment[3] ~= 1 then return string.format("%d weighted judgments", count) end
	end

	local rowJudgments
	if curScore then
		rowJudgments = curScore:GetChordCohesion()
	else
		rowJudgments = not GAMESTATE:CountNotesSeparately()
	end
	local radar = rowJudgments and "RadarCategory_TapsAndHolds" or "RadarCategory_Notes"
	local stage = openingStageRadar()
	local total = stage and stage.possible[radar] or steps:GetRadarValues(pn):GetValue(radar)
	if total <= 0 or count > total then return string.format("%d tap judgments", count) end
	return string.format("%.2f%% %s judged", 100 * count / total, rowJudgments and "rows" or "notes")
end

local function evaluationWifePoints()
	if isOnlineEvaluation() or usingCustomWindows or isManiaModeEnabled() then return end
	if rescore.earned then return rescore.earned, rescore.possible end
	if judge == playedJudge then return HV.Score.GetEvaluationWifePoints(curScore, songMaxPoints) end
	if normalized and curScore and judge == 4 and rescore.data then
		local percent, earned, possible = getRescoredWife3Judge(3, 4, rescore.data)
		if possible and math.abs(percent - evaluationWifeScore() * 100) <= 0.0001 then
			return earned, possible
		end
	end
end

local function getRunningWife(wife, judged)
	if judged == 0 then return 0 end
	return wife * (songTotalNotes / judged)
end

local function nearestGradeComparison(percent)
	if not percent or isManiaModeEnabled() then return "" end
	local baseTiers = {
		"Grade_Tier01", "Grade_Tier04", "Grade_Tier07", "Grade_Tier10",
		"Grade_Tier13", "Grade_Tier14", "Grade_Tier15", "Grade_Tier16",
	}
	local score = percent / 100
	local currentIndex = #baseTiers
	for i, tier in ipairs(baseTiers) do
		if score >= (WifeTiers[tier] or 0) then currentIndex = i; break end
	end
	local targetIndex = math.max(1, currentIndex - 1)
	local currentTier = WifeTiers[baseTiers[currentIndex]] or 0
	local targetTier = WifeTiers[baseTiers[targetIndex]] or currentTier
	-- Only show a negative differential after crossing the midpoint toward
	-- the next higher grade; otherwise compare positively to the current grade.
	if targetIndex < currentIndex and score < (currentTier + targetTier) / 2 then
		targetIndex = currentIndex
	end
	local target = baseTiers[targetIndex]
	local wifeDP = score * songMaxPoints
	local thresholdDP = (WifeTiers[target] or 0) * songMaxPoints
	return string.format("%s %+0.2f", HV.GetGradeName(target), wifeDP - thresholdDP)
end
local clearType = scoringVoided and nil or getClearType(pn, steps, curScore)

local accentColor = HVColor.Accent
local brightText = color("1,1,1,1")
local dimText = brightText
local subText = brightText
local mainText = brightText
local bgCard = color("0.06,0.06,0.06,0.7")
local dividerColor = color("0.2,0.2,0.2,1")

local judgmentColors = {
	HVColor.GetJudgmentColor("W1"), HVColor.GetJudgmentColor("W2"), HVColor.GetJudgmentColor("W3"),
	HVColor.GetJudgmentColor("W4"), HVColor.GetJudgmentColor("W5"), HVColor.GetJudgmentColor("Miss")
}
local function getDisplayedJudgeCount(judgeName, judgeIndex)
	if scoringVoided then return 0 end
	local key = judgeName:gsub("TapNoteScore_", "")
	if usingCustomWindows and lastSnapshot then
		return lastSnapshot.counts[key] or 0
	end
	if maniaRescore then return maniaRescore.counts[judgeIndex] or 0 end
	if judge == playedJudge then return evaluationTapCount(judgeName) end
	if not rescore.counts then return end
	return rescore.counts[key]
end

local function customWindowUsesOldestNoteFirst()
	if not customWindowsConfig then return false end
	if type(currentCustomWindowConfigUsesOldestNoteFirst) == "function" then
		local ok, value = pcall(currentCustomWindowConfigUsesOldestNoteFirst)
		if ok then return value == true end
	end
	local data = customWindowsConfig:get_data()
	local order = data and data.customWindowOrder or {}
	local activeIndex = rawget(_G, "customWindowIndex") or rawget(_G, "customWindowConfigIndex") or rawget(_G, "currentCustomWindowIndex") or 1
	local configName = order and order[activeIndex]
	local config = data and data.customWindowConfigs and data.customWindowConfigs[configName]
	local value = config and config.judgeByOldestNote
	return value == true or value == "true" or value == 1 or value == "1"
end

local maniaJudgeLabels = {"MAX", "300", "200", "100", "50", "MISS"}
local function getEvaluationJudgeLabel(judgeName, judgeIndex)
	if maniaRescore or (HV.ManiaState and HV.ManiaState.enabled) then return maniaJudgeLabels[judgeIndex] or "" end
	return getJudgeStrings(judgeName)
end

local function judgmentFraction(count, total)
	if count and total and total > 0 then return count / total end
end

local function displayedJudgmentFraction(judgeName, judgeIndex)
	local total = usingCustomWindows and lastSnapshot and lastSnapshot.totalTaps
		or (maniaRescore and totalTaps or songTotalNotes)
	return judgmentFraction(getDisplayedJudgeCount(judgeName, judgeIndex), total)
end

local function getRATallyCount(rowIndex)
	if scoringVoided then return 0 end
	local ra, la, ridic, marvRA, ludic, ridicLA = getRatios()
	if rowIndex == 1 then return ludic
	elseif rowIndex == 2 then return ridicLA
	elseif rowIndex == 3 then return marvRA
	elseif rowIndex == 4 then return evaluationTapCount("TapNoteScore_W2")
	elseif rowIndex == 5 then return evaluationTapCount("TapNoteScore_W3")
	elseif rowIndex == 6 then return evaluationTapCount("TapNoteScore_Miss")
	end
	return 0
end

-- Combo Graph Configuration
local comboConfig = {
 	{ name = "8ms FA+",  window = 8.0,  judgment = 4, color = color("#c3f1ff") },
 	{ name = "10ms FA+", window = 10.0,  judgment = 4, color = color("#86e3ff") },
 	{ name = "15ms FA+", window = 15.0,  judgment = 4, color = color("#39d1ff") },
	{ name = "Marvelous", window = 22.5,  judgment = 4, color = HVColor.GetJudgmentColor("W1") },
 	{ name = "J6 Perfect", window = 45.0,  judgment = 6, color = color("#feffafff") },
	{ name = "Perfect", window = 45.0, judgment = 4, color = HVColor.GetJudgmentColor("W2") },
 }

-- Life Difficulty Color Helper (1-7 scale)
local function getLifeDifficultyColor(diff)
	local c1 = color("#A0CFAB") -- Easy / Green
	local c2 = color("#CFD198") -- Normal / Gold
	local c3 = color("#CF9898") -- Hard / Red
	if diff <= 4 then
		return HV.LerpColor((diff - 1) / 3, c1, c2)
	else
		return HV.LerpColor((diff - 4) / 3, c2, c3)
	end
end

-- Combo Graph Calculation Logic (custom)
local function calculateMaxStreaks(dvt, nrv, config)
	local results = {}
	for i = 1, #config do
		results[i] = { max = 0, startRow = 0, endRow = 0 }
	end
	if not dvt or not nrv then return results end

	local currentStreaks = {}
	local startRows = {}
	for i = 1, #config do currentStreaks[i] = 0 startRows[i] = 1 end

	for idx = 1, #dvt do
		local off = dvt[idx]
		local row = nrv[idx] or 0
		local absOff = math.abs(off)
		
		for i, conf in ipairs(config) do
			local threshold = conf.window * (ms.JudgeScalers[conf.judgment] or 1)
			if absOff <= threshold then
				if currentStreaks[i] == 0 then
					startRows[i] = row
				end
				currentStreaks[i] = currentStreaks[i] + 1
				if currentStreaks[i] > results[i].max then
					results[i].max = currentStreaks[i]
					results[i].startRow = startRows[i]
					results[i].endRow = row
				end
			else
				currentStreaks[i] = 0
			end
		end
	end
	return results
end

-- Scroll support
local function scroller(event)
	if event.type == "InputEventType_FirstPress" then
		if event.DeviceInput.button == "DeviceButton_mousewheel up" then
			MESSAGEMAN:Broadcast("WheelUpSlow")
		elseif event.DeviceInput.button == "DeviceButton_mousewheel down" then
			MESSAGEMAN:Broadcast("WheelDownSlow")
		elseif event.DeviceInput.button == "DeviceButton_left mouse button" then
			MESSAGEMAN:Broadcast("MouseLeftClick", {event=event})
		end
	end
end

local function isOver(actor)
	if not actor or not actor.GetVisible or not actor:GetVisible() then return false end
	if actor.IsVisible and not actor:IsVisible() then return false end
	local x = actor:GetTrueX()
	local y = actor:GetTrueY()
	local w = actor:GetZoomedWidth()
	local h = actor:GetZoomedHeight()
	local ha = actor.GetHAlign and actor:GetHAlign() or 0
	local va = actor.GetVAlign and actor:GetVAlign() or 0
	local mx = INPUTFILTER:GetMouseX()
	local my = INPUTFILTER:GetMouseY()
	return mx >= x - w * ha and mx <= x + w * (1 - ha) and my >= y - h * va and my <= y + h * (1 - va)
end

local function selectEvaluationScore(score, online, refreshReplay)
	if scoringVoided then return false end
	if not score or not steps or score:GetChartKey() ~= steps:GetChartKey() or score:GetScoreKey() == "" then return false end
	local sameScore = curScore and score:GetScoreKey() == curScore:GetScoreKey()
	if refreshReplay then
		if not sameScore or not selectedOnline then return false end
		curScore = score
		updateVectors()
		clearRatioCache()
		refreshRescoredPercentage()
		MESSAGEMAN:Broadcast("ScoreChanged", {score = score, judge = judge})
		return true
	end
	if sameScore then return true end

	local hadCustomWindows = usingCustomWindows
	usingCustomWindows, lastSnapshot = false, nil
	if hadCustomWindows then unloadCustomWindowConfig() end

	if openingScore and score:GetScoreKey() == openingScore:GetScoreKey() then
		curScore, selectedOnline = openingScore, openingIsOnline
	else
		curScore, selectedOnline = score, online == true
	end
	playedJudge = getJudgeForScore(curScore)
	judge = defaultJudge()
	clearType = getClearType(pn, steps, curScore)
	updateVectors()
	clearRatioCache()
	refreshRescoredPercentage()

	if hadCustomWindows then
		MESSAGEMAN:Broadcast("UnloadedCustomWindow")
		MESSAGEMAN:Broadcast("CustomWindowStateChanged")
	end
	MESSAGEMAN:Broadcast("ScoreChanged", {score = curScore, judge = judge})
	return true
end

local t = Def.ActorFrame {
	Name = "EvalDecorations",
	OnCommand = function(self)
		HV.ResetManiaMode()
		maniaRescore = nil
		SCREENMAN:GetTopScreen():AddInputCallback(scroller)
		SCREENMAN:SetSystemCursorVisible(true)
		if INPUTFILTER and INPUTFILTER.SetMouseVisible then
			INPUTFILTER:SetMouseVisible(true)
		end
		self:sleep(0):queuecommand("RefreshJudgeDisplay")
	end,
	OffCommand = function(self)
		if usingCustomWindows then unloadCustomWindowConfig() end
		HV.ResetManiaMode()
	end,
	LoadFont("Common Normal") .. {
		Name = "OnlineReplayWatermark",
		InitCommand = function(self)
			self:xy(SCREEN_CENTER_X, SCREEN_CENTER_Y):zoom(2.2):rotationz(-15)
				:diffuse(accentColor):diffusealpha(0.14):z(999):draworder(10000):visible(false)
			self:settext("ONLINE REPLAY")
		end,
		OnCommand = function(self)
			self:visible(openingIsOnline and curScore == openingScore)
		end,
		ScoreChangedMessageCommand = function(self) self:visible(openingIsOnline and curScore == openingScore) end,
	},

	RefreshJudgeDisplayCommand = function(self)
		playedJudge = getJudgeForScore(curScore)
		judge = defaultJudge()
		updateVectors()
		clearRatioCache()
		refreshRescoredPercentage()
		self:RunCommandsOnChildren(function(self) self:playcommand("SetJudge") end)
	end,

	Def.Actor {
		Name = "SessionGradeLogger",
		OnCommand = function()
			local countPlay = HV.GameplaySessionValid and not isReplay
			HV.GameplaySessionValid = false
			if countPlay and GRADECOUNTERSTORAGE then
				local grade = normalized and openingScore and openingScore:GetWifeGrade() or pss:GetWifeGrade()
				GRADECOUNTERSTORAGE:incrementSession(grade)
			end
		end,
	},
}

-- Rescore data + rescore delegate to the corrected global functions in 08 EtternaUtils.lua.

------------------------------------------------------------
-- LEFT PANEL: SCORE CARD
------------------------------------------------------------
local function loadEvaluationCustomWindow()
	lastSnapshot = nil
	if not curScore or not curScore:HasReplayData() then return false end
	local ok, snapshot = pcall(function()
		loadCurrentCustomWindowConfig()
		local screen = SCREENMAN:GetTopScreen()
		if not screen:RescoreReplay(pss, 1, curScore, customWindowUsesOldestNoteFirst()) then return end
		local replay = REPLAYS:GetActiveReplay()
		if not replay or replay:GetScoreKey() ~= curScore:GetScoreKey()
			or replay:GetChartKey() ~= curScore:GetChartKey() then return end
		local result = replay:GetLastReplaySnapshot()
		local possible, earned = result:GetMaxWifeScore(), result:GetCurWifeScore()
		if possible > 0 and possible < math.huge and earned == earned and math.abs(earned) < math.huge then
			local counts = result:GetJudgments()
			local taps = 0
			for _, name in ipairs({"W1", "W2", "W3", "W4", "W5", "Miss"}) do taps = taps + (counts[name] or 0) end
			return {percent = 100 * earned / possible, counts = counts, totalTaps = taps}
		end
	end)
	unloadCustomWindowConfig()
	if not ok or not snapshot then return false end
	lastSnapshot = snapshot
	return true
end

local function createScoreBoard(pn, frameW, pad)
	local frameX = 10
	local frameY = 10
	local frameH = SCREEN_HEIGHT - 20
	local modIconsY = 8
	local topHeaderY = pad + 10

	local board = Def.ActorFrame {
		Name = "EvaluationSummary",
		ScoreChangedMessageCommand = function(self)
			self:RunCommandsOnChildren(function(child) child:playcommand("On") end)
			self:RunCommandsOnChildren(function(child) child:playcommand("SetJudge") end)
		end,
		InitCommand = function(self)
			self:xy(frameX - 55, frameY):diffusealpha(0)
		end,
		OnCommand = function(self)
			self:sleep(0.25):linear(0.4):x(frameX):diffusealpha(1)
		end,
		OffsetPlotModificationMessageCommand = function(self, params)
			if params.Name == "Coin" then
				self:playcommand("ToggleCustomWindows")
				return
			end

			if usingCustomWindows then
				if params.Name == "PrevJudge" then
					self:playcommand("MoveCustomWindowIndex", {direction=-1})
				elseif params.Name == "NextJudge" then
					self:playcommand("MoveCustomWindowIndex", {direction=1})
				end
				return
			end

			if params.Name == "PrevJudge" then
				if judge == 4 then return end
				judge = judge - 1
			elseif params.Name == "NextJudge" then
				if judge == 9 then return end
				judge = judge + 1
			elseif params.Name == "ResetJudge" then
				judge = defaultJudge()
			else
				return
			end
			refreshRescoredPercentage()
			if params.Name == "ResetJudge" then
				self:RunCommandsOnChildren(function(child) child:playcommand("ResetJudge") end)
			end
			self:RunCommandsOnChildren(function(child) child:playcommand("SetJudge") end)
			MESSAGEMAN:Broadcast("EvaluationJudgeChanged")
		end,
		ToggleCustomWindowsMessageCommand = function(self)
			if inMulti or not curScore then return end
			if usingCustomWindows then
				usingCustomWindows, lastSnapshot = false, nil
				MESSAGEMAN:Broadcast("UnloadedCustomWindow")
			else
				usingCustomWindows = loadEvaluationCustomWindow()
				if usingCustomWindows then
					MESSAGEMAN:Broadcast("LoadedCustomWindow")
				else
					SCREENMAN:SystemMessage("Custom windows unavailable for this replay")
				end
			end
			MESSAGEMAN:Broadcast("CustomWindowStateChanged")
			self:RunCommandsOnChildren(function(child) child:playcommand("UpdateCustomWindowVisibility") end)
		end,
		MoveCustomWindowIndexMessageCommand = function(self, params)
			if not usingCustomWindows then return end
			moveCustomWindowConfigIndex(params.direction)
			usingCustomWindows = loadEvaluationCustomWindow()
			if usingCustomWindows then
				MESSAGEMAN:Broadcast("LoadedCustomWindow")
			else
				MESSAGEMAN:Broadcast("UnloadedCustomWindow")
				SCREENMAN:SystemMessage("Custom windows unavailable for this replay")
			end
			MESSAGEMAN:Broadcast("CustomWindowStateChanged")
			self:RunCommandsOnChildren(function(child) child:playcommand("UpdateCustomWindowVisibility") end)
		end,

		-- Main BG
		Def.Quad {
			InitCommand = function(self) self:halign(0):valign(0):zoomto(frameW, frameH):diffuse(bgCard):diffusealpha(0) end,
			OnCommand = function(self)
				self:sleep(0.05):linear(0.35):diffusealpha(0.7):x(0)
			end
		},

		Def.ActorFrame {
			Name = "ModIcons",
			InitCommand = function(self)
				self:xy(20, modIconsY):diffusealpha(0)
			end,
			OnCommand = function(self)
				self:playcommand("Update")
				self:sleep(0.12):linear(0.25):diffusealpha(1)
			end,
			UpdateCommand = function(self)
				local ps = GAMESTATE:GetPlayerState(pn)
				if not ps then return end

				local po = ps:GetPlayerOptions("ModsLevel_Current")
				local modStr = (curScore and curScore.GetModifiers and curScore:GetModifiers())
					or ps:GetPlayerOptionsString("ModsLevel_Current")
					or ""
				if modStr == "" then
					modStr = ps:GetPlayerOptionsString("ModsLevel_Preferred") or ""
				end
				local normalizedModStr = modStr:lower():gsub("[%s_]+", "")

				local speed, mode = 400, "C"
				if GetSpeedModeAndValueFromPoptions then
					speed, mode = GetSpeedModeAndValueFromPoptions(pn)
				end

				local rate = (curScore and curScore.GetMusicRate and curScore:GetMusicRate())
					or (getCurRateValue and getCurRateValue())
					or 1
				local life = GetLifeDifficulty()
				local playedJudge = curScore and getJudgeForScore(curScore) or GetTimingDifficulty()
				local fail = po and po:FailSetting() or "FailType_Immediate"
				local assist = hasEvaluationAssistEnabled(po, modStr)

				local accent = accentColor or (HVColor and HVColor.Accent) or color("#5ABAFF")
				local dim = (HVColor and HVColor.TextDim) or color("0.4,0.4,0.4,1")
				local warn = color("#CF9898")

				self:GetChild("Speed"):settext(formatEvalSpeedMode(mode, speed)):diffuse(accent)
				self:GetChild("Rate"):settext(formatEvalRateValue(rate)):diffuse(accent)

				self:GetChild("Life"):settext(string.format("L%d", life)):diffuse(accent)
				self:GetChild("Judge"):settext(string.format("J%d", playedJudge)):diffuse(accent)

				local failText = "F:IMM"
				if fail == "FailType_Off" then
					failText = "F:OFF"
				elseif fail == "FailType_EndOfSong" then
					failText = "F:END"
				end
				self:GetChild("Fail"):settext(failText):diffuse(fail == "FailType_Immediate" and accent or warn)
				self:GetChild("Assist"):settext("AST"):diffuse(assist and accent or dim)

				local active = {}
				for mod, short in pairs(evalModShorthands) do
					local normalizedMod = mod:lower()
					local matched = string.find(normalizedModStr, normalizedMod)
					if mod == "Mines" then
						matched = string.find(normalizedModStr, "mines") and not string.find(normalizedModStr, "nomines")
					elseif mod == "Shuffle" then
						matched = string.find(normalizedModStr, "shuffle")
							and not string.find(normalizedModStr, "softshuffle")
							and not string.find(normalizedModStr, "supershuffle")
					end
					if matched then
						table.insert(active, short)
					end
				end

				local receptorSize = tonumber(ThemePrefs.Get("HV_Mini")) or 100
				if math.abs(receptorSize - 100) > 0.001 then
				table.insert(active, "RS" .. math.round(receptorSize))
				end

				self:GetChild("Separator"):visible(#active > 0)
				self:GetChild("Mods"):settext(table.concat(active, "  ")):diffuse(accent)
			end,
			ScoreChangedMessageCommand = function(self)
				self:finishtweening():sleep(0):queuecommand("Update")
			end,
			LoadFont("Common Normal") .. { Name = "Speed", InitCommand = function(self) self:zoom(0.4):halign(0) end },
			LoadFont("Common Normal") .. { Name = "Rate", InitCommand = function(self) self:x(42):zoom(0.4):halign(0) end },
			LoadFont("Common Normal") .. { Name = "Life", InitCommand = function(self) self:x(82):zoom(0.4):halign(0) end },
			LoadFont("Common Normal") .. { Name = "Judge", InitCommand = function(self) self:x(110):zoom(0.4):halign(0):diffuse(accentColor or (HVColor and HVColor.Accent) or color("#5ABAFF")) end },
			LoadFont("Common Normal") .. { Name = "Fail", InitCommand = function(self) self:x(138):zoom(0.4):halign(0):diffuse(color("#CF9898")) end },
			LoadFont("Common Normal") .. { Name = "Assist", InitCommand = function(self) self:x(182):zoom(0.4):halign(0):diffuse(accentColor or (HVColor and HVColor.Accent) or color("#5ABAFF")) end },
			LoadFont("Common Normal") .. {
				Name = "Separator",
				InitCommand = function(self) self:x(217):zoom(0.4):halign(0):settext("|"):diffuse(color("0.4,0.4,0.4,1")) end
			},
			LoadFont("Common Normal") .. {
				Name = "Mods",
				InitCommand = function(self) self:x(232):zoom(0.4):halign(0):diffuse(accentColor or (HVColor and HVColor.Accent) or color("#5ABAFF")) end
			}
		},

		-- Banner + Profile Display
		Def.ActorFrame {
			Name = "TopHeader",
			InitCommand = function(self) self:xy(20, topHeaderY) end,

			Def.Sprite {
				Name = "Banner",
				InitCommand = function(self) self:halign(0):valign(0):xy(pad -20, 0):diffusealpha(0) end,
				OnCommand = function(self)
					if song then
						local bpath = song:GetBannerPath()
						if not bpath then bpath = THEME:GetPathG("Common", "fallback banner") end
						self:LoadBackground(bpath)
						self:scaletoclipped((frameW - pad * 3) * 0.5, 60)
					end
					self:stoptweening():sleep(0.05):linear(0.25):diffusealpha(1)
				end
			},

			Def.ActorFrame {
				Name = "ProfileDisplay",
				InitCommand = function(self) 
					self:xy(pad + (frameW - pad * 3) * 0.5 + pad - 20, 0):diffusealpha(0) 
				end,
				OnCommand = function(self)
					self:sleep(0.1):linear(0.25):diffusealpha(1)
				end,

				-- Avatar
				Def.Sprite {
					Name = "Avatar",
					InitCommand = function(self) self:halign(0):valign(0):zoomto(60, 60) end,
					BeginCommand = function(self) self:playcommand("SetAvatar") end,
					ScoreChangedMessageCommand = function(self) self:playcommand("SetAvatar") end,
					SetAvatarCommand = function(self)
						local avatar = isOnlineEvaluation() and getDefaultAssetByType("avatar") or getAvatarPath(pn)
						self:Load(avatar):zoomto(60, 60)
					end,
				},

				-- Name: online evaluations show only the viewed leaderboard player.
				LoadFont("Common Normal") .. {
					Name = "PlayerName",
					InitCommand = function(self)
						local zoom = 0.50
						self:xy(65, 11):zoom(zoom):halign(0):maxwidth(((frameW - pad * 3) * 0.5 - 65) / zoom)
						self.showOnline = true
						self.transitionDuration = 0.25
						self.displayDuration = 3
						self.localOnlineName = DLMAN:IsLoggedIn() and DLMAN:GetUsername() or nil
						if isOnlineEvaluation() then
							self.replayName = HV.OnlineEvaluationName or HV.OnlineReplayName
						end
						if isOnlineEvaluation() and curScore and not self.replayName then
							local getter = curScore.GetDisplayName or curScore.GetName
							if getter then
								local ok, replayName = pcall(getter, curScore)
								local placeholder = { ["Player 1"] = true, ["Player 2"] = true, ["Replay"] = true, ["Unknown"] = true, ["???"] = true }
								if ok and replayName and replayName ~= "" and not placeholder[tostring(replayName)] then
									self.replayName = tostring(replayName)
								end
							end
						end
						self.offlineName = profile and profile:GetDisplayName() or nil
						if self.offlineName == "" then self.offlineName = nil end
					end,
					OnCommand = function(self) self:playcommand("SetName") end,
					ScoreChangedMessageCommand = function(self) self:playcommand("SetName") end,
					SetNameCommand = function(self)
						self:stoptweening():diffusealpha(1)
						self.onlineName = self.localOnlineName
						if isOnlineEvaluation() then
							self.showOnline = true
							local name = curScore and curScore.GetDisplayName and curScore:GetDisplayName()
							if curScore == openingScore and self.replayName then name = self.replayName end
							self:settext(name and name ~= "" and name or "Online Player")
							return
						elseif not self.onlineName then
							self:settext(self.offlineName or "Player 1")
							return
						elseif not self.offlineName or self.onlineName == self.offlineName then
							self:settext(self.onlineName)
							return
						end
						self:playcommand("UpdateName")
					end,
					UpdateNameCommand = function(self)
						self:stoptweening():linear(self.transitionDuration * 0.5):diffusealpha(0):queuecommand("SwapName")
					end,
					SwapNameCommand = function(self)
						local nextName = self.showOnline and self.onlineName or self.offlineName
						self:settext(nextName)
						self.showOnline = not self.showOnline
						self:stoptweening():linear(self.transitionDuration * 0.5):diffusealpha(1):sleep(self.displayDuration):queuecommand("UpdateName")
					end
				},

				-- Rating (Player SSR - cycles between online and offline with fade)
				LoadFont("Common Large") .. {
					Name = "PlayerRating",
					InitCommand = function(self)
						self:xy(65, 35):zoom(0.45):halign(0)
						self.showOnline = true
						self.transitionDuration = 0.25
						self.onlineRating = DLMAN:IsLoggedIn() and DLMAN:GetSkillsetRating("Overall") or nil
						self.offlineRating = profile and profile:GetPlayerRating() or nil
					end,
					OnCommand = function(self)
						if isOnlineEvaluation() or not HV.ShowMSD() then self:visible(false); return end
						if not profile then return end

						if not self.onlineRating or self.onlineRating <= 0 then
							self:settextf("%.2f", self.offlineRating)
							self:diffuse(HVColor.GetMSDRatingColor(self.offlineRating))
							return
						elseif not self.offlineRating or self.offlineRating <= 0 or math.abs(self.onlineRating - self.offlineRating) < 0.01 then
							self:settextf("%.2f", self.onlineRating)
							self:diffuse(HVColor.GetMSDRatingColor(self.onlineRating))
							return
						end
						self:playcommand("UpdateRating")
					end,
					UpdateRatingCommand = function(self)
						self:stoptweening():linear(self.transitionDuration * 0.5):diffusealpha(0):queuecommand("SwapRating")
					end,
					SwapRatingCommand = function(self)
						local val = self.showOnline and self.onlineRating or self.offlineRating
						self:settextf("%.2f", val)
						self:diffuse(HVColor.GetMSDRatingColor(val))
						self.showOnline = not self.showOnline
						self:stoptweening():linear(self.transitionDuration * 0.5):diffusealpha(1):sleep(3):queuecommand("UpdateRating")
					end
				}
			}
		},

		-- Song Title
		LoadFont("Common Large") .. {
			InitCommand = function(self)
				self:halign(0):valign(0):xy(pad - 10, pad + 80):zoom(0.55):diffuse(brightText):diffusealpha(0)
				self:maxwidth((frameW - pad*2 - 105) / 0.5)
			end,
			OnCommand = function(self) 
				if song then self:settext(song:GetDisplayMainTitle()) end 
				self:sleep(0.1):linear(0.25):xy(pad, pad + 80):diffusealpha(1)
			end
		},
		-- Artist
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:halign(0):valign(0):xy(pad - 10, pad + 104):zoom(0.5):diffuse(subText):diffusealpha(0)
				self:maxwidth((frameW - pad*2) / 0.5)
			end,
			OnCommand = function(self) 
				if song then self:settext("// " .. song:GetDisplayArtist()) end 
				self:sleep(0.15):linear(0.25):xy(pad, pad + 104):diffusealpha(1)
			end
		},
		-- Pack Name
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:halign(0):valign(0):xy(pad - 10, pad + 120):zoom(0.4):diffuse(subText):diffusealpha(0)
				self:maxwidth((frameW - pad*2) / 0.4)
			end,
			OnCommand = function(self) 
				if song then self:settext(song:GetGroupName()) end 
				self:sleep(0.2):linear(0.25):xy(pad, pad + 120):diffusealpha(1)
			end
		},
		-- Compact Difficulty + MSD
		Def.ActorFrame {
			InitCommand = function(self) self:xy(frameW - pad + 10, pad + 80):diffusealpha(0) end,
			OnCommand = function(self)
				self:sleep(0.2):linear(0.25):xy(frameW - pad, pad + 80):diffusealpha(1)
			end,
			
			-- Shorthand (colored by difficulty type)
			LoadFont("Common Normal") .. {
				InitCommand = function(self)
					self:halign(1):valign(1):xy(-51, 14):zoom(0.55)
				end,
				OnCommand = function(self)
					if steps then
						local diff = ToEnumShortString(steps:GetDifficulty())
						local diffShort = {
							Beginner = "BG", Easy = "EZ", Medium = "NM", Hard = "HD", Challenge = "IN", Edit = "ED"
						}
						local diffLabel = diffShort[diff] or diff:sub(1,2):upper()
						local keyLabel = getKeycountLabelForSteps(steps)
						self:settext((keyLabel and (keyLabel .. " " .. diffLabel)) or diffLabel)
						self:diffuse(HVColor.GetDifficultyColor(diff))
					end
				end
			},
			-- MSD (Common Large, 2 decimal points)
			LoadFont("Common Large") .. {
				InitCommand = function(self)
					self:halign(1):valign(0):xy(0, -2):zoom(0.6)
				end,
				OnCommand = function(self)
					if steps then
						local msd = steps:GetMSD(curScore and curScore:GetMusicRate() or getCurRateValue(), 1)
						if HV.ShowMSD() and msd > 0 then
							self:settextf("%.2f", msd)
							self:diffuse(HVColor.GetMSDRatingColor(msd))
							self:diffuse(HVColor.GetMSDRatingColor(msd))
						else
							self:settext(tostring(steps:GetMeter()))
							self:diffuse(brightText)
						end
					end
				end
			}
		},
		-- Rate
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:halign(1):valign(0):xy(frameW - pad + 10, pad + 100):zoom(0.65):diffuse(brightText):diffusealpha(0)
			end,
			OnCommand = function(self) 
				self:settext(curScore and formatEvalRateValue(curScore:GetMusicRate()) or getCurRate())
				self:sleep(0.25):linear(0.25):xy(frameW - pad, pad + 100):diffusealpha(1)
			end
		},
		-- Timing judge display
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:halign(1):valign(0):xy(frameW - pad, pad + 114):zoom(0.5):diffuse(dimText)
			end,
			OnCommand = function(self) self:settextf("Judge: %d", judge) end,
			SetJudgeCommand = function(self)
				self:settext(HV.ManiaState and HV.ManiaState.enabled and string.format("osu!mania OD %.1f", HV.ManiaState.od) or string.format("Judge: %d", judge))
			end,
			ResetJudgeCommand = function(self) self:playcommand("SetJudge") end,
			ManiaModeChangedMessageCommand = function(self) self:playcommand("SetJudge") end
		},
		LoadFont("Common Normal") .. {
			Name = "OffsetPriorityStatus",
			InitCommand = function(self) self:halign(1):valign(0):xy(frameW - pad, pad + 128):zoom(0.28):diffuse(accentColor):visible(false) end,
			SetJudgeCommand = function(self)
				local active = (HV.ManiaState and HV.ManiaState.enabled) or (usingCustomWindows and customWindowUsesOldestNoteFirst())
				self:settext(active and "Offsets Reprioritized" or "")
				self:visible(active)
			end,
			ManiaModeChangedMessageCommand = function(self) self:playcommand("SetJudge") end,
			LoadedCustomWindowMessageCommand = function(self) self:playcommand("SetJudge") end,
			UnloadedCustomWindowMessageCommand = function(self) self:playcommand("SetJudge") end,
			ResetJudgeMessageCommand = function(self) self:playcommand("SetJudge") end
		},



		-- Separator
		Def.Quad {
			InitCommand = function(self)
				self:halign(0):valign(0):xy(pad, pad + 135):zoomto(frameW - pad*2, 1):diffuse(dividerColor)
			end
		},
	}

	-- ============================================================
	-- GRADE + SCORE AREA
	-- ============================================================
	board[#board + 1] = Def.ActorFrame {
		Name = "GradeScore",
		InitCommand = function(self) self:xy(pad, pad + 145) end,

		-- Menacing CC Indicator
		LoadFont("Common Normal") .. {
			Name = "ChordCohesionIndicator",
			InitCommand = function(self) self:xy(0, -25):halign(0):zoom(0.6):diffuse(color("#FF0000")):visible(false) end,
			ManiaModeChangedMessageCommand = function(self)
				local active = not isManiaModeEnabled() and curScore and curScore:GetChordCohesion()
				self:visible(active == true)
				if not active then self:settext("") end
			end,
			OnCommand = function(self)
				if not isManiaModeEnabled() and curScore and curScore:GetChordCohesion() then
					self:visible(true):pulse():effectmagnitude(1, 1.1, 1):effecttiming(0.25, 0.25, 0.25, 0.25)
					self:settext("Chord Cohesion ON")
				else
					self:visible(false):settext("")
				end
			end,
			ScoreChangedMessageCommand = function(self) self:playcommand("On") end
		},

		-- Grade
		LoadFont("Common Large") .. {
			Name = "GradeScoreLabel",
			InitCommand = function(self) self:halign(0):valign(0):xy(0, 0):zoom(0.85):diffuse(mainText):diffusealpha(0) end,
			OnCommand = function(self)
				self:playcommand("SetJudge")
				self:stoptweening():sleep(0.3):linear(0.2):zoom(0.7):diffusealpha(1)
			end,
			SetJudgeCommand = function(self)
				if usingCustomWindows then return end
				if isManiaModeEnabled() then
					local grade = getOsuManiaGrade(rescore.percent, maniaRescore)
					self:settext(grade):diffuse(getOsuManiaGradeColor(grade))
					return
				end
				local grade = evaluationGrade()
				local percent = displayedWifePercent()
				if grade ~= "Grade_Failed" and rescore.percent then grade = GetGradeFromPercent(percent / 100) end
				local shortGrade = ToEnumShortString(grade)
				self:settext(percent and HV.GetGradeName(shortGrade) or "-")
					:diffuse(HVColor.GetGradeColor(shortGrade))
			end,
			ManiaModeChangedMessageCommand = function(self) self:playcommand("SetJudge") end
		},
		LoadFont("Common Normal") .. {
			Name = "NearestGrade",
			InitCommand = function(self) self:halign(0):valign(0):xy(1, 25):zoom(0.38):diffuse(subText):diffusealpha(0) end,
			OnCommand = function(self)
				self:visible(not usingCustomWindows and not isManiaModeEnabled())
				self:settext(nearestGradeComparison(displayedWifePercent())):sleep(0.3):linear(0.2):diffusealpha(1)
			end,
			SetJudgeCommand = function(self)
				self:visible(not usingCustomWindows and not isManiaModeEnabled())
				self:settext(nearestGradeComparison(displayedWifePercent()))
			end,
			ToggleCustomWindowsMessageCommand = function(self) self:playcommand("SetJudge") end,
			LoadedCustomWindowMessageCommand = function(self) self:playcommand("SetJudge") end,
			UnloadedCustomWindowMessageCommand = function(self) self:playcommand("SetJudge") end,
			CustomWindowStateChangedMessageCommand = function(self) self:playcommand("SetJudge") end,
			ManiaModeChangedMessageCommand = function(self) self:playcommand("SetJudge") end
		},
		-- SSR
		LoadFont("Common Normal") .. {
			InitCommand = function(self) self:halign(0):valign(0):xy(10, 45):zoom(1.05):diffuse(subText):diffusealpha(0) end,
			OnCommand = function(self)
				if HV.ShowMSD() then
					local ssr = curScore and curScore:GetSkillsetSSR("Overall") or 0
					self:settextf("%.2f", ssr)
					self:diffuse(HVColor.GetMSDRatingColor(ssr))
					self:sleep(0.4):linear(0.2):diffusealpha(1)
				else
					self:settext("")
					self:visible(false)
				end
			end
		},

		-- Custom Scoring Label
		LoadFont("Common Normal") .. {
			Name = "CustomScoringLabel",
			InitCommand = function(self) self:halign(0):valign(0):xy(110, -5):zoom(0.45):diffuse(accentColor):visible(false) end,
			OnCommand = function(self)
				if usingCustomWindows then
					self:visible(true)
					self:settext(getCurrentCustomWindowConfigName())
				end
			end,
			LoadedCustomWindowMessageCommand = function(self)
				self:visible(true)
				self:settext(getCurrentCustomWindowConfigName())
			end,
			UnloadedCustomWindowMessageCommand = function(self)
				self:visible(false)
			end
		},

		-- Wife Score Wrapper
		Def.ActorFrame {
			Name = "WifeScoreWrapper",
			InitCommand = function(self) self:xy(110, 5) end,
			OnCommand = function(self)
				local label = self:GetChild("WifeScoreLabel")
				local wife = displayedWifePercent()
				label:sleep(0.35):linear(0.15):diffusealpha(1)
				if not wife then
					label:settext("-")
					self:SetUpdateFunction(nil)
					return
				end

				-- Incremental counting
				local duration = 0.2
				local curTime = 0
				local targetWife = wife
				self:SetUpdateFunction(function(self, delta)
					curTime = curTime + delta
					local progress = math.min(1, curTime / duration)
					local currentWifeDisplay = targetWife * math.sin(progress * (math.pi / 2)) -- Ease out Sine
					label:settext(formatEvaluationPercent(currentWifeDisplay))
					
					if progress >= 1 then
						self:SetUpdateFunction(nil)
					end
				end)
			end,
			ResetJudgeMessageCommand = function(self) 
				self:SetUpdateFunction(nil)
				self:playcommand("On") 
			end,
			ManiaModeChangedMessageCommand = function(self)
				self:SetUpdateFunction(nil)
				self:playcommand("On")
			end,

			LoadFont("Common Normal") .. {
				Name = "J4WifeScoreLabel",
				InitCommand = function(self) self:halign(0):valign(0):xy(2,-10):zoom(0.4):diffuse(color("#FF6666")):diffusealpha(0) end,
				OnCommand = function(self)
					self:playcommand("SetJudge")
					self:sleep(0.35):linear(0.15):diffusealpha(1)
				end,
				SetJudgeCommand = function(self)
					if usingCustomWindows or isManiaModeEnabled() or judge == 4 then
						self:visible(false)
						return
					end
					local percent = wifePercentAtJudge(4)
					self:visible(percent ~= nil)
					if percent then self:settext("J4: " .. formatWifePercent(percent)) end
				end,
			},

			LoadFont("Common Large") .. {
				Name = "WifeScoreLabel",
				InitCommand = function(self) self:halign(0):valign(0):xy(0,-3):zoom(0.72):diffuse(mainText):diffusealpha(0) end,
				SetJudgeCommand = function(self)
					if usingCustomWindows then return end
					local percent = displayedWifePercent()
					self:settext(percent and formatEvaluationPercent(percent) or "-")
				end,
				ManiaModeChangedMessageCommand = function(self) self:playcommand("SetJudge") end,
				LoadedCustomWindowMessageCommand = function(self)
					if not lastSnapshot then return end
					local wife = lastSnapshot.percent
					self:settext(formatWifePercent(wife))
				end,
			},
			-- CC indicator below Wife%
			LoadFont("Common Normal") .. {
				Name = "CCBelowWife",
				InitCommand = function(self) self:halign(0):valign(0):xy(0, 24):zoom(0.35):diffuse(color("#FF0000")):settext("Chord Cohesion ON"):visible(false) end,
				OnCommand = function(self)
					if not isManiaModeEnabled() and curScore and curScore:GetChordCohesion() then
						self:visible(true):settext("Chord Cohesion ON")
					else
						self:visible(false):settext("")
					end
				end,
				ManiaModeChangedMessageCommand = function(self) self:playcommand("On") end,
				ScoreChangedMessageCommand = function(self) self:playcommand("On") end
			},
			
			-- Hover detection for Tooltip
			Def.ActorFrame {
				OnCommand = function(self)
					self:SetUpdateFunction(function(self)
						local wrapper = self:GetParent()
						local label = wrapper and wrapper:GetChild("WifeScoreLabel")
						if isManiaModeEnabled() then
							MESSAGEMAN:Broadcast("HideScoreTooltip")
							return
						end
						if isOver(label) then
							MESSAGEMAN:Broadcast("ShowScoreTooltip")
						else
							MESSAGEMAN:Broadcast("HideScoreTooltip")
						end
					end)
				end,
				ResetJudgeMessageCommand = function(self)
					self:SetUpdateFunction(nil)
					self:playcommand("On")
				end
			}
		},

		Def.ActorFrame {
			Name = "ManiaODSlider",
			InitCommand = function(self) self:xy(110, 34):visible(false) end,
			ManiaModeChangedMessageCommand = function(self)
				local active = isManiaModeEnabled()
				self:visible(active)
				self:GetChild("Value"):settext(active and string.format("OD %.1f", HV.ManiaState.od) or "")
			end,
			Def.Quad { Name = "Hit", InitCommand = function(self) self:halign(0):x(85):zoomto(100, 22):diffuse(color("0.12,0.12,0.14,0.9")):diffusealpha(0.9) end },
			LoadFont("Common Normal") .. { Name = "Value", InitCommand = function(self) self:halign(0.5):x(135):y(-1):zoom(0.32):diffuse(accentColor) end }
		},

		-- ScoreV2 toggle button (visible only in mania mode)
		Def.ActorFrame {
			Name = "ManiaScoreV2Toggle",
			InitCommand = function(self) self:xy(110, 56):visible(false) end,
			ManiaModeChangedMessageCommand = function(self)
				local active = isManiaModeEnabled()
				self:visible(active)
				if active then self:playcommand("Refresh") end
			end,
			RefreshCommand = function(self)
				local v2 = HV.ManiaState.useScoreV2
				self:GetChild("Bg"):diffuse(v2 and accentColor or color("0.12,0.12,0.14,0.9"))
					:diffusealpha(v2 and 0.35 or 0.9)
				self:GetChild("Label")
					:settext(v2 and "ScoreV2" or "ScoreV1")
					:diffuse(v2 and accentColor or dimText)
			end,
			-- Background pill
			Def.Quad {
				Name = "Bg",
				InitCommand = function(self)
					self:halign(0):x(85):zoomto(100, 18):diffuse(color("0.12,0.12,0.14,0.9")):diffusealpha(0.9)
				end
			},
			LoadFont("Common Normal") .. {
				Name = "Label",
				InitCommand = function(self)
					self:halign(0.5):x(135):y(-1):zoom(0.28):diffuse(dimText):settext("ScoreV1")
				end
			}
		},

		-- Share of chart notes or rows judged on a failed play.
		LoadFont("Common Normal") .. {
			Name = "FailedProgress",
			InitCommand = function(self)
				self:xy(110, 29):halign(0):valign(0):zoom(0.4):diffuse(accentColor):visible(false)
			end,
			BeginCommand = function(self)
				self:playcommand("UpdateResult"):diffusealpha(0):sleep(0.4):linear(0.2):diffusealpha(1)
			end,
			ScoreChangedMessageCommand = function(self) self:playcommand("UpdateResult") end,
			UpdateResultCommand = function(self)
				local failed = evaluationGrade() == "Grade_Failed"
				self:visible(failed):settext(failed and failedProgressText() or "")
			end,
		},
		-- DP (WifeDP)
		Def.ActorFrame {
			Name = "WifeDPDisplay",
			InitCommand = function(self) self:xy(110, 45):diffusealpha(0):visible(not usingCustomWindows) end,
			ManiaModeChangedMessageCommand = function(self)
				self:visible(true)
				self:playcommand("On")
			end,
			OnCommand = function(self)
				if usingCustomWindows then self:visible(false); return end
				self:visible(true)
				local wholePart = self:GetChild("WholeDP")
				local decimalPart = self:GetChild("DecimalDP")
				local displayPct = displayedWifePercent()
				local targetDP = isManiaModeEnabled() and getOsuManiaLongScore() or evaluationWifePoints()
				if not targetDP then
					self:SetUpdateFunction(nil)
					wholePart:settext("-")
					decimalPart:settext("")
					self:stoptweening():sleep(0.4):linear(0.15):diffusealpha(1)
					return
				end
				
				local duration = 0.2
				local curTime = 0

				self:stoptweening():sleep(0.4):linear(0.15):diffusealpha(1)
				
				self:SetUpdateFunction(function(self, delta)
					curTime = curTime + delta
					local progress = math.min(1, curTime / duration)
					local currentDP = targetDP * math.sin(progress * (math.pi / 2))
					if isManiaModeEnabled() then wholePart:settext(formatOsuManiaLongScore(currentDP + 0.5)); decimalPart:settext("")
					else setDPTextActors(wholePart, decimalPart, currentDP, (displayPct >= 99) and 4 or 2) end
					
					if progress >= 1 then
						self:SetUpdateFunction(nil)
					end
				end)
			end,
			SetJudgeCommand = function(self)
				self:playcommand("On")
			end,
			CustomWindowStateChangedMessageCommand = function(self) self:playcommand("On") end,
			LoadedCustomWindowMessageCommand = function(self) self:playcommand("On") end,
			UnloadedCustomWindowMessageCommand = function(self) self:playcommand("On") end,
			ResetJudgeMessageCommand = function(self) 
				self:SetUpdateFunction(nil)
				self:playcommand("On") 
			end,
			
			-- Whole part
			LoadFont("Common Normal") .. {
				Name = "WholeDP",
				InitCommand = function(self) self:halign(0):valign(1):xy(0, 5):zoom(0.8):diffuse(accentColor) end,
			},
			-- Decimal part
			LoadFont("Common Normal") .. {
				Name = "DecimalDP",
				InitCommand = function(self) self:halign(0):valign(1):xy(0, 5):zoom(0.35):diffuse(accentColor) end,
				OnCommand = function(self)
					-- Handled by WholeDP UpdateFunction
				end,
				SetJudgeCommand = function(self)
					-- Handled by WholeDP SetJudgeCommand
				end,
				ResetJudgeMessageCommand = function(self) self:playcommand("On") end
			},
		},
		-- DP slash (Total Score)
		LoadFont("Common Normal") .. {
			Name = "DPTotal",
			InitCommand = function(self) self:halign(0):valign(0):xy(110, 52):zoom(0.35):diffuse(subText) end,
			OnCommand = function(self)
				local _, possible = evaluationWifePoints()
				self:visible(possible ~= nil and not isManiaModeEnabled())
				if possible then self:settextf("/ %.2f", possible) end
			end,
			SetJudgeCommand = function(self) self:playcommand("On") end,
			ManiaModeChangedMessageCommand = function(self) self:playcommand("On") end,
			CustomWindowStateChangedMessageCommand = function(self) self:playcommand("On") end,
		},
		-- MF (Manip Factor)
		LoadActor("manipfactor", curScore, steps) .. {
			InitCommand = function(self) self:xy(280, 10) end
		},

		-- Clear Type Display Area
		Def.ActorFrame {
			Name = "ClearTypeDisplay",
			InitCommand = function(self) self:xy(280, 38):diffusealpha(0) end,
			ManiaModeChangedMessageCommand = function(self) self:visible(not isManiaModeEnabled()) end,
			OnCommand = function(self)
				self:stoptweening():sleep(0.55):linear(0.2):diffusealpha(1)
			end,

			-- Current Clear Type
			LoadFont("Common Normal") .. {
				InitCommand = function(self) self:halign(0):valign(0):zoom(0.5) end,
				OnCommand = function(self) self:playcommand("SetJudge") end,
				SetJudgeCommand = function(self)
					local currentCT = clearType
					if judge ~= playedJudge then
						currentCT = rescore.counts and getDetailedClearType(curScore or pss, rescore.counts)
					end
					self:settext(currentCT and getClearTypeText(currentCT) or "-")
						:diffuse(currentCT and getClearTypeColor(currentCT) or dimText)
				end
			},
		},
	}
	return board
end

local function addScoreBoardStats(board, pn, frameW, pad)
	local statsStartY = pad + 230
	local col1X = pad
	local col2X = (frameW / 2) + 5
	local rowH = 18
	
	-- Separator
	board[#board + 1] = Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(pad, statsStartY):zoomto(frameW - pad*2, 1):diffuse(dividerColor)
		end
	}

	-- Judgment Tally Frame (Column 1)
	local tallyFrame = Def.ActorFrame {
		Name = "JudgmentTally",
		InitCommand = function(self) self:diffusealpha(0) end,
		OnCommand = function(self)
			self:stoptweening():sleep(0.6):linear(0.3):diffusealpha(1)
			
			-- Handle hover logic via direct update function to avoid command overhead
			self:SetUpdateFunction(function(self)
				if usingCustomWindows or isManiaModeEnabled() then
					if showRATally then 
						showRATally = false 
						self:playcommand("RATallyChanged") 
					end
					return
				end
				local over = isOver(self:GetChild("HoverArea"))
				if over ~= showRATally then
					showRATally = over
					self:playcommand("RATallyChanged")
				end
			end)
		end,

		Def.Quad {
			Name = "HoverArea",
			InitCommand = function(self)
				self:halign(0):valign(0):xy(col1X, statsStartY + 20):zoomto(col2X - pad - 5, rowH * #judges + 4):diffusealpha(0)
			end,
		},

		LoadFont("Common Normal") .. {
			InitCommand = function(self) self:halign(0):valign(0):xy(col1X, statsStartY + 8):zoom(0.45):diffuse(subText)
							:settext(THEME:GetString("ScreenEvaluation", "CategoryJudgment"))
					end,
		}
	}
	board[#board + 1] = tallyFrame

	local raLabels = {"Ludicrous", "Ridiculous", "Marvelous", "Perfect", "Great", "Miss"}
	local raColors = {
		color("#FF69B4"), color("#FFD700"), 
		HVColor.GetJudgmentColor("W1"), HVColor.GetJudgmentColor("W2"), HVColor.GetJudgmentColor("W3"), HVColor.GetJudgmentColor("Miss")
	}
	
	for k, v in ipairs(judges) do
		local jy = statsStartY + 28 + (k - 1) * rowH
		local rowColor = judgmentColors[k]

		-- Backdrop
		tallyFrame[#tallyFrame + 1] = Def.Quad {
			InitCommand = function(self)
				self:halign(0):xy(col1X - 2, jy):zoomto(0, rowH - 2):diffuse(rowColor):diffusealpha(0.2)
			end,
			ManiaModeChangedMessageCommand = function(self)
				self:playcommand("SetJudge")
			end,
			OnCommand = function(self)
				local pct = displayedJudgmentFraction(v, k) or 0
				self:zoomto((col2X - pad - col1X) * pct, rowH - 2)
			end,
			SetJudgeCommand = function(self)
				local pct = displayedJudgmentFraction(v, k) or 0
				self:finishtweening():linear(0.2):zoomto((col2X - pad - col1X) * pct, rowH - 2)
			end,
			LoadedCustomWindowMessageCommand = function(self) self:playcommand("SetJudge") end,
			UnloadedCustomWindowMessageCommand = function(self) self:playcommand("SetJudge") end,
			CustomWindowStateChangedMessageCommand = function(self) self:playcommand("SetJudge") end,
			RATallyChangedCommand = function(self)
				local pct
				if showRATally then
					pct = judgmentFraction(getRATallyCount(k), totalTaps)
				else
					pct = displayedJudgmentFraction(v, k)
				end
				self:diffuse(showRATally and raColors[k] or rowColor):diffusealpha(0.2)
				pct = pct or 0
				self:finishtweening():linear(0.2):zoomto((col2X - pad - col1X) * pct, rowH - 2)
			end,
			ResetJudgeMessageCommand = function(self) self:playcommand("On") end
		}
		-- Label
		tallyFrame[#tallyFrame + 1] = LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:halign(0):xy(col1X, jy):zoom(0.45):diffuse(rowColor)
					self:settext(getEvaluationJudgeLabel(v, k))
			end,
			ManiaModeChangedMessageCommand = function(self) self:settext(getEvaluationJudgeLabel(v, k)):diffuse(rowColor) end,
			RATallyChangedCommand = function(self)
				if showRATally then
					self:settext(raLabels[k]):diffuse(raColors[k])
				elseif usingCustomWindows then
					if getCustomWindowConfigJudgmentName then self:settext(getCustomWindowConfigJudgmentName(v)) end
					self:diffuse(rowColor)
				elseif maniaRescore then
					self:settext(getEvaluationJudgeLabel(v, k)):diffuse(rowColor)
				else
					self:settext(getJudgeStrings(v)):diffuse(rowColor)
				end
			end,
			LoadedCustomWindowMessageCommand = function(self)
				if getCustomWindowConfigJudgmentName then self:settext(getCustomWindowConfigJudgmentName(v)) end
			end,
			UnloadedCustomWindowMessageCommand = function(self) self:settext(getJudgeStrings(v)) end
		}
		-- Count
		tallyFrame[#tallyFrame + 1] = LoadFont("Common Normal") .. {
			InitCommand = function(self) self:halign(1):xy(col2X - pad - 40, jy):zoom(0.55):diffuse(brightText) end,
			ManiaModeChangedMessageCommand = function(self)
				self:playcommand("SetJudge")
			end,
			OnCommand = function(self) self:settext(getDisplayedJudgeCount(v, k) or "-") end,
			SetJudgeCommand = function(self) 
				local count = getDisplayedJudgeCount(v, k)
				self:settext(count or "-")
			end,
			CustomWindowStateChangedMessageCommand = function(self) self:playcommand("SetJudge") end,
			RATallyChangedCommand = function(self)
				if showRATally then
					self:settext(getRATallyCount(k))
				else
					self:playcommand("SetJudge")
				end
			end,
			LoadedCustomWindowMessageCommand = function(self)
				if lastSnapshot then
					local jName = v:gsub("TapNoteScore_", "")
					self:settext(lastSnapshot.counts[jName] or 0)
				end
			end,
			ResetJudgeMessageCommand = function(self) self:playcommand("On") end
		}
		-- Percentage
		tallyFrame[#tallyFrame + 1] = LoadFont("Common Normal") .. {
			InitCommand = function(self) self:halign(1):xy(col2X - pad - 5, jy):zoom(0.35):diffuse(dimText) end,
			ManiaModeChangedMessageCommand = function(self)
				self:playcommand("SetJudge")
			end,
			OnCommand = function(self)
				self:playcommand("SetJudge")
			end,
			SetJudgeCommand = function(self)
				local pct = displayedJudgmentFraction(v, k)
				self:settext(pct and string.format("%.1f%%", pct * 100) or "-")
			end,
			LoadedCustomWindowMessageCommand = function(self) self:playcommand("SetJudge") end,
			UnloadedCustomWindowMessageCommand = function(self) self:playcommand("SetJudge") end,
			CustomWindowStateChangedMessageCommand = function(self) self:playcommand("SetJudge") end,
			RATallyChangedCommand = function(self)
				if showRATally then
					local pct = judgmentFraction(getRATallyCount(k), totalTaps)
					self:settext(pct and string.format("%.1f%%", pct * 100) or "")
				else
					self:playcommand("SetJudge")
				end
			end,
			ResetJudgeMessageCommand = function(self) self:playcommand("On") end
		}
	end

	-- Ratios (Bottom Column 1 - 2x2 Grid)
	local ratioStartY = statsStartY + 28 + (#judges * rowH) + 12
	local ratioLabels = {"LA", "RA", "MA", "PA"}
	local ratioColors = {color("#FF69B4"), color("#FFD700"), color("#FFFFFF"), color("#E0E0A0")}
	local function getManiaRatioText(index)
		if not maniaRescore then return nil end
		local a = maniaRescore.counts[index] or 0
		local b = maniaRescore.counts[index + 1] or 0
		if b == 0 then return a > 0 and "-" or "-" end
		return string.format("%.2f:1", a / b)
	end
	for ri, rlabel in ipairs(ratioLabels) do
		local col = (ri - 1) % 2
		local row = math.floor((ri - 1) / 2)
		local rx = col1X + col * 75
		if col == 1 then rx = rx + 35 end
		local ry = ratioStartY + row * 26
		
		board[#board + 1] = LoadFont("Common Normal") .. {
			InitCommand = function(self) self:halign(col == 1 and 1 or 0):xy(col == 1 and rx + 20 or rx, ry):zoom(0.48):diffuse(ratioColors[ri]):settext(rlabel .. ":"):diffusealpha(0):visible(ri > 2) end,
			OnCommand = function(self)
				self:visible(ri > 2 or not usingCustomWindows)
				self:stoptweening():sleep(0.65 + ri * 0.05):linear(0.2):diffusealpha(1)
			end,
			ManiaModeChangedMessageCommand = function(self) self:visible(ri > 2 or not isManiaModeEnabled()) end,
			CustomWindowStateChangedMessageCommand = function(self) self:visible(ri > 2 or not usingCustomWindows) end,
			LoadedCustomWindowMessageCommand = function(self) self:visible(ri > 2) end,
			UnloadedCustomWindowMessageCommand = function(self) self:visible(ri > 2) end
		}
		board[#board + 1] = LoadFont("Common Normal") .. {
			InitCommand = function(self) self:halign(col == 1 and 1 or 0):xy(col == 1 and rx + 75 or rx + 40, ry):zoom(0.5):diffuse(mainText):diffusealpha(0):visible(true) end,
			ManiaModeChangedMessageCommand = function(self)
				self:visible(ri > 2 or not isManiaModeEnabled())
				self:playcommand("SetJudge")
			end,
			CustomWindowStateChangedMessageCommand = function(self)
				self:visible(ri > 2 or not usingCustomWindows)
				self:playcommand("SetJudge")
			end,
			LoadedCustomWindowMessageCommand = function(self) self:visible(ri > 2); self:playcommand("SetJudge") end,
			UnloadedCustomWindowMessageCommand = function(self) self:visible(ri > 2); self:playcommand("SetJudge") end,
			OnCommand = function(self)
				if maniaRescore then
					self:settext(getManiaRatioText(ri)):diffuse(ratioColors[ri])
				elseif ri == 1 then
					local ra, la, ridic, marvRA, ludic, ridicLA = getRatios()
					if ridicLA == 0 then self:settext(ludic > 0 and "No Ridics" or "-"):diffuse(ludic > 0 and color("#FFFFFF") or dimText)
					else self:settextf("%.2f:1", la):rainbow() end
				elseif ri == 2 then
					local ra, la, ridic, marvRA, ludic, ridicLA = getRatios()
					if marvRA == 0 then self:settext(ridic > 0 and "No Marvs" or "-"):diffuse(ridic > 0 and ratioColors[2] or dimText)
					else self:settextf("%.2f:1", ra):diffuse(ratioColors[2]) end
				elseif ri == 3 then
					local w1 = evaluationTapCount("TapNoteScore_W1")
					local w2 = evaluationTapCount("TapNoteScore_W2")
					if w2 == 0 then self:settext(w1 > 0 and "-" or "-"):diffuse(w1 > 0 and color("#FFFFFF") or dimText)
					else self:settextf("%.2f:1", w1 / w2):diffuse(ratioColors[3]) end
				elseif ri == 4 then
					local w3 = evaluationTapCount("TapNoteScore_W3")
					if w3 == 0 then self:settext(evaluationTapCount("TapNoteScore_W2") > 0 and "-" or "-"):diffuse(dimText)
					else self:settextf("%.2f:1", evaluationTapCount("TapNoteScore_W2") / w3):diffuse(ratioColors[4]) end
				end
				self:sleep(0.7 + ri * 0.05):linear(0.2):diffusealpha(1)
			end,
			SetJudgeCommand = function(self)
				self:stoptweening()
				if maniaRescore then
					self:settext(getManiaRatioText(ri)):diffuse(ratioColors[ri])
				elseif ri == 3 or ri == 4 then
					local counts = rescore.counts
					if judge == playedJudge then
						counts = {
							W1 = evaluationTapCount("TapNoteScore_W1"),
							W2 = evaluationTapCount("TapNoteScore_W2"),
							W3 = evaluationTapCount("TapNoteScore_W3"),
						}
					end
					local numerator = counts and (ri == 3 and counts.W1 or counts.W2)
					local denominator = counts and (ri == 3 and counts.W2 or counts.W3)
					self:settext(denominator and denominator > 0 and string.format("%.2f:1", numerator / denominator) or "-")
				else
					self:playcommand("On")
				end
			end,
			ResetJudgeMessageCommand = function(self) self:playcommand("On") end
		}
	end

	-- Column 2: Holds / Mines
	board[#board + 1] = LoadFont("Common Normal") .. {
		InitCommand = function(self) self:halign(0):valign(0):xy(col2X, statsStartY + 8):zoom(0.45):diffuse(subText):settext("Holds & Stats"):diffusealpha(0) end,
		OnCommand = function(self)
			self:stoptweening():sleep(0.6):linear(0.2):diffusealpha(1)
		end
	}
	local holdStats = {
		{"Hold OK", function() return evaluationHoldCount("HoldNoteScore_Held") end},
		{"Hold NG", function()
			return evaluationHoldCount("HoldNoteScore_LetGo") + evaluationHoldCount("HoldNoteScore_MissedHold")
		end},
		{"Mines Hit", function() return evaluationTapCount("TapNoteScore_HitMine") end},
	}
	for i, stat in ipairs(holdStats) do
		local label, getCount = stat[1], stat[2]
		local hy = statsStartY + 28 + (i - 1) * rowH
		board[#board + 1] = LoadFont("Common Normal") .. {
			InitCommand = function(self) self:halign(0):xy(col2X, hy):zoom(0.42):diffuse(subText):settext(label .. ":"):diffusealpha(0) end,
			OnCommand = function(self)
				self:stoptweening():sleep(0.65 + i * 0.05):linear(0.2):diffusealpha(1)
			end
		}
		board[#board + 1] = LoadFont("Common Normal") .. {
			Name = label .. "Count",
			InitCommand = function(self) self:halign(1):xy(frameW - pad, hy):zoom(0.45):diffuse(mainText):diffusealpha(0) end,
			BeginCommand = function(self)
				self:playcommand("UpdateResult"):sleep(0.65 + i * 0.05):linear(0.2):diffusealpha(1)
			end,
			ScoreChangedMessageCommand = function(self) self:playcommand("UpdateResult") end,
			UpdateResultCommand = function(self) self:settext(getCount()) end,
		}
	end

	-- Column 2: Timing Stats
	local timingStartY = statsStartY + 28 + (3 * rowH)
	local tStatLabels = {"Mean", "Std Dev", "Largest"}
	for i, label in ipairs(tStatLabels) do
		local ty = timingStartY + (i - 1) * rowH
		board[#board + 1] = LoadFont("Common Normal") .. {
			InitCommand = function(self) self:halign(0):xy(col2X, ty):zoom(0.42):diffuse(subText):settext(label .. ":"):diffusealpha(0) end,
			OnCommand = function(self)
				self:stoptweening():sleep(0.75 + i * 0.05):linear(0.2):diffusealpha(1)
			end
		}
		board[#board + 1] = LoadFont("Common Normal") .. {
			InitCommand = function(self) self:halign(1):xy(frameW - pad, ty):zoom(0.45):diffuse(mainText):diffusealpha(0) end,
			OnCommand = function(self)
				self:playcommand("UpdateText")
				self:stoptweening():sleep(0.75 + i * 0.05):linear(0.2):diffusealpha(1)
			end,
			SetJudgeCommand = function(self) self:playcommand("UpdateText") end,
			UpdateTextCommand = function(self)
				local value = offsetStats[i]
				self:settext(value and string.format("%.2fms", value) or "-")
			end
		}
	end

	-- Column 2: Note Types
	local ntStartY = statsStartY + 20 + (7 * rowH)
	-- The native Mines radar counts avoided mines.
	local noteTypeLabels = {"Holds", "Rolls", "Lifts", "Mines"}
	for ni, nlabel in ipairs(noteTypeLabels) do
		local radar = noteTypeRadars[ni]
		local ny = ntStartY + (ni - 1) * 16
		board[#board + 1] = LoadFont("Common Normal") .. {
			InitCommand = function(self) self:halign(0):xy(col2X, ny - 7):zoom(0.4):diffuse(subText):settext(nlabel .. ":"):diffusealpha(0) end,
			BeginCommand = function(self)
				self:sleep(0.8 + ni * 0.03):linear(0.15):diffusealpha(1)
			end
		}
		board[#board + 1] = LoadFont("Common Normal") .. {
			Name = nlabel .. "Radar",
			InitCommand = function(self) self:halign(1):xy(frameW - pad, ny -7):zoom(0.43):diffuse(mainText):diffusealpha(0) end,
			BeginCommand = function(self)
				self:playcommand("UpdateResult"):sleep(0.8 + ni * 0.03):linear(0.15):diffusealpha(1)
			end,
			ScoreChangedMessageCommand = function(self) self:playcommand("UpdateResult") end,
			UpdateResultCommand = function(self)
				local stage = openingStageRadar()
				local actual = curScore and curScore:GetRadarValues():GetValue(radar) or -1
				if actual < 0 and stage then actual = stage.actual[radar] end
				local possible = stage and stage.possible[radar] or steps:GetRadarValues(pn):GetValue(radar)
				self:settextf("%s/%s", actual >= 0 and actual or "-", possible >= math.max(0, actual) and possible or "-")
			end,
		}
	end
end

do
	local frameW = SCREEN_CENTER_X - 20
	local pad = 12
	local board = createScoreBoard(PLAYER_1, frameW, pad)
	addScoreBoardStats(board, PLAYER_1, frameW, pad)
	t[#t + 1] = board
end

------------------------------------------------------------
-- RIGHT PANEL: OFFSET PLOT + SCOREBOARD
------------------------------------------------------------
local rightX = SCREEN_CENTER_X + 10
local rightW = SCREEN_CENTER_X - 20
local offsetPlotHeight = 160

t[#t + 1] = Def.ActorFrame {
	Name = "RightPanel",
	InitCommand = function(self) self:x(rightX + 50):diffusealpha(0) end,
	OnCommand = function(self)
		self:sleep(0.25):linear(0.4):x(rightX):diffusealpha(1)
		SCREENMAN:GetTopScreen():AddInputCallback(function(event)
			if event.DeviceInput and event.type == "InputEventType_FirstPress" then
				if event.DeviceInput.button == "DeviceButton_backspace" then
					local wasEnabled = HV.ManiaState and HV.ManiaState.enabled
					HV.ToggleManiaMode()
					if not wasEnabled and usingCustomWindows then
						usingCustomWindows = false
						unloadCustomWindowConfig()
						lastSnapshot = nil
						MESSAGEMAN:Broadcast("UnloadedCustomWindow")
					end
					if refreshEvaluationDisplays then refreshEvaluationDisplays() end
					return true
				end
				if HV.ManiaState and HV.ManiaState.enabled and event.DeviceInput.button == "DeviceButton_left mouse button" then
					local mx, my = INPUTFILTER:GetMouseX(), INPUTFILTER:GetMouseY()
					local odFieldX, odFieldY = 207, 201
					if mx >= odFieldX and mx <= odFieldX + 110 and my >= odFieldY - 14 and my <= odFieldY + 14 then
						editManiaOD()
						return true
					end
					-- ScoreV2 toggle button: same X band, 22px lower than OD (at y ~223)
					local v2FieldY = odFieldY + 22
					if mx >= odFieldX and mx <= odFieldX + 110 and my >= v2FieldY - 11 and my <= v2FieldY + 11 then
						HV.ToggleManiaScoreV2()
						if refreshEvaluationDisplays then refreshEvaluationDisplays() end
						return true
					end
				end
			end
			if event.type == "InputEventType_FirstPress" then
				local btn = event.DeviceInput and event.DeviceInput.button
				local up = btn == "DeviceButton_up" or event.button == "MenuUp" or event.button == "Up"
				local down = btn == "DeviceButton_down" or event.button == "MenuDown" or event.button == "Down"
				if up or down then
					MESSAGEMAN:Broadcast("OffsetPlotModification", {Name = "ToggleHands", Direction = up and -1 or 1})
					return true
				end

				-- Judge cycling
				if event.button == "EffectUp" then
					if isManiaModeEnabled() then
						HV.SetManiaOD(HV.ManiaState.od + 1)
						if refreshEvaluationDisplays then refreshEvaluationDisplays() end
					elseif usingCustomWindows then
						MESSAGEMAN:Broadcast("MoveCustomWindowIndex", {direction = 1})
					else
						MESSAGEMAN:Broadcast("OffsetPlotModification", {Name = "NextJudge"})
					end
				elseif event.button == "EffectDown" then
					if isManiaModeEnabled() then
						HV.SetManiaOD(HV.ManiaState.od - 1)
						if refreshEvaluationDisplays then refreshEvaluationDisplays() end
					elseif usingCustomWindows then
						MESSAGEMAN:Broadcast("MoveCustomWindowIndex", {direction = -1})
					else
						MESSAGEMAN:Broadcast("OffsetPlotModification", {Name = "PrevJudge"})
					end
				elseif event.button == "Coin" then
					MESSAGEMAN:Broadcast("OffsetPlotModification", {Name = "Coin"})
				end
			end
		end)
	end,
	-- BG
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(0, 10):zoomto(rightW, SCREEN_HEIGHT - 20):diffuse(bgCard)
		end
	},

	-- ============================================================
	-- OFFSET PLOT
	-- ============================================================
	Def.ActorFrame {
		Name = "OffsetPlotWrapper",
		InitCommand = function(self) self:xy(0, 50) end,

		LoadActor(THEME:GetPathG("", "OffsetGraph")) .. {
			InitCommand = function(self)
				self:xy(10, 20)
			end,
			OnCommand = function(self) self:playcommand("SetJudge") end,
			SetJudgeCommand = function(self)
				self:RunCommandsOnChildren(function(child)
					child:playcommand("Update", {
						width = rightW - 20,
						height = 100,
						song = song,
						steps = steps,
						judge = judge,
						scoreKey = curScore and curScore:GetScoreKey() or "",
						nrv = nrv,
						dvt = dvt,
						ctt = ctt,
						ntt = ntt,
						misses = plotMisses,
						rate = curScore and curScore:GetMusicRate() or getCurRateValue(),
						customWindows = usingCustomWindows,
						mania = isManiaModeEnabled(),
						chordCohesion = curScore and curScore.GetChordCohesion and curScore:GetChordCohesion() or false,
						columns = steps and steps:GetNumColumns() or 4,
					})
				end)
			end,
			EvaluationJudgeChangedMessageCommand = function(self) self:playcommand("SetJudge") end,
			ScoreChangedMessageCommand = function(self) self:playcommand("SetJudge") end,
			ManiaModeChangedMessageCommand = function(self) self:playcommand("SetJudge") end,
			LoadedCustomWindowMessageCommand = function(self) self:playcommand("SetJudge") end,
			UnloadedCustomWindowMessageCommand = function(self) self:playcommand("SetJudge") end,
		},
		-- Offset Plot Label
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:xy(10, -10):zoom(0.55):halign(0):diffuse(subText)
				self:settext(THEME:GetString("ScreenEvaluation", "CategoryOffset"))
			end,
		},
	},
}

-- ============================================================
-- SCOREBOARD (loaded from external files)
-- ============================================================
local scoreboardFrame = Def.ActorFrame {
	Name = "ScoreboardContainer",
	InitCommand = function(self) self:xy(rightX + 10, offsetPlotHeight + 110) end,
}

if inMulti then
	scoreboardFrame[#scoreboardFrame + 1] = LoadActor("MPscoreboard")
else
	scoreboardFrame[#scoreboardFrame + 1] = LoadActor("online_leaderboard", selectEvaluationScore, openingScore)
end

t[#t + 1] = scoreboardFrame
t[#t + 1] = LoadActor("../_cursor")

t[#t + 1] = Def.ActorFrame {
	Name = "GlobalScoreTooltip",
	InitCommand = function(self) self:diffusealpha(0):z(100) end,
	ShowScoreTooltipMessageCommand = function(self)
		if isManiaModeEnabled() then self:diffusealpha(0); return end
		self:diffusealpha(1)
		self:playcommand("UpdateScores")
		local mx = INPUTFILTER:GetMouseX()
		local my = INPUTFILTER:GetMouseY()
		
		local bg = self:GetChild("BG")
		local w = bg and bg:GetZoomedWidth() or 260
		local h = bg and bg:GetZoomedHeight() or 120
		local cx = mx + 15
		local cy = my + 15
		if cx + w > SCREEN_WIDTH then cx = mx - w - 5 end
		if cy + h > SCREEN_HEIGHT then cy = my - h - 5 end
		
		self:xy(cx, cy)
	end,
	HideScoreTooltipMessageCommand = function(self) self:diffusealpha(0) end,
	SetJudgeMessageCommand = function(self) self:playcommand("UpdateScores") end,
	ScoreChangedMessageCommand = function(self) self:playcommand("UpdateScores") end,
	UpdateScoresCommand = function(self)
		if self:GetDiffuseAlpha() == 0 then return end
		local rst = rescore.data
		
		local numCustoms = customWindowsConfig and #customWindowsConfig:get_data().customWindowOrder or 0
		local rows = math.max(6, numCustoms)
		local bg = self:GetChild("BG")
		if bg then
			bg:zoomto(260, rows * 16 + 12)
		end
		
		self:RunCommandsOnChildren(function(child)
			child:playcommand("UpdateData", {rst = rst})
		end)
	end,
	Def.Quad {
		Name = "Border",
		InitCommand = function(self) self:halign(0):valign(0):diffuse(color("0.3,0.3,0.3,1")):diffusealpha(0.8) end,
		UpdateDataCommand = function(self)
			local bg = self:GetParent():GetChild("BG")
			if bg then self:zoomto(bg:GetZoomedWidth()+2, bg:GetZoomedHeight()+2):xy(-1, -1) end
		end
	},
	Def.Quad {
		Name = "BG",
		InitCommand = function(self) self:halign(0):valign(0):diffuse(color("0.05,0.05,0.05,0.95")) end
	},
	(function()
		local col = Def.ActorFrame { Name = "LeftCol", InitCommand = function(self) self:xy(8, 8) end }
		for i = 4, 9 do
			local yOff = (i - 4) * 16
			col[#col+1] = LoadFont("Common Normal") .. {
				InitCommand = function(self) self:halign(0):valign(0):xy(0, yOff):zoom(0.35):settext("J"..i..":") end
			}
			col[#col+1] = LoadFont("Common Normal") .. {
				InitCommand = function(self) self:halign(1):valign(0):xy(100, yOff):zoom(0.35) end,
				UpdateDataCommand = function(self)
					local pct = wifePercentAtJudge(i)
					self:settext(pct and formatWifePercent(pct) or "-")
				end
			}
		end
		return col
	end)(),
	(function()
		local col = Def.ActorFrame { Name = "RightCol", InitCommand = function(self) self:xy(120, 8) end }
		for i = 1, 15 do
			local yOff = (i - 1) * 16
			col[#col+1] = LoadFont("Common Normal") .. {
				InitCommand = function(self) self:halign(0):valign(0):xy(0, yOff):zoom(0.35) end,
				UpdateDataCommand = function(self, params)
					if not customWindowsConfig then self:settext(""); return end
					local order = customWindowsConfig:get_data().customWindowOrder
					local configName = order[i]
					if not configName then self:settext(""); return end
					local conf = customWindowsConfig:get_data().customWindowConfigs[configName]
					local dispName = conf and conf.displayName or configName
					if dispName:len() > 16 then dispName = dispName:sub(1,15).."." end
					self:settext(dispName..":")
				end
			}
			col[#col+1] = LoadFont("Common Normal") .. {
				InitCommand = function(self) self:halign(1):valign(0):xy(130, yOff):zoom(0.35) end,
				UpdateDataCommand = function(self, params)
					if not customWindowsConfig then self:settext(""); return end
					local order = customWindowsConfig:get_data().customWindowOrder
					local configName = order[i]
					if not configName then self:settext(""); return end
					local pct = params.rst and calculateCustomWindowScore(configName, params.rst)
					self:settext(pct and formatWifePercent(pct) or "-")
				end
			}
		end
		return col
	end)()
}



return t
