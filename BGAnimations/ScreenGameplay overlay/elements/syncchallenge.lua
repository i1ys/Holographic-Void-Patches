local gameplay = ...

return Def.ActorFrame {
	Name = "SyncChallengeOverlay",
	InitCommand = function(self) self:visible(gameplay.isSync) end,
	(function()
		local noteCounter = 0
		local threshold = 10
		local triggered = false

		return Def.ActorFrame {
			LoadFont("Common Normal") .. {
				Name = "Message",
				InitCommand = function(self)
					self:Center():zoom(0.8):diffusealpha(0):settext("Keep tapping to the beat")
				end,
				PulseCommand = function(self)
					self:stoptweening():linear(0.5):zoom(0.85):linear(0.5):zoom(0.8):queuecommand("Pulse")
				end
			},
			JudgmentMessageCommand = function(self, params)
				if not gameplay.isSync or triggered then return end
				if params.TapNoteScore then
					noteCounter = noteCounter + 1
					if noteCounter >= threshold then
						triggered = true
						MESSAGEMAN:Broadcast("SyncTriggered")
						local msg = self:GetChild("Message")
						msg:linear(1):diffusealpha(1):queuecommand("Pulse")
					end
				end
			end,
			CurrentSongChangedMessageCommand = function(self)
				noteCounter = 0
				triggered = false
				local msg = self:GetChild("Message")
				if msg then msg:stoptweening():diffusealpha(0) end
			end
		}
	end)()
}
