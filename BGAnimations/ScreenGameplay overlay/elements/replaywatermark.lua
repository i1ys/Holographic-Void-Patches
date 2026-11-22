return LoadFont("Common Normal") .. {
		Name = "OnlineReplayWatermark",
		InitCommand = function(self)
			self:xy(SCREEN_CENTER_X, SCREEN_CENTER_Y):zoom(2.2):rotationz(-15)
				:diffuse(HVColor.Accent):diffusealpha(0.14):z(999):draworder(10000):visible(false)
			self:settext("ONLINE REPLAY")
		end,
		OnCommand = function(self)
			self:visible(HV.OnlineReplayActive == true)
		end
	}
