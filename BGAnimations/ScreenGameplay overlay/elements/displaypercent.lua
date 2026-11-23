local gameplay = ...
local showCurrentWife = HV.ShowCurrentWife() and not gameplay.isSync
if not showCurrentWife then return end

local function setPercent(self, percent)
	self:settextf("%.4f%%", percent)
	self:diffuse(HVColor.GetGradeColor(getEtternaGrade(percent))):diffusealpha(0.7)
end

local function resetPercent(self)
	setPercent(self, 0)
end

return Def.ActorFrame {
	Name = "CenteredScore",
	InitCommand = function(self)
		self:xy(gameplay.gameplayCoord("DisplayPercentX"), gameplay.gameplayCoord("DisplayPercentY"))
			:zoom(gameplay.gameplaySize("DisplayPercentZoom")):diffusealpha(0.8)
		self:visible(gameplay.minimalisticHUDVisible(showCurrentWife))
	end,
	HV_MinimalisticModeChangedMessageCommand = function(self, params)
		gameplay.animateGameplayHUDVisibility(self, gameplay.minimalisticHUDVisible(showCurrentWife, params and params.Enabled))
	end,
	OnCommand = function(self)
		setMovableActor({"DeviceButton_w", "DeviceButton_e"}, self, self:GetChild("Border"))
	end,

	LoadFont("Common Normal") .. {
		Name = "ScoreValue",
		InitCommand = function(self)
			self:zoom(0.45)
			resetPercent(self)
		end,
		PracticeModeResetMessageCommand = resetPercent,
		PracticeModeReloadMessageCommand = resetPercent,
		JudgmentMessageCommand = function(self, message)
			local percent = HV.Score.GetLiveWifePercent(message, gameplay.player)
			if percent ~= nil then setPercent(self, percent) end
		end,
	},
	MovableBorder(110, 20, 1, 0, 0)
}
