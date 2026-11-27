HV.Judgment = HV.Judgment or {}
HV.Score = HV.Score or {}

local tapWindows = {22.5, 45, 90, 135}
local tapKeys = {"W1", "W2", "W3", "W4"}

function HV.Judgment.GetWindows(scale)
	scale = math.max(0.001, math.min(tonumber(scale) or 1, 1))
	local windows = { W5 = 180 }
	for i, key in ipairs(tapKeys) do
		local seconds = PREFSMAN:GetPreference("TimingWindowSeconds" .. key)
		local milliseconds = type(seconds) == "number" and seconds * 1000 or tapWindows[i]
		windows[key] = math.max(0, math.min(milliseconds * scale, 180))
	end
	return windows
end

function HV.Judgment.ClassifyOffset(offsetMs, windows)
	local offset = math.abs(offsetMs)
	for _, key in ipairs(tapKeys) do
		if offset <= windows[key] then return key end
	end
	if offset <= windows.W5 then return "W5" end
	return "Miss"
end

function HV.Score.IsAutoplayController(controller)
	return controller == "PlayerController_Autoplay" or controller == "PlayerController_Cpu"
end

function HV.Score.GetLiveWifePercent(message, player)
	-- Replay resume broadcasts a snapshot with the raw player index.
	local replaySnapshot = message.FromReplay == true
	local matchesPlayer = message.Player == player or (replaySnapshot and message.Player == 0 and player == PLAYER_1)
	if not matchesPlayer or type(message.MaxWifeScore) ~= "number" then return end

	-- The engine sends judgments for these controllers without recording a live score.
	local state = GAMESTATE:GetPlayerState(player)
	local controller = state and state:GetPlayerController()
	if HV.Score.IsAutoplayController(controller) then return end

	local percent = message.WifePercent
	if type(percent) ~= "number" or percent ~= percent or math.abs(percent) == math.huge then return end
	if message.MaxWifeScore > 0 or (replaySnapshot and message.MaxWifeScore == 0 and percent == 0) then
		return percent
	end
end

function HV.Score.GetEvaluationOpeningScore(steps, stageStats, replayPlayback)
	if not steps then return nil end
	local chartKey = steps:GetChartKey()
	if replayPlayback then
		local replay = REPLAYS:GetActiveReplay()
		if not replay or replay:GetChartKey() ~= chartKey then return nil end
		local replayKey = replay:GetScoreKey()
		if replayKey == "" then return nil end
		local score
		if replay:IsForOnlineScore() then
			score = SCOREMAN:GetTempReplayScore()
		else
			score = SCOREMAN:GetMostRecentScore()
		end
		if score and score:GetScoreKey() == replayKey and score:GetChartKey() == chartKey then return score end
		return nil
	end
	local score = stageStats and stageStats:GetHighScore()
	if score and score:GetChartKey() == chartKey then return score end
end

function HV.Score.OpenLocalEvaluation(screen, score)
	if not screen or screen ~= SCREENMAN:GetTopScreen() or screen:IsTransitioning()
		or not screen.ShowEvalScreenForScore or not score then return false end
	local steps = GAMESTATE:GetCurrentSteps()
	if not steps or score:GetScoreKey() == "" or score:GetChartKey() ~= steps:GetChartKey() then return false end

	-- The native call sets autoplay and changes the most recent score before loading the replay.
	local replay = score:HasReplayData() and score:GetReplay()
	local loaded
	if replay then
		-- LoadAllData rejects reprioritized rows after a custom-window rescore.
		if replay:UsingReprioritizedNoteRows() then
			loaded = replay:IsLoaded()
		else
			loaded = replay:LoadAllData()
		end
	end
	if not loaded then
		ms.ok(THEME:GetString("ScreenSelectMusic", "ScoreReplayUnavailable"))
		return false
	end

	local autoplay = PREFSMAN:GetPreference("AutoPlay")
	HV.OnlineReplayActive = false
	HV.OnlineReplayName = nil
	HV.OnlineEvaluationActive = nil
	HV.OnlineEvaluationName = nil
	if screen:ShowEvalScreenForScore(score) then return true end
	-- Etterna reports the failed transition. Restore the option it may have changed before failing.
	PREFSMAN:SetPreference("AutoPlay", autoplay)
	return false
end

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function HV.Score.GetPlayedJudge(score)
	local scale = score and score.GetJudgeScale and score:GetJudgeScale()
	if type(scale) ~= "number" then return end
	for judge = 1, 9 do
		local candidate = ms.JudgeScalers[judge]
		if candidate and math.abs(scale - candidate) < 0.005 then return judge end
	end
end

function HV.Judgment.GetReplayHits(offsets, noteTypes, expectedHits)
	if type(offsets) ~= "table" then return end
	local typed = noteTypes and #noteTypes > 0
	if typed and #noteTypes ~= #offsets then return end
	local hits = {}
	for i, offset in ipairs(offsets) do
		local kind = noteTypes and noteTypes[i]
		local isTap = not typed or kind == "TapNoteType_Tap"
			or kind == "TapNoteType_HoldHead" or kind == "TapNoteType_Lift"
		if isTap and finite(offset) and math.abs(offset) <= 180.001 then
			hits[#hits + 1] = offset
		end
	end
	-- A partial or incompatible replay cannot provide the judgment split.
	if #hits == expectedHits then return hits end
end

function HV.Judgment.RescoreHits(hits, misses, judge)
	local windows = HV.Judgment.GetWindows(ms.JudgeScalers[judge])
	local counts = {W1 = 0, W2 = 0, W3 = 0, W4 = 0, W5 = 0, Miss = misses}
	for _, offset in ipairs(hits) do
		local judgment = HV.Judgment.ClassifyOffset(offset, windows)
		counts[judgment] = counts[judgment] + 1
	end
	return counts
end

function HV.Score.GetChartBestGradeTier(chartKey, chartGrades, checkpoint)
	if chartGrades[chartKey] == nil then
		local best, localBest, played = false, false, false
		for _, rate in pairs(SCOREMAN:GetScoresByKey(chartKey) or {}) do
			if checkpoint then checkpoint() end
			for _, score in ipairs(rate:GetScores()) do
				if checkpoint then checkpoint() end
				played = true
				local tier = tonumber(score:GetWifeGrade():match("^Grade_Tier(%d+)$"))
				if tier and (not best or tier < best) then
					local eligible = not score.GetEtternaValid or score:GetEtternaValid()
					if eligible and not IsScoreInvalid(score) then
						best = tier
					elseif not eligible and not best and (not localBest or tier < localBest) and not IsScoreInvalid(score) then
						localBest = tier
					end
				end
				if best == 1 then break end
			end
			if best == 1 then break end
		end
		chartGrades[chartKey] = {tier = best or localBest, played = played}
	end
	local result = chartGrades[chartKey]
	return result.tier, result.played
end

function HV.Score.FormatEvaluationWifePercent(percent)
	local precision = percent >= 99 and 4 or 2
	local scale = 10 ^ precision
	local rounded = math.floor(percent * scale + 0.5) / scale
	return string.format("%." .. precision .. "f%%", rounded)
end

function HV.Score.BuildEvaluationLeaderboard(scores, currentRate, allRates, online, includeInvalid)
	local result = {}
	for _, score in ipairs(scores) do
		local rate = score:GetMusicRate()
		if rate > 0 and (allRates or math.floor(rate * 10000 + 0.5) == math.floor(currentRate * 10000 + 0.5))
			and (not online or includeInvalid or (score:GetEtternaValid() and not score:GetChordCohesion())) then
			local wife, ssr = score:GetWifeScore(), score:GetSkillsetSSR("Overall")
			if finite(wife) and finite(ssr) then
				result[#result + 1] = {score = score, key = score:GetScoreKey(), wife = wife, ssr = ssr, date = score:GetDate()}
			end
		end
	end
	table.sort(result, function(a, b)
		if allRates and a.ssr ~= b.ssr then return a.ssr > b.ssr end
		if a.wife ~= b.wife then return a.wife > b.wife end
		if a.ssr ~= b.ssr then return a.ssr > b.ssr end
		if a.date ~= b.date then return a.date > b.date end
		return a.key < b.key
	end)
	if not online then return result end
	local filtered, seen = {}, {}
	for _, entry in ipairs(result) do
		local player = entry.score:GetDisplayName():lower()
		if player == "" or not seen[player] then
			filtered[#filtered + 1] = entry
			seen[player] = true
		end
	end
	return filtered
end

function HV.Score.GetEvaluationWifePoints(score, chartMaximum)
	if not score or chartMaximum <= 0 then return end
	if PREFSMAN:GetPreference("SortBySSRNormPercent") and HV.Score.GetPlayedJudge(score) ~= 4 then return end
	local earned = score:GetWifePoints()
	local fraction = score:GetWifeScore()
	if not finite(earned) or not finite(fraction) then return end
	-- The saved points are played-judge points. Verify the chart maximum against the saved fraction.
	if math.abs(earned / chartMaximum - fraction) <= 0.000001 then
		return earned, chartMaximum
	end
end

function HV.Judgment.GetEvaluationOffsetStats(offsets, noteTypes)
	local count, mean, m2, maxAbs = 0, 0, 0, 0
	local typed = noteTypes and #noteTypes == #offsets
	for i, offset in ipairs(offsets) do
		local kind = typed and noteTypes[i]
		if finite(offset) and math.abs(offset) <= 180.001
			and (not typed or kind == "TapNoteType_Tap" or kind == "TapNoteType_HoldHead" or kind == "TapNoteType_Lift") then
			count = count + 1
			local delta = offset - mean
			mean = mean + delta / count
			m2 = m2 + delta * (offset - mean)
			maxAbs = math.max(maxAbs, math.abs(offset))
		end
	end
	if count == 0 then return {} end
	return {mean, count > 1 and math.sqrt(math.max(0, m2 / (count - 1))) or nil, maxAbs}
end
