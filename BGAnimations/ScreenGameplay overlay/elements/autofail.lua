local gameplay = ...
local ThemePrefs = HV.LegacyPrefs

local function GetCurrentSongSecond()
	local pos = GAMESTATE:GetSongPosition()
	if pos and pos.GetMusicSeconds then
		return pos:GetMusicSeconds() or 0
	end
	return 0
end

local function HardStopAutofail(top)
	if not top then return end

	local freezePos = math.max(0, GetCurrentSongSecond())

	if top.SetSongPosition then
		pcall(function() top:SetSongPosition(freezePos) end)
	end

	if top.GetPaused and top.TogglePause then
		local ok, paused = pcall(function() return top:GetPaused() end)
		if ok and not paused then
			pcall(function() top:TogglePause() end)
		end
	end

	if top.GetLifeMeter then
		local lifeMeter = top:GetLifeMeter(gameplay.player)
		if lifeMeter and lifeMeter.ChangeLife then
			pcall(function() lifeMeter:ChangeLife(-10) end)
		end
	end
end

return Def.Actor {
	Name = "AutoFailController",
	InitCommand = function(self)
		self.hasTriggered = false
	end,
	HV_PointsUpdateMessageCommand = function(self)
		-- Let the engine finish updating PlayerStageStats before reading the
		-- current Wife percentage.  Reading it in the message handler can see a
		-- transient zero on the first note and trigger Absolute incorrectly.
		self:queuecommand("Evaluate")
	end,
	EvaluateCommand = function(self)
		local actionMode = ThemePrefs.Get("HV_AutoFailMode")
		if GAMESTATE:IsPracticeMode() or actionMode == "Off" or not actionMode or self.hasTriggered then return end

		local condition = ThemePrefs.Get("HV_AutoFailCondition")

		local triggered = false

		if condition == "Wife Percent" then
			local threshold = tonumber(ThemePrefs.Get("HV_AutoFailThreshold_Wife")) or 93.00
			local subtractiveWife = ((gameplay.maxPoints - gameplay.pointsLost) / gameplay.maxPoints) * 100
			if subtractiveWife <= threshold then
				triggered = true
			end
		elseif condition == "Sync to Goal" then
			local threshold = tonumber(ThemePrefs.Get("HV_PacemakerTargetGoal")) or 93.00
			if GetDisplayScore() then threshold = getJ4NormalizedPercentage(GetDisplayScore()) end
			local subtractiveWife = ((gameplay.maxPoints - gameplay.pointsLost) / gameplay.maxPoints) * 100
			if subtractiveWife <= threshold then
				triggered = true
			end
		elseif condition == "Personal Best" then
			local subtractiveWife = ((gameplay.maxPoints - gameplay.pointsLost) / gameplay.maxPoints) * 100
			if subtractiveWife <= gameplay.pbThreshold then
				triggered = true
			end
		elseif condition == "Judgement Count" then
			local limit = tonumber(ThemePrefs.Get("HV_AutoFailThreshold_Count")) or 10
			local judgePref = ThemePrefs.Get("HV_AutoFailJudgement") or "Miss"
			local order = {"W2","W3","W4","W5","Miss"}
			local idx = 5
			for i=1, #order do
				if order[i] == judgePref then idx = i break end
			end
			local currentCount = 0
			for i=idx, #order do
				currentCount = currentCount + (gameplay.autofailJudgments[order[i]] or 0)
			end
			if currentCount > limit then
				triggered = true
			end
		end

		if triggered then
			-- Prevent multiple triggers
			self:playcommand("ActionTriggered")
		end
	end,
	ActionTriggeredCommand = function(self)
		if self.hasTriggered then return end
		if GAMESTATE:IsPracticeMode() then return end
		self.hasTriggered = true
		gameplay.autofailStopped = true

		local actionMode = ThemePrefs.Get("HV_AutoFailMode")
		local top = SCREENMAN:GetTopScreen()
		local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats()

		if top and pss then
			gameplay.playFailSound()

			-- Explicitly mark the score as Failed for the engine's stats committer
			if pss.FailPlayer then
				pss:FailPlayer()
			end

			if actionMode == "Fail" then
				top:PostScreenMessage("SM_BeginFailed", 0)
				HardStopAutofail(top)
			elseif actionMode == "Restart" then
				SCREENMAN:SetNewScreen("ScreenGameplay")
			end
		end
	end,
	InputEventCommand = function(self)
		-- Consume input while the failed-screen transition is being processed.
		if self.hasTriggered then return true end
	end
}
