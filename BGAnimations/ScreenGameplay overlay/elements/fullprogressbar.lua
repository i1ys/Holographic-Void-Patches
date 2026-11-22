local gameplay = ...
local gameplayCoord = gameplay.gameplayCoord
local minimalisticHUDVisible = gameplay.minimalisticHUDVisible
local animateGameplayHUDVisibility = gameplay.animateGameplayHUDVisibility
local getChartLastSecond = gameplay.getChartLastSecond
local accentColor = gameplay.accentColor
local dimText = gameplay.dimText
local subText = gameplay.subText

local progressBarPosition = HV.GetProgressBarPosition()
local barW = SCREEN_WIDTH * 0.4
local barH = 6

local showProgressBar = progressBarPosition ~= "Off" and not gameplay.isSync

-- cache song length
local progSongLen = 0

local function setProgSongLen()
    progSongLen = getChartLastSecond(GAMESTATE:GetCurrentSong(), GAMESTATE:GetCurrentSteps())
end
if showProgressBar then
return Def.ActorFrame {
	Name = "ProgressBarContainer",
	InitCommand = function(self)
		self:xy(gameplayCoord("FullProgressBarX"), gameplayCoord("FullProgressBarY"))
		self:visible(minimalisticHUDVisible(showProgressBar))
	end,
	HV_MinimalisticModeChangedMessageCommand = function(self, params)
		animateGameplayHUDVisibility(self, minimalisticHUDVisible(showProgressBar, params and params.Enabled))
	end,
	OnCommand = function(self)
		setMovableActor({"DeviceButton_9"}, self, self:GetChild("Border"))
	end,
	BeginCommand = function(self)
		setProgSongLen()
		self:SetUpdateFunction(function(self)
			self:playcommand("UpdateBars")
		end)
	end,
	CurrentSongChangedMessageCommand = function(self)
		setProgSongLen()
	end,
	Def.Quad {
		Name = "ProgressBarBG",
		InitCommand = function(self)
			self:zoomto(barW, barH):diffuse(color("0,0,0,0.2"))
		end
	},

	Def.Quad {
		Name = "ProgressFill",
		InitCommand = function(self)
			self:halign(0):x(-barW / 2)
				:zoomto(0, barH):diffuse(accentColor):diffusealpha(0.7)
		end,
		UpdateBarsCommand = function(self)
			-- local song = GAMESTATE:GetCurrentSong()
			-- if song then
			-- 	local steps = GAMESTATE:GetCurrentSteps()
			-- 	local len = getChartLastSecond(song, steps)
			if progSongLen > 0 then
				local cur = GAMESTATE:GetSongPosition():GetMusicSeconds()
				local pct = math.max(0, math.min(cur / progSongLen, 1))
				self:zoomto(barW * pct, barH)
			end
			-- end
		end
	},

	-- Remaining Time (incorporating music rate and ms)
	LoadFont("Common Normal") .. {
		Name = "TimeRemaining",
		InitCommand = function(self)
			self:x(barW / 2 + 8):zoom(0.35):halign(0):diffuse(dimText)
		end,
		UpdateBarsCommand = function(self)
			-- local song = GAMESTATE:GetCurrentSong()
			-- if song then
			-- 	local steps = GAMESTATE:GetCurrentSteps()
			-- 	local songLen = getChartLastSecond(song, steps)
			local curTime = GAMESTATE:GetSongPosition():GetMusicSeconds()
			local remaining = math.max(0, progSongLen - curTime) / getCurRateValue()
			local mins = math.floor(remaining / 60)
			local secs = math.floor(remaining % 60)
			local ms = math.floor((remaining - math.floor(remaining)) * 100)
			self:settext(string.format("-%d:%02d.%02d", mins, secs, ms))
			-- end
		end
	},

	-- Elapsed Time (incorporating music rate and ms)
	LoadFont("Common Normal") .. {
		Name = "TimeElapsed",
		InitCommand = function(self)
			self:x(-barW / 2 - 8):zoom(0.35):halign(1):diffuse(subText)
		end,
		UpdateBarsCommand = function(self)
			local song = GAMESTATE:GetCurrentSong()
			if song then
				local curTime = math.max(0, GAMESTATE:GetSongPosition():GetMusicSeconds()) / getCurRateValue()
				local mins = math.floor(curTime / 60)
				local secs = math.floor(curTime % 60)
				local ms = math.floor((curTime - math.floor(curTime)) * 100)
				self:settext(string.format("%d:%02d.%02d", mins, secs, ms))
			end
		end,

	}
	,
	MovableBorder(barW, 16, 1, 0, 0)
}
end -- End progress bar visibility check
