local gameplay = ...
local minimalisticHUDVisible = gameplay.minimalisticHUDVisible
local animateGameplayHUDVisibility = gameplay.animateGameplayHUDVisibility
local mainText = gameplay.mainText

if not gameplay.isSync then
return Def.ActorFrame {
	Name = "SongInfoHUD",
	InitCommand = function(self)
		self:xy(SCREEN_CENTER_X, SCREEN_BOTTOM - 14)
		self:visible(minimalisticHUDVisible(true))
	end,
	HV_MinimalisticModeChangedMessageCommand = function(self, params)
		animateGameplayHUDVisibility(self, minimalisticHUDVisible(true, params and params.Enabled))
	end,
	OnCommand = function(self)
		self:diffusealpha(0.6)
	end,

	LoadFont("Zpix Normal") .. {
		InitCommand = function(self)
			self:zoom(0.35):diffuse(mainText):maxwidth(SCREEN_WIDTH * 0.5 / 0.35)
		end,
		BeginCommand = function(self)
			local song = GAMESTATE:GetCurrentSong()
			if song then
				self:settext(song:GetDisplayMainTitle())
			end
		end
	}
}
end
