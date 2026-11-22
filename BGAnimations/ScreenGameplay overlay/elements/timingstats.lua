local gameplay = ...
local gameplayCoord = gameplay.gameplayCoord
local gameplaySize = gameplay.gameplaySize
local minimalisticHUDVisible = gameplay.minimalisticHUDVisible
local animateGameplayHUDVisibility = gameplay.animateGameplayHUDVisibility
local mainText = gameplay.mainText

return Def.ActorFrame {
	Name = "NotefieldMean",
	InitCommand = function(self)
		self:xy(gameplayCoord("DisplayMeanX"), gameplayCoord("DisplayMeanY")):zoom(gameplaySize("DisplayMeanZoom")):diffusealpha(0)
		-- Check if notefield stat should be shown
		local statType = HV.GetNotefieldStat()
		local showStat = statType ~= "Off" and not gameplay.isSync
		self.HVBaseVisible = showStat
		self:visible(minimalisticHUDVisible(showStat))
	end,
	HV_MinimalisticModeChangedMessageCommand = function(self, params)
		animateGameplayHUDVisibility(self, minimalisticHUDVisible(self.HVBaseVisible, params and params.Enabled))
	end,
	OnCommand = function(self)
		setMovableActor({"DeviceButton_m", "DeviceButton_comma"}, self, self:GetChild("Border"))
		self:linear(0.2):diffusealpha(0.8)
	end,

		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:zoom(0.35):diffuse(mainText)
				local statType = HV.GetNotefieldStat()
				self.statType = statType
				self.currWifePoints = 0
				self.leftOffsetSumMs = 0
				self.leftOffsetCount = 0
				self.rightOffsetSumMs = 0
				self.rightOffsetCount = 0
				self.middleOffsetSumMs = 0
				self.middleOffsetCount = 0
				-- Implement mean like Rebirth does
				self.meansum = 0
				self.meancount = 0
				self.lastTapOffsetMs = nil
				-- Implement SD like Rebirth does
				self.runningmean = 0
				self.runningvariance = 0
				self.tapcount = 0

				if statType == "J4" then
					self:settext("100.0000%")
				elseif statType == "MARatio" then
					self:settext("0.00:1")
				elseif statType == "DeltaHand" then
					self:settext("0.0000%")
				else
					self:settext("0.00ms")
				end
			end,
			JudgmentMessageCommand = function(self, msg)
				if msg.Player ~= GAMESTATE:GetMasterPlayerNumber() then return end
				if msg.HoldNoteScore then return end -- Skip holds, handled in HoldNoteScoreMessageCommand
				if self.statType == "J4" then
					if msg.TapNoteScore and msg.TapNoteScore ~= "TapNoteScore_AvoidMine" and msg.TapNoteScore ~= "TapNoteScore_CheckpointHit" then
						local ts = ms.JudgeScalers[4] or 1.0
						if msg.TapNoteOffset then
							self.currWifePoints = self.currWifePoints + wife3(math.abs(msg.TapNoteOffset) * 1000, ts, "Wife3")
						elseif msg.TapNoteScore == "TapNoteScore_Miss" then
							self.currWifePoints = self.currWifePoints - 5.5
						elseif msg.TapNoteScore == "TapNoteScore_HitMine" then
							self.currWifePoints = self.currWifePoints - 7.0
						elseif msg.TapNoteScore ~= "TapNoteScore_None" then
							self.currWifePoints = self.currWifePoints + 2.0
						end
					end
				elseif self.statType == "TapOffset" then
					if msg.TapNoteOffset ~= nil and msg.TapNoteScore ~= "TapNoteScore_Miss" then
						self.lastTapOffsetMs = msg.TapNoteOffset * 1000
					end
				elseif self.statType == "StdDev" then
			        if msg.TapNoteOffset ~= nil and msg.TapNoteScore ~= "TapNoteScore_Miss" then
			            local offset = msg.TapNoteOffset * 1000
			            -- Implementation inspired by Rebirth's displaystddev.lua
			            self.tapcount = self.tapcount + 1
			            local delta = offset - self.runningmean
			            self.runningmean = self.runningmean + (delta / self.tapcount)
			            local delta2 = offset - self.runningmean
			            self.runningvariance = self.runningvariance + (delta * delta2)
			        end
				elseif self.statType == "Mean" then
					if msg.TapNoteOffset ~= nil and msg.TapNoteScore ~= "TapNoteScore_Miss" then
						self.meansum = self.meansum + msg.TapNoteOffset * 1000
						self.meancount = self.meancount + 1
					end
				elseif self.statType == "DeltaHand" then
					if msg.TapNoteOffset and msg.TapNoteScore and msg.TapNoteScore ~= "TapNoteScore_AvoidMine" and msg.TapNoteScore ~= "TapNoteScore_CheckpointHit" then
						local track = msg.FirstTrack
						if track == nil then track = msg.Track end
						if track ~= nil then
							local judge = (PREFSMAN:GetPreference("SortBySSRNormPercent") and 4) or GetTimingDifficulty()
							local ts = (ms.JudgeScalers and ms.JudgeScalers[judge]) or 1.0
							local pts = wife3(math.abs(msg.TapNoteOffset) * 1000, ts, "Wife3")

							local cols = 4
							local style = GAMESTATE:GetCurrentStyle()
							if style and style.ColumnsPerPlayer then cols = style:ColumnsPerPlayer() end
							local middleColumn = (cols - 1) / 2.0

							if track < middleColumn then
								self.leftOffsetSumMs = self.leftOffsetSumMs + pts
								self.leftOffsetCount = self.leftOffsetCount + 1
							elseif track > middleColumn then
								self.rightOffsetSumMs = self.rightOffsetSumMs + pts
								self.rightOffsetCount = self.rightOffsetCount + 1
							else
								-- Middle column (odd keymodes)
								self.middleOffsetSumMs = (self.middleOffsetSumMs or 0) + pts
								self.middleOffsetCount = (self.middleOffsetCount or 0) + 1
							end
						end
					end
				end
				self:queuecommand("Update")
			end,
			HoldNoteScoreMessageCommand = function(self, msg)
				if msg.Player ~= GAMESTATE:GetMasterPlayerNumber() then return end
				if self.statType == "J4" then
					-- The engine applies the hold penalty even if the head was completely missed
					if msg.HoldNoteScore == "HoldNoteScore_LetGo" or msg.HoldNoteScore == "HoldNoteScore_MissedHold" then
						self.currWifePoints = self.currWifePoints - 4.5
					end
				end
				self:queuecommand("Update")
			end,
			RollNoteScoreMessageCommand = function(self, msg)
				if msg.Player ~= GAMESTATE:GetMasterPlayerNumber() then return end
				if self.statType == "J4" then
					if msg.RollNoteScore == "RollNoteScore_LetGo" or msg.RollNoteScore == "RollNoteScore_MissedRoll" then
						self.currWifePoints = self.currWifePoints - 4.5
					end
				end
				self:queuecommand("Update")
			end,
			UpdateCommand = function(self)
				local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats()
				if not pss then return end
				local ps = GAMESTATE:GetPlayerState(gameplay.player)

				if self.statType == "J4" then
					local notesPassed = pss:GetTapNoteScores("TapNoteScore_W1") +
									   pss:GetTapNoteScores("TapNoteScore_W2") +
									   pss:GetTapNoteScores("TapNoteScore_W3") +
									   pss:GetTapNoteScores("TapNoteScore_W4") +
									   pss:GetTapNoteScores("TapNoteScore_W5") +
									   pss:GetTapNoteScores("TapNoteScore_Miss")
					local maxPoints = notesPassed * 2
					if maxPoints > 0 then
						local j4 = math.min((self.currWifePoints / maxPoints) * 100, 100)
						self:settextf("%.4f%%", j4)
					elseif self.currWifePoints < 0 then
						-- Show penalty relative to total song max points until first tap
						local raw = (gameplay.maxPoints + self.currWifePoints) / gameplay.maxPoints
						self:settextf("%.4f%%", raw * 100)
					else
						self:settext("0.0000%")
					end
				elseif self.statType == "TapOffset" then
					self:settextf("%+.2fms", self.lastTapOffsetMs or 0)
				elseif self.statType == "StdDev" then
					if self.tapcount > 1 then
						self:settextf("%.2fms", math.sqrt(self.runningvariance / (self.tapcount - 1)))
				    else
				        self:settext("0.00ms")
				    end
				elseif self.statType == "MARatio" then
					local marv = pss:GetTapNoteScores("TapNoteScore_W1") or 0
					local perf = pss:GetTapNoteScores("TapNoteScore_W2") or 0
					if perf > 0 then
						self:settextf("%.2f:1", marv / perf)
					elseif marv > 0 then
						self:settext("∞")
					else
						self:settext("0.00:1")
					end
				elseif self.statType == "DeltaHand" then
					local cols = 4
					local style = GAMESTATE:GetCurrentStyle()
					if style and style.ColumnsPerPlayer then cols = style:ColumnsPerPlayer() end
					local oddColumns = (cols % 2) ~= 0

					local leftTaps, rightTaps = self.leftOffsetCount or 0, self.rightOffsetCount or 0
					local middleTaps = self.middleOffsetCount or 0
					local leftScore = leftTaps > 0 and (self.leftOffsetSumMs / (leftTaps * 2)) or 0
					local rightScore = rightTaps > 0 and (self.rightOffsetSumMs / (rightTaps * 2)) or 0
					local middleScore = middleTaps > 0 and ((self.middleOffsetSumMs or 0) / (middleTaps * 2)) or 0

					if oddColumns then
						if leftTaps == 0 and rightTaps == 0 and middleTaps == 0 then
							self:settext("0.0000%")
						else
							local scores = {L = leftScore, M = middleScore, R = rightScore}
							local minScore = math.min(leftScore, middleScore, rightScore)
							local maxScore = math.max(leftScore, middleScore, rightScore)
							local delta = (maxScore - minScore) * 100
							local sorted = {"L", "M", "R"}
							table.sort(sorted, function(a, b) return scores[a] > scores[b] end)
							local symbol = table.concat(sorted, ">")
							self:settextf("%s %.4f%%", symbol, delta)
						end
					else
						if leftTaps > 0 and rightTaps > 0 then
							local delta = math.abs(leftScore - rightScore) * 100
							local symbol = leftScore > rightScore and "> " or "< "
							self:settextf("%s%.4f%%", symbol, delta)
						else
							self:settext("0.0000%")
						end
					end
				else -- mean
					if self.meancount > 0 then
				        self:settextf("%.2fms", self.meansum / self.meancount)
				    else
				        self:settext("0.00ms")
				    end
				end
			end,
			PracticeModeResetMessageCommand = function(self)
				self.currWifePoints = 0
				self.leftOffsetSumMs, self.leftOffsetCount = 0, 0
				self.rightOffsetSumMs, self.rightOffsetCount = 0, 0
				self.middleOffsetSumMs, self.middleOffsetCount = 0, 0
				self.meansum, self.meancount = 0, 0
				self.tapcount = 0
				self.runningmean = 0
				self.runningvariance = 0
				self:queuecommand("Update")
			end,
			PracticeModeReloadMessageCommand = function(self)
				self.currWifePoints = 0
				self.leftOffsetSumMs, self.leftOffsetCount = 0, 0
				self.rightOffsetSumMs, self.rightOffsetCount = 0, 0
				self.middleOffsetSumMs, self.middleOffsetCount = 0, 0
				self.meansum, self.meancount = 0, 0
				self:queuecommand("Update")
			end

		},
		MovableBorder(100, 18, 1, 0, 0)
	}
