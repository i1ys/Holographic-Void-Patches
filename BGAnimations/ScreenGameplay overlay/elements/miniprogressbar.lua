local gameplay = ...
local gameplayCoord = gameplay.gameplayCoord
local minimalisticHUDVisible = gameplay.minimalisticHUDVisible
local animateGameplayHUDVisibility = gameplay.animateGameplayHUDVisibility
local getChartLastSecond = gameplay.getChartLastSecond
local accentColor = gameplay.accentColor
local dimText = gameplay.dimText
local ThemePrefs = HV.LegacyPrefs

-- Compact progress bar and remaining time, positioned below the combo by default.
local miniProgressBarEnabled = ThemePrefs.Get("HV_MiniProgressBar") ~= false
local miniBarW, miniBarH = 50, 4
local miniSongLen = 0
local function setMiniSongLen()
	miniSongLen = getChartLastSecond(GAMESTATE:GetCurrentSong(), GAMESTATE:GetCurrentSteps())
end

if miniProgressBarEnabled and not gameplay.isSync then
	return Def.ActorFrame {
		Name = "MiniProgressBarContainer",
		InitCommand = function(self) self:xy(gameplayCoord("MiniProgressBarX"), gameplayCoord("MiniProgressBarY")):visible(minimalisticHUDVisible(true)) end,
		HV_MinimalisticModeChangedMessageCommand = function(self, params) animateGameplayHUDVisibility(self, minimalisticHUDVisible(true, params and params.Enabled)) end,
		OnCommand = function(self) setMovableActor({"DeviceButton_q"}, self, self:GetChild("Border")) end,
		BeginCommand = function(self)
			setMiniSongLen()
			self:SetUpdateFunction(function(self) self:playcommand("UpdateMiniBar") end)
		end,
		CurrentSongChangedMessageCommand = function(self) setMiniSongLen() end,
		Def.Quad { Name = "Background", InitCommand = function(self) self:zoomto(miniBarW, miniBarH):diffuse(color("0,0,0,0.3")) end },
		Def.Quad { Name = "Fill", InitCommand = function(self) self:halign(0):x(-miniBarW / 2):zoomto(0, miniBarH):diffuse(accentColor):diffusealpha(0.8) end,
			UpdateMiniBarCommand = function(self)
				if miniSongLen > 0 then self:zoomto(miniBarW * math.max(0, math.min(GAMESTATE:GetSongPosition():GetMusicSeconds() / miniSongLen, 1)), miniBarH) end
			end },
		LoadFont("Common Normal") .. { Name = "TimeRemaining", InitCommand = function(self) self:y(9):zoom(0.3):halign(0.5):diffuse(dimText) end,
			UpdateMiniBarCommand = function(self)
				local remaining = math.max(0, miniSongLen - GAMESTATE:GetSongPosition():GetMusicSeconds()) / getCurRateValue()
				self:settextf("-%d:%02d", math.floor(remaining / 60), math.floor(remaining % 60))
			end },
		MovableBorder(miniBarW, 22, 0.5, 0, 0)
	}
end
