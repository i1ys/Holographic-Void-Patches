local gameplay = ...

return Def.Actor {
	Name = "FailSoundController",
	CurrentSongChangedMessageCommand = function(self)
		gameplay.failSoundPlayed = false
		gameplay.autofailJudgments = { W2 = 0, W3 = 0, W4 = 0, W5 = 0, Miss = 0 }
	end,
	PlayingUpdateMessageCommand = function(self)
		if gameplay.failSoundPlayed then return end
		local top = SCREENMAN:GetTopScreen()
		if not top or not top.GetLifeMeter then return end
		local lifeMeter = top:GetLifeMeter(gameplay.player)
		if not lifeMeter or not lifeMeter.GetLife then return end
		local life = lifeMeter:GetLife() or 0
		if life <= 0 then
			gameplay.playFailSound()
		end
	end,
}
