local gameplay = ...
local gameplayCoord = gameplay.gameplayCoord
local gameplaySize = gameplay.gameplaySize
local minimalisticHUDVisible = gameplay.minimalisticHUDVisible
local animateGameplayHUDVisibility = gameplay.animateGameplayHUDVisibility
local subText = gameplay.subText
local brightText = gameplay.brightText
local ThemePrefs = HV.LegacyPrefs

local showCurrentWife = HV.ShowCurrentWife() and not gameplay.isSync

if showCurrentWife then
return Def.ActorFrame {
	Name = "CenteredScore",
	InitCommand = function(self)
		self:xy(gameplayCoord("DisplayPercentX"), gameplayCoord("DisplayPercentY")):zoom(gameplaySize("DisplayPercentZoom")):diffusealpha(0.8)
		self:visible(minimalisticHUDVisible(showCurrentWife))
	end,
	HV_MinimalisticModeChangedMessageCommand = function(self, params)
		animateGameplayHUDVisibility(self, minimalisticHUDVisible(showCurrentWife, params and params.Enabled))
	end,
	OnCommand = function(self)
		setMovableActor({"DeviceButton_w", "DeviceButton_e"}, self, self:GetChild("Border"))
	end,

	LoadFont("Common Normal") .. {
		Name = "EmulatedJudgeLabel",
		InitCommand = function(self)
			self:y(-15):zoom(0.30):diffuse(subText):diffusealpha(0)
			if HV.ScoreEmulationEnabled() and not (HV.IsReplayPlayback and HV.IsReplayPlayback()) then
				self:settext(HV.ScoreEmulationLabel()):diffusealpha(0.8)
			end
		end,
	},

	LoadFont("Common Normal") .. {
		Name = "ScoreValue",
		InitCommand = function(self)
			self:zoom(0.45):diffuse(brightText):diffusealpha(0.7)
			self.currWifePoints = 0
			self.currScoredTaps = 0
			self.emulatedPoints = 0
			self.emulatedMaxPoints = 0
			self.replayWifePoints = 0
			self.replayMaxPoints = 0
			local scoreMode = ThemePrefs.Get("HV_ScoreDisplayMode") or "Normal"
			if scoreMode == "Subtractive" then
				self:settext("100.0000%")
			else
				self:settext("0.0000%")
			end
		end,
		OnCommand = function(self)
			self:queuecommand("UpdateAutoplay")
		end,
		UpdateAutoplayCommand = function(self)
			if getAutoplay and getAutoplay() ~= 0 then
				self:queuecommand("Update")
			end
			self:sleep(0.05):queuecommand("UpdateAutoplay")
		end,
		JudgmentMessageCommand = function(self, msg)
			if msg.Player ~= GAMESTATE:GetMasterPlayerNumber() then return end
			if msg.HoldNoteScore then return end -- Skip holds, handled in HoldNoteScoreMessageCommand
			if msg.TapNoteScore and msg.TapNoteScore ~= "TapNoteScore_AvoidMine" and msg.TapNoteScore ~= "TapNoteScore_CheckpointHit" and msg.TapNoteScore ~= "TapNoteScore_CheckpointMiss" then
				if HV.IsReplayPlayback and HV.IsReplayPlayback() then
					if msg.TapNoteScore ~= "TapNoteScore_HitMine" then
						self.replayMaxPoints = self.replayMaxPoints + 2
					end
					if msg.TapNoteOffset then
						self.replayWifePoints = self.replayWifePoints + wife3(math.abs(msg.TapNoteOffset) * 1000, gameplay.judgeScale, "Wife3")
					elseif msg.TapNoteScore == "TapNoteScore_Miss" then
						self.replayWifePoints = self.replayWifePoints - 5.5
					elseif msg.TapNoteScore == "TapNoteScore_HitMine" then
						self.replayWifePoints = self.replayWifePoints - 7
					else
						self.replayWifePoints = self.replayWifePoints + 2
					end
				end
				if HV.ScoreEmulationEnabled and HV.ScoreEmulationEnabled() then
					local selection = HV.ScoreEmulationSelection()
					if msg.TapNoteScore ~= "TapNoteScore_HitMine" then
						self.emulatedMaxPoints = self.emulatedMaxPoints + HV.GetCosmeticTapMax(selection)
					end
					self.emulatedPoints = self.emulatedPoints + HV.GetCosmeticPointValue(selection, msg.TapNoteOffset and math.abs(msg.TapNoteOffset) * 1000 or nil, msg.TapNoteScore)
				end
				if msg.TapNoteOffset then
					self.currWifePoints = self.currWifePoints + wife3(math.abs(msg.TapNoteOffset) * 1000, gameplay.judgeScale, "Wife3")
					self.currScoredTaps = self.currScoredTaps + 1
				elseif msg.TapNoteScore == "TapNoteScore_Miss" then
					self.currWifePoints = self.currWifePoints - 5.5
					self.currScoredTaps = self.currScoredTaps + 1
				elseif msg.TapNoteScore == "TapNoteScore_HitMine" then
					self.currWifePoints = self.currWifePoints - 7.0
				elseif msg.TapNoteScore ~= "TapNoteScore_None" then
					self.currWifePoints = self.currWifePoints + 2.0
					self.currScoredTaps = self.currScoredTaps + 1
				end
			end
			self:playcommand("Update")
		end,
		HoldNoteScoreMessageCommand = function(self, msg)
			if msg.Player ~= GAMESTATE:GetMasterPlayerNumber() then return end
			-- The engine applies the hold penalty even if the head was completely missed
			if msg.HoldNoteScore == "HoldNoteScore_LetGo" or msg.HoldNoteScore == "HoldNoteScore_MissedHold" then
				if HV.IsReplayPlayback and HV.IsReplayPlayback() then
					self.replayWifePoints = self.replayWifePoints - 4.5
				end
				if HV.ScoreEmulationEnabled and HV.ScoreEmulationEnabled() then
					self.emulatedPoints = self.emulatedPoints + HV.GetCosmeticHoldPointValue(HV.ScoreEmulationSelection(), msg.HoldNoteScore)
				end
				self:playcommand("Update")
			end
		end,
		RollNoteScoreMessageCommand = function(self, msg)
			if msg.Player ~= GAMESTATE:GetMasterPlayerNumber() then return end
			if msg.RollNoteScore == "RollNoteScore_LetGo" or msg.RollNoteScore == "RollNoteScore_MissedRoll" then
				if HV.IsReplayPlayback and HV.IsReplayPlayback() then
					self.replayWifePoints = self.replayWifePoints - 4.5
				end
				if HV.ScoreEmulationEnabled and HV.ScoreEmulationEnabled() then
					self.emulatedPoints = self.emulatedPoints + HV.GetCosmeticHoldPointValue(HV.ScoreEmulationSelection(), msg.RollNoteScore)
				end
				self:playcommand("Update")
			end
		end,
		HV_PointsUpdateMessageCommand = function(self)
			self:playcommand("Update")
		end,
		UpdateCommand = function(self)
			local wifePct
			local scoreMode = ThemePrefs.Get("HV_ScoreDisplayMode") or "Normal"
			local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats()
			local isAutoplay = getAutoplay and getAutoplay() ~= 0
			local isReplay = HV.IsReplayPlayback and HV.IsReplayPlayback()

			-- Replay playback must reflect the engine's live replay stats. Do not
			-- apply this theme's cumulative or subtractive display calculations.
			if isReplay then
				if self.replayMaxPoints > 0 then
					wifePct = (self.replayWifePoints / self.replayMaxPoints) * 100
				else
					wifePct = 0
				end
			elseif HV.ScoreEmulationEnabled and HV.ScoreEmulationEnabled() and pss then
				if self.emulatedMaxPoints > 0 then
					wifePct = (self.emulatedPoints / self.emulatedMaxPoints) * 100
				else
					wifePct = 0
				end
			elseif isAutoplay and pss then
				local notesPassed = pss:GetTapNoteScores("TapNoteScore_W1") +
								   pss:GetTapNoteScores("TapNoteScore_W2") +
								   pss:GetTapNoteScores("TapNoteScore_W3") +
								   pss:GetTapNoteScores("TapNoteScore_W4") +
								   pss:GetTapNoteScores("TapNoteScore_W5") +
								   pss:GetTapNoteScores("TapNoteScore_Miss")
				local currentMaxPoints = notesPassed * 2
				if currentMaxPoints > 0 and type(pss.GetWifePoints) == "function" then
					local ok, value = pcall(pss.GetWifePoints, pss)
					value = ok and tonumber(value) or nil
					if value then wifePct = math.min((value / currentMaxPoints) * 100, 100) end
				end
				if not wifePct and type(pss.GetWifeScore) == "function" then
					local ok, value = pcall(pss.GetWifeScore, pss)
					value = ok and tonumber(value) or nil
					if value then wifePct = value * 100 end
				end
			elseif scoreMode == "Subtractive" then
				wifePct = ((gameplay.maxPoints - gameplay.pointsLost) / gameplay.maxPoints) * 100
			else
				if pss then
					local notesPassed = pss:GetTapNoteScores("TapNoteScore_W1") +
						pss:GetTapNoteScores("TapNoteScore_W2") +
						pss:GetTapNoteScores("TapNoteScore_W3") +
						pss:GetTapNoteScores("TapNoteScore_W4") +
						pss:GetTapNoteScores("TapNoteScore_W5") +
						pss:GetTapNoteScores("TapNoteScore_Miss")
					local ngCount = pss:GetHoldNoteScores("HoldNoteScore_LetGo") +
						pss:GetHoldNoteScores("HoldNoteScore_MissedHold")
					if type(pss.GetRollNoteScores) == "function" then
						ngCount = ngCount + pss:GetRollNoteScores("RollNoteScore_LetGo") +
							pss:GetRollNoteScores("RollNoteScore_MissedRoll")
					end
					local currentMaxPoints = self.currScoredTaps * 2
					if currentMaxPoints > 0 then
						wifePct = math.min(((self.currWifePoints - ngCount * 4.5) / currentMaxPoints) * 100, 100)
					elseif self.currWifePoints - ngCount * 4.5 < 0 then
						wifePct = ((self.currWifePoints - ngCount * 4.5) / 2) * 100
					else
						wifePct = 100.0000
					end
				end
			end
			if not wifePct then return end
			self:settext(string.format("%.4f%%", wifePct))

			-- Use standard Etterna grade tiers and theme colors
			local tier = getEtternaGrade(wifePct)
			self:diffuse(HVColor.GetGradeColor(tier)):diffusealpha(0.7)
		end,

	}
	,
	MovableBorder(110, 20, 1, 0, 0)
}
end
