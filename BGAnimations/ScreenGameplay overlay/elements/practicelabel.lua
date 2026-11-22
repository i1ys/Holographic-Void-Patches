local gameplay = ...
local accentColor = gameplay.accentColor

local progressBarPosition = HV.GetProgressBarPosition()
local barY = progressBarPosition == "Top" and 12 or (progressBarPosition == "Bottom" and SCREEN_BOTTOM - 12 or 12)

return Def.ActorFrame {
	Name = "IndicatorFrame",
	InitCommand = function(self)
		self:xy(SCREEN_CENTER_X, barY + 15):visible(GAMESTATE:IsPracticeMode())
	end,
	LoadFont("Common Normal") .. {
		Text = "** PRACTICE MODE **",
		InitCommand = function(self) self:zoom(0.35):diffuse(accentColor):diffusealpha(0.8) end
	}
}
