local gameplay = ...

return Def.ActorFrame {
	BeginCommand = function(self)
		self:SetUpdateFunction(function(self)
			-- Lifebar still uses this for now
			MESSAGEMAN:Broadcast("PlayingUpdate")
		end)
	end,

	-- NoteMask for Sync Mode (placed here to be below judgments/combo)
	Def.Quad {
		Name = "SyncNoteMask",
		InitCommand = function(self)
			self:Center():zoomto(SCREEN_WIDTH * 0.4, SCREEN_HEIGHT)
				:diffuse(color("0,0,0,1")):diffusealpha(0)
				:visible(gameplay.isSync)
		end,
		SyncTriggeredMessageCommand = function(self)
			self:linear(2):diffusealpha(1)
		end,
		CurrentSongChangedMessageCommand = function(self)
			self:stoptweening():diffusealpha(0)
		end
	}
}
