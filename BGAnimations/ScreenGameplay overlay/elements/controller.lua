local gameplay = ...
local gameplayCoord = gameplay.gameplayCoord
local gameplaySize = gameplay.gameplaySize
local ThemePrefs = HV.LegacyPrefs

local function hideFallbackLifeBar()
	local top = SCREENMAN and SCREENMAN:GetTopScreen()
	if not top or not top.GetLifeMeter then return end
	for _, player in ipairs(GAMESTATE:GetEnabledPlayers()) do
		local lifeMeter = top:GetLifeMeter(player)
		if lifeMeter then
			lifeMeter:visible(false)
			lifeMeter:diffusealpha(0)
		end
	end
end

local function toggleMinimalisticModePreference()
	local enabled = not HV.MinimalisticMode()
	ThemePrefs.Set("HV_MinimalisticMode", enabled)
	local top = SCREENMAN and SCREENMAN:GetTopScreen()
	if top and top.GetChild then
		local overlay = top:GetChild("GameplayOverlay")
		if overlay then
			overlay:playcommand("ApplyMinimalisticMode", { Enabled = enabled })
		end
	end
	if SCREENMAN then
		SCREENMAN:SystemMessage("Minimalistic Mode: " .. (enabled and "On" or "Off"))
	end
	MESSAGEMAN:Broadcast("HV_MinimalisticModeChanged", { Enabled = enabled })
end

local function toggleInGameLeaderboardPreference()
	local mode = HV.ShowInGameLeaderboard()
	if mode == "Off" then
		local lastMode = ThemePrefs.Get("HV_LastInGameLeaderboardMode") or "Local"
		if lastMode ~= "Local" and lastMode ~= "Online" then lastMode = "Local" end
		ThemePrefs.Set("HV_ShowInGameLeaderboard", lastMode)
		MESSAGEMAN:Broadcast("HV_InGameLeaderboardModeChanged", { Mode = lastMode })
	else
		if mode == "Local" or mode == "Online" then
			ThemePrefs.Set("HV_LastInGameLeaderboardMode", mode)
		end
		ThemePrefs.Set("HV_ShowInGameLeaderboard", "Off")
		MESSAGEMAN:Broadcast("HV_InGameLeaderboardModeChanged", { Mode = "Off" })
	end
end

local function isRidiculousJudgment(params)
	return HV.EmulateRidiculousEnabled() and params and params.TapNoteScore == "TapNoteScore_W1" and params.TapNoteOffset and math.abs(params.TapNoteOffset) <= 0.01125 * (tonumber(gameplay.judgeScale) or 1)
end

return Def.ActorFrame {
	Name = "GameplayOverlay",
	ApplyMinimalisticModeCommand = function(self, params)
		self:playcommand("HV_MinimalisticModeChangedMessage", params)
	end,
	BeginCommand = function(self)
		hideFallbackLifeBar()
		-- The online-replay marker is set by the online score launcher and must
		-- not leak into subsequent ordinary gameplay/evaluation screens.
		if not (HV.IsReplayPlayback and HV.IsReplayPlayback()) then
			HV.OnlineReplayActive = false
			HV.OnlineReplayName = nil
		end
		HV.OnlineEvaluationActive = nil
		HV.OnlineEvaluationName = nil
		gameplay.failSoundPlayed = false
		gameplay.autofailStopped = false
		gameplay.autofailJudgments = { W2 = 0, W3 = 0, W4 = 0, W5 = 0, Miss = 0 }
		-- Re-check sync mode via SCREENMAN now that it's safer
		local curScreen = SCREENMAN:GetTopScreen()
		if curScreen and curScreen:GetName():find("Sync") then
			gameplay.isSync = true
		end
		-- Apply Measure Lines (Beat Bars) mod
		local beatBarMod = HV.ShowMeasureLines() and "beatbars" or "nobeatbars"

		-- Apply mods to all enabled players
		for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
			local ps = GAMESTATE:GetPlayerState(pn)
			for _, level in ipairs({"ModsLevel_Preferred", "ModsLevel_Stage", "ModsLevel_Current"}) do
				ps:GetPlayerOptions(level):FromString(beatBarMod)
			end

			-- Sync Mode overrides
			if gameplay.isSync then
				for _, level in ipairs({"ModsLevel_Preferred", "ModsLevel_Stage", "ModsLevel_Current"}) do
					local po = ps:GetPlayerOptions(level)
					po:CMod(400)
					po:Reverse(0) -- Upscroll
				end
			end
		end

		HV.LastGameplayTime = os.time()
		HV.GameplaySessionValid = true

		-- Properly initialize total chart points once song/steps are loaded
		gameplay.maxPoints = (getMaxNotes(PLAYER_1) or 1) * 2
		gameplay.pointsLost = 0
		gameplay.ridiculousCount = 0
		gameplay.judgeScale = PREFSMAN:GetPreference("TimingWindowScale") or 1.0
		if HV.IsReplayPlayback and HV.IsReplayPlayback() and curScreen and curScreen.GetReplayScore then
			local replayScore = curScreen:GetReplayScore(PLAYER_1)
			if replayScore and type(replayScore.GetJudgeScale) == "function" then
				local ok, scale = pcall(replayScore.GetJudgeScale, replayScore)
				if ok and tonumber(scale) then gameplay.judgeScale = tonumber(scale) end
			end
		end

		-- Initialize Auto-Fail Personal Best threshold if needed
		local condition = ThemePrefs.Get("HV_AutoFailCondition")
		if condition == "Personal Best" then
			local best = GetDisplayScore()
			if best then
				gameplay.pbThreshold = getJ4NormalizedPercentage(best)
			else
				-- Fallback to Wife Percent threshold if no PB exists
				gameplay.pbThreshold = tonumber(ThemePrefs.Get("HV_AutoFailThreshold_Wife")) or 93.00
			end
		end
	end,
	OnCommand = function(self)
		hideFallbackLifeBar()
		-- Double check mods on OnCommand just in case
		if gameplay.isSync then
			for _, pn_loop in ipairs(GAMESTATE:GetEnabledPlayers()) do
				local ps = GAMESTATE:GetPlayerState(pn_loop)
				ps:GetPlayerOptions("ModsLevel_Current"):CMod(400)
				ps:GetPlayerOptions("ModsLevel_Current"):Reverse(0)
			end
		end

		-- Notefield Customization
		local top = SCREENMAN:GetTopScreen()
		if top then
			-- Input Callback for Ghost Tapping feedback
			top:AddInputCallback(function(event)
				if event.type == "InputEventType_Release" then return end
				if event.type == "InputEventType_FirstPress" then
					local b = event.button
					local db = event.DeviceInput and event.DeviceInput.button or ""
					if db == "DeviceButton_tab" and INPUTFILTER and INPUTFILTER:IsControlPressed() then
						toggleMinimalisticModePreference()
						return true
					elseif db == "DeviceButton_tab" then
						toggleInGameLeaderboardPreference()
						return true
					end
					-- Filter for common gameplay buttons to avoid menu buttons triggering HUD animations
					if b == "Left" or b == "Down" or b == "Up" or b == "Right" or
					   b == "Key 1" or b == "Key 2" or b == "Key 3" or b == "Key 4" or
					   b == "Key 5" or b == "Key 6" or b == "Key 7" then
						MESSAGEMAN:Broadcast("GhostTap")
					end
				end
			end)

			local player = top:GetChild("PlayerP1")
			if player then
				local notefield = player:GetChild("NoteField")
				if notefield then
					local nfX = gameplayCoord("NotefieldX")
					local nfY = gameplayCoord("NotefieldY")
					local usingReverse = GAMESTATE:GetPlayerState():GetCurrentPlayerOptions():UsingReverse()

					notefield:addx(nfX)
					notefield:addy(nfY * (usingReverse and 1 or -1))

					local cols = notefield:get_column_actors()
					local nfW = gameplaySize("NotefieldWidth")
					local nfH = gameplaySize("NotefieldHeight")
					local nfS = gameplaySize("NotefieldSpacing")

					for _, col in ipairs(cols) do
						col:zoomtowidth(nfW)
						col:zoomtoheight(nfH)
					end

					if setMovableNotefield then
						setMovableNotefield(notefield, cols)
						if spaceNotefieldCols then
							spaceNotefieldCols(nfS)
						end
					end
				end
			end
		end
	end,



	CurrentSongChangedMessageCommand = function(self)
		hideFallbackLifeBar()
		gameplay.ridiculousCount = 0
		-- Re-apply sync mods on every loop start to prevent engine resets
		if gameplay.isSync then
			for _, pn_loop in ipairs(GAMESTATE:GetEnabledPlayers()) do
				local ps = GAMESTATE:GetPlayerState(pn_loop)
				local po = ps:GetPlayerOptions("ModsLevel_Preferred")
				po:CMod(400)
				po:Reverse(0)
				local co = ps:GetPlayerOptions("ModsLevel_Current")
				co:CMod(400)
				co:Reverse(0)
			end
		end
	end,

	-- Shared PointsLost Accumulator (Wife3 Adherent)
	-- Fully compliant with Etterna's internal wife3 scoring and evaluation mechanics
	JudgmentMessageCommand = function(self, params)
		if params.Player ~= PLAYER_1 then return end
		if gameplay.autofailStopped then return end

		-- Exclude non-tap judgements that don't affect points
		local s = params.TapNoteScore
		if params.HoldNoteScore or not s or s == "TapNoteScore_None" or s == "TapNoteScore_AvoidMine" or
		   s == "TapNoteScore_CheckpointHit" or s == "TapNoteScore_CheckpointMiss" then
			return
		end

		if s == "TapNoteScore_HitMine" then
			-- Match Etterna engine internal Wife3 rescoring logic (-350% weight = 7.0 points lost)
			gameplay.pointsLost = gameplay.pointsLost + 7.0
		elseif params.TapNoteOffset then
			local offset = math.abs(params.TapNoteOffset) * 1000
			local weight = wife3(offset, gameplay.judgeScale, "Wife3")
			gameplay.pointsLost = gameplay.pointsLost + (2.0 - weight)
		elseif s == "TapNoteScore_Miss" then
			-- A full miss loses 7.5 points relative to the 2.0 potential max per tap (2.0 - (-5.5) = 7.5)
			gameplay.pointsLost = gameplay.pointsLost + 7.5
		end

		if isRidiculousJudgment(params) then
			gameplay.ridiculousCount = gameplay.ridiculousCount + 1
		end

		if s == "TapNoteScore_W2" then
			gameplay.autofailJudgments.W2 = gameplay.autofailJudgments.W2 + 1
		elseif s == "TapNoteScore_W3" then
			gameplay.autofailJudgments.W3 = gameplay.autofailJudgments.W3 + 1
		elseif s == "TapNoteScore_W4" then
			gameplay.autofailJudgments.W4 = gameplay.autofailJudgments.W4 + 1
		elseif s == "TapNoteScore_W5" then
			gameplay.autofailJudgments.W5 = gameplay.autofailJudgments.W5 + 1
		elseif s == "TapNoteScore_Miss" then
			gameplay.autofailJudgments.Miss = gameplay.autofailJudgments.Miss + 1
		end

		MESSAGEMAN:Broadcast("HV_PointsUpdate")
	end,

	HoldNoteScoreMessageCommand = function(self, params)
		if params.Player ~= PLAYER_1 then return end
		if gameplay.autofailStopped then return end
		-- The engine applies the hold penalty even if the head was completely missed
		if params.HoldNoteScore == "HoldNoteScore_LetGo" or params.HoldNoteScore == "HoldNoteScore_MissedHold" then
			gameplay.pointsLost = gameplay.pointsLost + 4.5
			MESSAGEMAN:Broadcast("HV_PointsUpdate")
		end
	end,

	RollNoteScoreMessageCommand = function(self, params)
		if params.Player ~= PLAYER_1 then return end
		if gameplay.autofailStopped then return end
		if params.RollNoteScore == "RollNoteScore_LetGo" or params.RollNoteScore == "RollNoteScore_MissedRoll" then
			gameplay.pointsLost = gameplay.pointsLost + 4.5
			MESSAGEMAN:Broadcast("HV_PointsUpdate")
		end
	end,
	PlayingUpdateMessageCommand = function(self)
		hideFallbackLifeBar()
	end
}
