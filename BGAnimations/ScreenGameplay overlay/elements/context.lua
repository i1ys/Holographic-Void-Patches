local loadingScreen = Var "LoadingScreen" or ""
local gameplay = {
	player = GAMESTATE:GetEnabledPlayers()[1] or PLAYER_1,
	isSync = loadingScreen:find("Sync") ~= nil,
	pointsLost = 0,
	maxPoints = 1,
	pbThreshold = 0,
	judgeScale = 1.0,
	autofailJudgments = { W2 = 0, W3 = 0, W4 = 0, W5 = 0, Miss = 0 },
	ridiculousCount = 0,
	autofailStopped = false,
	failSoundPlayed = false,
	accentColor = HVColor.Accent,
	dimText = color("0.45,0.45,0.45,1"),
	subText = color("0.65,0.65,0.65,1"),
	mainText = color("0.85,0.85,0.85,1"),
	brightText = color("1,1,1,1"),
}

local failSfxPath = THEME:GetPathS("", "ScreenGameplay failed")

function gameplay.playFailSound()
	if gameplay.failSoundPlayed then return end
	gameplay.failSoundPlayed = true
	if failSfxPath and failSfxPath ~= "" then
		SOUND:PlayOnce(failSfxPath)
	end
end

function gameplay.gameplayCoord(name)
	return (MovableValues and MovableValues[name]) or getDefaultGameplayCoordinate(name) or 0
end

function gameplay.gameplaySize(name)
	return (MovableValues and MovableValues[name]) or getDefaultGameplaySize(name) or 1
end

function gameplay.minimalisticHUDVisible(baseVisible, enabled)
	if enabled == nil then enabled = HV.MinimalisticMode() end
	return baseVisible and not enabled
end

function gameplay.animateGameplayHUDVisibility(self, visible, instant)
	self:stoptweening()
	if visible then
		self:visible(true)
		if instant then
			self:diffusealpha(1):zoom(1)
		else
			self:diffusealpha(0):zoom(0.96):decelerate(0.18):diffusealpha(1):zoom(1)
		end
	else
		if instant then
			self:diffusealpha(0):zoom(0.96):visible(false)
		else
			self:accelerate(0.14):diffusealpha(0):zoom(0.96):sleep(0):visible(false)
		end
	end
end

function gameplay.getChartLastSecond(song, steps)
	if steps then
		local ok, len = pcall(function() return steps:GetLastSecond() end)
		if ok and len and len > 0 then return len end
	end
	if song then
		local ok, len = pcall(function() return song:GetLastSecond() end)
		if ok and len and len > 0 then return len end
		ok, len = pcall(function() return song:MusicLengthSeconds() end)
		if ok and len and len > 0 then return len end
	end
	return 0
end

return gameplay
