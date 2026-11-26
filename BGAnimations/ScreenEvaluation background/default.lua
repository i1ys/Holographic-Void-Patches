--- Holographic Void: ScreenEvaluation Background

local t = Def.ActorFrame {}

-- OLED Black
t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:Center():zoomto(SCREEN_WIDTH, SCREEN_HEIGHT):diffuse(color("0,0,0,1"))
	end
}

-- Song Background Sprite
t[#t + 1] = Def.Sprite {
	Name = "SongBackground",
	InitCommand = function(self)
		self:Center():diffusealpha(0)
	end,
	OnCommand = function(self)
		local song = GAMESTATE:GetCurrentSong()
		local brightness = HV.GetSongBackgroundBrightness()
		local path = brightness > 0 and song and song:GetBackgroundPath()
		if path and path ~= "" then
			self:LoadBackground(path):zoomto(SCREEN_WIDTH, SCREEN_HEIGHT):visible(true)
			self:stoptweening():linear(0.2):diffusealpha(brightness)
		else
			self:visible(false):diffusealpha(0)
		end
	end,
}

-- Subtle grid
for i = 1, 8 do
	t[#t + 1] = Def.Quad {
		InitCommand = function(self)
			self:xy(SCREEN_CENTER_X, (SCREEN_HEIGHT / 9) * i)
				:zoomto(SCREEN_WIDTH, 1):diffuse(color("1,1,1,0.02"))
		end
	}
end

-- Load Shared Background Particles
t[#t + 1] = LoadActor("../_particles.lua")

return t
