--- Holographic Void: ScreenSelectMusic Background
-- OLED black with subtle animated scan lines.

local t = Def.ActorFrame {}

-- Full-screen OLED black
t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:Center():zoomto(SCREEN_WIDTH, SCREEN_HEIGHT):diffuse(color("0,0,0,1"))
	end
}

-- Song Background Sprite
t[#t + 1] = Def.Sprite {
	Name = "SongBackground",
	InitCommand = function(self)
		self:Center():visible(false)
	end,
	CurrentSongChangedMessageCommand = function(self)
		self:visible(false)
	end,
	HV_SelectionDetailsReadyMessageCommand = function(self)
		local song = GAMESTATE:GetCurrentSong()
		local brightness = HV.GetSongBackgroundBrightness()
		local path = brightness > 0 and song and song:GetBackgroundPath()
		if not path or path == "" then
			self:visible(false)
			return
		end
		if path ~= self.lastPath then
			self:Load(path):zoomto(SCREEN_WIDTH, SCREEN_HEIGHT)
			self.lastPath = path
		end
		self:diffusealpha(brightness):visible(true)
	end,
}

-- Subtle horizontal scan lines (every 3 pixels for a CRT effect)
for i = 0, math.floor(SCREEN_HEIGHT / 6) do
	t[#t + 1] = Def.Quad {
		InitCommand = function(self)
			self:xy(SCREEN_CENTER_X, i * 6)
				:zoomto(SCREEN_WIDTH, 1)
				:diffuse(color("1,1,1,0.015"))
		end
	}
end

-- Header accent line
t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:xy(SCREEN_CENTER_X, 50)
			:zoomto(SCREEN_WIDTH * 0.5, 1)
			:diffuse(HVColor.Accent):diffusealpha(0.3)
	end
}

-- Load Shared Background Particles
t[#t + 1] = LoadActor("../_particles.lua")

return t
