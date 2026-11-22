local gameplay = ...
local gameplayCoord = gameplay.gameplayCoord
local gameplaySize = gameplay.gameplaySize
local ThemePrefs = HV.LegacyPrefs

return Def.ActorFrame {
		Name = "AutofailDisplay",
		InitCommand = function(self)
			self:xy(gameplayCoord("AutoFailDisplayX"), gameplayCoord("AutoFailDisplayY")):zoom(gameplaySize("AutoFailDisplayZoom"))
			self:visible(false)
		end,
		OnCommand = function(self)
			setMovableActor({"DeviceButton_g", "DeviceButton_h"}, self, self:GetChild("Border"))
		end,
		BeginCommand = function(self)
			self:queuecommand("Refresh")
		end,
		ThemePrefChangedMessageCommand = function(self, params)
			if not params or not params.Name then return end
			if params.Name:find("HV_AutoFail") then
				self:queuecommand("Refresh")
			end
		end,
		HV_PointsUpdateMessageCommand = function(self)
			self:queuecommand("Refresh")
		end,
		RefreshCommand = function(self)
			local actionMode = ThemePrefs.Get("HV_AutoFailMode")
			if GAMESTATE:IsPracticeMode() or actionMode == "Off" or not actionMode then
				self:visible(false)
				return
			end
			self:visible(true)
			local condition = ThemePrefs.Get("HV_AutoFailCondition")
			local iconWife = self:GetChild("IconWife")
			local iconPB = self:GetChild("IconPB")
			local iconTarget = self:GetChild("IconTarget")
			if iconWife then iconWife:visible(condition == "Wife Percent") end
			if iconTarget then iconTarget:visible(condition == "Judgement Count" or condition == "Sync to Goal") end
			if iconPB then iconPB:visible(condition == "Personal Best") end
			if iconTarget then iconTarget:visible(condition == "Judgement Count" or condition == "Sync to Goal") end
			local txt = self:GetChild("Value")
			if not txt then return end
			local display = ""
			local c = color("1,1,1,1")
			if condition == "Wife Percent" then
				local threshold = tonumber(ThemePrefs.Get("HV_AutoFailThreshold_Wife")) or 93.00
				local subtractiveWife = ((gameplay.maxPoints - gameplay.pointsLost) / gameplay.maxPoints) * 100
				display = string.format("%.4f%%", threshold)
				txt:xy(11, 20)
			elseif condition == "Sync to Goal" then
				local threshold = tonumber(ThemePrefs.Get("HV_PacemakerTargetGoal")) or 93.00
				if GetDisplayScore() then
					threshold = getJ4NormalizedPercentage(GetDisplayScore())
				end
				display = string.format("%.4f%%", threshold)
				txt:xy(11, 20)
			elseif condition == "Personal Best" then
				if not gameplay.pbThreshold or gameplay.pbThreshold == 0 then
					local best = GetDisplayScore()
					if best then
						gameplay.pbThreshold = getJ4NormalizedPercentage(best)
					else
						gameplay.pbThreshold = tonumber(ThemePrefs.Get("HV_AutoFailThreshold_Wife")) or 93.00
					end
				end
				local subtractiveWife = ((gameplay.maxPoints - gameplay.pointsLost) / gameplay.maxPoints) * 100
				display = string.format("%.4f%%", gameplay.pbThreshold or 0)
				txt:xy(11, 20)
			elseif condition == "Judgement Count" then
				local limit = tonumber(ThemePrefs.Get("HV_AutoFailThreshold_Count")) or 10
				local judgePref = ThemePrefs.Get("HV_AutoFailJudgement") or "Miss"
				local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats()
				local currentCount = 0
				if pss then
					local order = {"W2","W3","W4","W5","Miss"}
					local idx = 5
					for i=1, #order do
						if order[i] == judgePref then idx = i break end
					end
					for i=idx, #order do
						currentCount = currentCount + pss:GetTapNoteScores("TapNoteScore_" .. order[i])
					end
				end
				local remaining = math.max(0, limit - currentCount)
				display = tostring(remaining)
				c = HVColor.GetJudgmentColor(judgePref)
				txt:xy(24, 20)
			end
			txt:settext(display)
			txt:diffuse(c)
		end,
		Def.Sprite {
			Name = "IconWife",
			Texture = THEME:GetPathG("", "wife.png"),
			InitCommand = function(self)
				self:halign(0):valign(0.5):xy(0, 0):zoom(0.20):visible(false)
			end
		},
		Def.Sprite {
			Name = "IconPB",
			Texture = THEME:GetPathG("", "pb.png"),
			InitCommand = function(self)
				self:halign(0):valign(0.5):xy(0, 0):zoom(0.20):visible(false)
			end
		},
		Def.Sprite {
			Name = "IconTarget",
			Texture = THEME:GetPathG("", "target.png"),
			InitCommand = function(self)
				self:halign(0):valign(0.5):xy(0, 0):zoom(0.20):visible(false)
			end
		},
		LoadFont("Common Normal") .. {
			Name = "Value",
			InitCommand = function(self)
				self:halign(0):valign(0.5):xy(11, 20):zoom(0.55)
				self:settext("")
			end
		},
		MovableBorder(64, 64, 1, 32, 0)
	}
