local gameplay = ...
local gameplayCoord = gameplay.gameplayCoord
local gameplaySize = gameplay.gameplaySize
local Config = HV.Config

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

local function saveHUDPreferences()
	if not Config.ProfileDirectory(gameplay.player) then return end
	local ok, err = Config.Player.Save(gameplay.player)
	if not ok and err then SCREENMAN:SystemMessage(err) end
end

local function toggleMinimalisticModePreference()
	local enabled = not HV.MinimalisticMode()
	if not Config.Player.Set(gameplay.player, "HV_MinimalisticMode", enabled) then return end
	saveHUDPreferences()
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
	local nextMode = "Off"
	if mode == "Off" then
		nextMode = Config.Player.Get(gameplay.player, "HV_LastInGameLeaderboardMode")
	else
		Config.Player.Set(gameplay.player, "HV_LastInGameLeaderboardMode", mode)
	end
	if not Config.Player.Set(gameplay.player, "HV_ShowInGameLeaderboard", nextMode) then return end
	saveHUDPreferences()
	MESSAGEMAN:Broadcast("HV_InGameLeaderboardModeChanged", { Mode = nextMode })
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

		HV.GameplaySessionValid = true
		HV.GameplayUsedAutoplay = false

		gameplay.judgeScale = PREFSMAN:GetPreference("TimingWindowScale") or 1.0
		if HV.IsReplayPlayback and HV.IsReplayPlayback() and curScreen and curScreen.GetReplayScore then
			local replayScore = curScreen:GetReplayScore(PLAYER_1)
			if replayScore and type(replayScore.GetJudgeScale) == "function" then
				local ok, scale = pcall(replayScore.GetJudgeScale, replayScore)
				if ok and tonumber(scale) then gameplay.judgeScale = tonumber(scale) end
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

	JudgmentMessageCommand = function(self, params)
		if params.Player ~= PLAYER_1 or HV.GameplayUsedAutoplay then return end
		local state = GAMESTATE:GetPlayerState(PLAYER_1)
		HV.GameplayUsedAutoplay = state and HV.Score.IsAutoplayController(state:GetPlayerController())
	end,

	PlayingUpdateMessageCommand = function(self)
		hideFallbackLifeBar()
	end
}
