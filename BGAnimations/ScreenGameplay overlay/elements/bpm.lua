local gameplay = ...
local gameplayCoord = gameplay.gameplayCoord
local gameplaySize = gameplay.gameplaySize
local minimalisticHUDVisible = gameplay.minimalisticHUDVisible
local animateGameplayHUDVisibility = gameplay.animateGameplayHUDVisibility
local subText = gameplay.subText

if not gameplay.isSync then
return Def.ActorFrame {
	Name = "BPMText",
	InitCommand = function(self)
		self:xy(gameplayCoord("BPMTextX"), gameplayCoord("BPMTextY")):zoom(gameplaySize("BPMTextZoom"))
		self:visible(minimalisticHUDVisible(true))
	end,
	HV_MinimalisticModeChangedMessageCommand = function(self, params)
		animateGameplayHUDVisibility(self, minimalisticHUDVisible(true, params and params.Enabled))
	end,
	OnCommand = function(self)
		setMovableActor({"DeviceButton_x", "DeviceButton_c"}, self, self:GetChild("Border"))
		self:diffusealpha(0.6)
	end,
	LoadFont("Common Normal") .. {
		Name = "Text",
		InitCommand = function(self)
			self:zoom(0.35):diffuse(subText):maxwidth(SCREEN_WIDTH / 0.35)
		end,
		PlayingUpdateMessageCommand = function(self)
			local song = GAMESTATE:GetCurrentSong()
			if song then
				local bps = GAMESTATE:GetSongPosition():GetCurBPS()
				local bpm = bps * 60 * getCurRateValue()
				local rate = getCurRateString()
				self:settextf("%d BPM    %s Rate", math.floor(bpm + 0.5), rate)
			end
		end
	},
	MovableBorder(150, 18, 1, 0, 0)
}
end
