local gameplay = ...
local showCounter = HV.ShowJudgeCounter()
local statMode = HV.GetNotefieldStat()
if gameplay.isSync or (not showCounter and statMode == "Off") then return end

local fullCounter = showCounter and HV.GetJudgmentTallyMode() ~= "Simple"
local useNativeCounts = showCounter or statMode == "MARatio"
local useRidiculous = showCounter and HV.EmulateRidiculousEnabled()
local useOffsets = fullCounter or statMode == "StdDev" or statMode == "Mean"
local useDelta = statMode == "DeltaHand"
local useLastOffset = statMode == "TapOffset"

local hitScores = {
	TapNoteScore_W1 = true,
	TapNoteScore_W2 = true,
	TapNoteScore_W3 = true,
	TapNoteScore_W4 = true,
	TapNoteScore_W5 = true,
}

local stats
local count, mean, m2, maxOffset
local sums, handCounts
local replayPrefixMissing
local replaySnapshotPending
local refreshPending

local function clearOffsets()
	count, mean, m2, maxOffset = 0, 0, 0, 0
	sums, handCounts = {0, 0, 0}, {0, 0, 0}
	stats.lastOffset = 0
	stats.handScores, stats.handCounts, stats.hasMiddleColumn = {0, 0, 0}, handCounts, false
end

local function reset()
	stats = {
		taps = {W1 = 0, W2 = 0, W3 = 0, W4 = 0, W5 = 0, Miss = 0},
		ridiculous = 0,
		held = 0,
		letGo = 0,
		maRatio = 0,
		paRatio = 0,
		longest = 0,
		mean = 0,
		stdDev = 0,
		largest = 0,
	}
	clearOffsets()
	replayPrefixMissing, replaySnapshotPending, refreshPending = false, false, false
end
reset()

local function publish(self)
	self:GetParent():RunCommandsOnChildren(function(child)
		child:playcommand("SetGameplayStats", stats)
	end)
end

local function resetAndPublish(self)
	reset()
	gameplay.ridiculousCount = 0
	publish(self)
end

local function addHandOffset(message, offset)
	local track = message.FirstTrack or message.Track
	if track == nil then return end

	local style = GAMESTATE:GetCurrentStyle()
	local columns = style and style:ColumnsPerPlayer() or 4
	local middle = (columns - 1) / 2
	local hand = track < middle and 1 or (track == middle and 2 or 3)
	stats.hasMiddleColumn = columns % 2 ~= 0
	local judge = PREFSMAN:GetPreference("SortBySSRNormPercent") and 4 or GetTimingDifficulty()
	local scale = ms.JudgeScalers[judge] or 1
	sums[hand] = sums[hand] + wife3(math.abs(offset), scale, "Wife3")
	handCounts[hand] = handCounts[hand] + 1
end

local function collectOffset(message)
	if message.HoldNoteScore or not hitScores[message.TapNoteScore] then return end
	local offset = message.TapNoteOffset
	if type(offset) ~= "number" or offset ~= offset or math.abs(offset) > 0.180001 then return end

	offset = offset * 1000
	stats.lastOffset = offset
	if useOffsets then
		count = count + 1
		local delta = offset - mean
		mean = mean + delta / count
		m2 = m2 + delta * (offset - mean)
		maxOffset = math.max(maxOffset, math.abs(offset))
	end
	if useDelta and not replayPrefixMissing then addHandOffset(message, offset) end
end

local function ratio(numerator, denominator)
	if denominator > 0 then return numerator / denominator end
	return numerator > 0 and math.huge or 0
end

local function refreshNativeStats()
	local stage = STATSMAN:GetCurStageStats()
	local pss = stage and stage:GetPlayerStageStats()
	if not pss then return end

	stats.taps.W1 = pss:GetTapNoteScores("TapNoteScore_W1")
	stats.taps.W2 = pss:GetTapNoteScores("TapNoteScore_W2")
	stats.maRatio = ratio(stats.taps.W1, stats.taps.W2)
	if not showCounter then return end
	stats.taps.W3 = pss:GetTapNoteScores("TapNoteScore_W3")
	stats.paRatio = ratio(stats.taps.W2, stats.taps.W3)
	stats.taps.W4 = pss:GetTapNoteScores("TapNoteScore_W4")
	stats.taps.W5 = pss:GetTapNoteScores("TapNoteScore_W5")
	stats.taps.Miss = pss:GetTapNoteScores("TapNoteScore_Miss")
	stats.held = pss:GetHoldNoteScores("HoldNoteScore_Held")
	stats.letGo = pss:GetHoldNoteScores("HoldNoteScore_LetGo")
	if useRidiculous and not replayPrefixMissing then
		stats.ridiculous = gameplay.ridiculousCount
	end
	if fullCounter then stats.longest = pss:MaxCombo() end
end

local function refreshTimingStats()
	stats.replaySegment = replayPrefixMissing
	stats.mean = mean
	stats.stdDev = count > 1 and math.sqrt(math.max(0, m2 / (count - 1))) or 0
	stats.largest = maxOffset
	if replayPrefixMissing then
		-- Etterna resets its combo on resume. Continue this segment from live
		-- judgments while native tap tallies retain their replay snapshot.
		stats.ridiculous = nil
		stats.handScores, stats.handCounts = nil, nil
		if count == 0 then stats.mean, stats.largest, stats.longest = nil, nil, nil end
		if count < 2 then stats.stdDev = nil end
	elseif useDelta then
		for i = 1, 3 do
			stats.handScores[i] = handCounts[i] > 0 and sums[i] / (handCounts[i] * 2) or 0
		end
	end
end

return Def.Actor {
	JudgmentMessageCommand = function(self, message)
		local replaySnapshot = message.FromReplay == true
		if message.Player ~= gameplay.player and not (replaySnapshot and message.Player == 0 and gameplay.player == PLAYER_1) then
			return
		end
		if replaySnapshot then
			if not replaySnapshotPending then
				-- Resume restores counts. The burst has no offset or combo history.
				replaySnapshotPending = true
				replayPrefixMissing = message.MaxWifeScore ~= 0
				clearOffsets()
				if replayPrefixMissing then
					stats.lastOffset = nil
				else
					gameplay.ridiculousCount = 0
				end
			end
		elseif useOffsets or useDelta or useLastOffset then
			collectOffset(message)
		end
		if not refreshPending then
			refreshPending = true
			self:queuecommand("Refresh")
		end
	end,
	RefreshCommand = function(self)
		if not refreshPending then return end
		refreshPending, replaySnapshotPending = false, false
		-- Stage counts and combo may be committed after Judgment is broadcast.
		if useNativeCounts then refreshNativeStats() end
		refreshTimingStats()
		publish(self)
	end,
	CurrentSongChangedMessageCommand = resetAndPublish,
	PracticeModeResetMessageCommand = resetAndPublish,
	PracticeModeReloadMessageCommand = resetAndPublish,
}
