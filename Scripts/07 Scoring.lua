HV.Judgment = HV.Judgment or {}
HV.Score = HV.Score or {}

local tapWindows = {22.5, 45, 90, 135}
local tapKeys = {"W1", "W2", "W3", "W4"}

function HV.Judgment.GetWindows(scale, includeRidiculous)
	scale = math.max(0.001, math.min(tonumber(scale) or 1, 1))
	local windows = { W5 = 180 }
	for i, key in ipairs(tapKeys) do
		local seconds = PREFSMAN:GetPreference("TimingWindowSeconds" .. key)
		local milliseconds = type(seconds) == "number" and seconds * 1000 or tapWindows[i]
		windows[key] = math.max(0, math.min(milliseconds * scale, 180))
	end
	if includeRidiculous then windows.Ridiculous = 11.25 * scale end
	return windows
end

function HV.Judgment.ClassifyOffset(offsetMs, windows)
	local offset = math.abs(offsetMs)
	if windows.Ridiculous and offset <= windows.Ridiculous then return "Ridiculous" end
	for _, key in ipairs(tapKeys) do
		if offset <= windows[key] then return key end
	end
	if offset <= windows.W5 then return "W5" end
	return "Miss"
end

function HV.Score.GetLiveWifePercent(message, player)
	-- Replay resume broadcasts a snapshot with the raw player index.
	local replaySnapshot = message.FromReplay == true
	local matchesPlayer = message.Player == player or (replaySnapshot and message.Player == 0 and player == PLAYER_1)
	if not matchesPlayer or type(message.MaxWifeScore) ~= "number" then return end

	-- The engine sends judgments for these controllers without recording a live score.
	local state = GAMESTATE:GetPlayerState(player)
	local controller = state and state:GetPlayerController()
	if controller == "PlayerController_Autoplay" or controller == "PlayerController_Cpu" then return end

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

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
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
	if not score or chartMaximum <= 0 or PREFSMAN:GetPreference("SortBySSRNormPercent") then return end
	local earned = score:GetWifePoints()
	local fraction = score:GetWifeScore()
	if not finite(earned) or earned == 0 or not finite(fraction) then return end
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
