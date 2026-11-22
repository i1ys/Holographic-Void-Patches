local gameplay = ...
local gameplayCoord = gameplay.gameplayCoord
local gameplaySize = gameplay.gameplaySize
local minimalisticHUDVisible = gameplay.minimalisticHUDVisible
local animateGameplayHUDVisibility = gameplay.animateGameplayHUDVisibility
local ThemePrefs = HV.LegacyPrefs

local showGoalTrackerText = HV.ShowGoalTrackerText() and not gameplay.isSync
if showGoalTrackerText then
	local pacemakerMode = ThemePrefs.Get("HV_PacemakerTargetType")
	if not pacemakerMode or pacemakerMode == "" then pacemakerMode = "Target" end

	local targetGoalPref = ThemePrefs.Get("HV_PacemakerTargetGoal")
	local targetGoalPct = tonumber(targetGoalPref) or 93
	local targetGoal = targetGoalPct / 100

	-- Set the engine-side target goal and replay mode
	GAMESTATE:GetPlayerState():SetTargetGoal(targetGoal)
	GAMESTATE:GetPlayerState():SetGoalTrackerUsesReplay(pacemakerMode == "PBReplay")

	return Def.ActorFrame {
		Name = "TextPacemaker",
		InitCommand = function(self)
			self:xy(gameplayCoord("TargetTrackerX"), gameplayCoord("TargetTrackerY")):zoom(gameplaySize("TargetTrackerZoom"))
			self:visible(minimalisticHUDVisible(showGoalTrackerText))
		end,
		HV_MinimalisticModeChangedMessageCommand = function(self, params)
			animateGameplayHUDVisibility(self, minimalisticHUDVisible(showGoalTrackerText, params and params.Enabled))
		end,
		OnCommand = function(self)
			setMovableActor({"DeviceButton_7", "DeviceButton_8"}, self, self:GetChild("Border"))
		end,
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:halign(0.5):zoom(0.35)
				self:settextf("%+5.2f (%5.2f%%)", 0, targetGoalPct)
				self:diffuse(HVColor.GetGoalTrackerColor("positive"))
			end,
			JudgmentMessageCommand = function(self, msg)
				self.msg = msg
				self:queuecommand("Update")
			end,
			UpdateCommand = function(self)
				local msg = self.msg
				if not msg then return end
				local tDiff = msg.WifeDifferential
				local displayTarget = targetGoalPct

				-- In PB or PB Replay mode, use the PB goal/differential if available
				if (pacemakerMode == "PB" or pacemakerMode == "PBReplay") and msg.WifePBGoal ~= nil then
					tDiff = msg.WifePBDifferential
					displayTarget = msg.WifePBGoal * 100
				end

				if tDiff and tDiff >= 0 then
					self:diffuse(HVColor.GetGoalTrackerColor("positive"))
				else
					self:diffuse(HVColor.GetGoalTrackerColor("negative"))
				end
				self:settextf("%+5.2f (%5.2f%%)", tDiff or 0, displayTarget)
			end,

		}
		,
		MovableBorder(130, 18, 1, 0, 0)
	}
end
