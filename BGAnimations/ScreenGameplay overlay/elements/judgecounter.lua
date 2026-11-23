local gameplay = ...
local gameplayCoord = gameplay.gameplayCoord
local minimalisticHUDVisible = gameplay.minimalisticHUDVisible
local animateGameplayHUDVisibility = gameplay.animateGameplayHUDVisibility
local dimText = gameplay.dimText
local subText = gameplay.subText
local mainText = gameplay.mainText

local judgmentColors = {
	HVColor.GetJudgmentColor("W1"),
	HVColor.GetJudgmentColor("W2"),
	HVColor.GetJudgmentColor("W3"),
	HVColor.GetJudgmentColor("W4"),
	HVColor.GetJudgmentColor("W5"),
	HVColor.GetJudgmentColor("Miss")
}
local judgmentLabels = {
	THEME:GetString("TapNoteScore", "W1"),
	THEME:GetString("TapNoteScore", "W2"),
	THEME:GetString("TapNoteScore", "W3"),
	THEME:GetString("TapNoteScore", "W4"),
	THEME:GetString("TapNoteScore", "W5"),
	THEME:GetString("TapNoteScore", "Miss")
}

local judgmentTNS = {
	"TapNoteScore_W1", "TapNoteScore_W2", "TapNoteScore_W3",
	"TapNoteScore_W4", "TapNoteScore_W5", "TapNoteScore_Miss"
}

if HV.EmulateRidiculousEnabled() then
	table.insert(judgmentColors, 1, HVColor.GetJudgmentColor("Ridiculous"))
	table.insert(judgmentLabels, 1, THEME:GetString("TapNoteScore", "Ridiculous"))
	table.insert(judgmentTNS, 1, "Ridiculous")
end

local function getGameplayJudgmentCount(pss, judgeName)
	if judgeName == "Ridiculous" then return gameplay.ridiculousCount end
	local count = pss:GetTapNoteScores(judgeName)
	if judgeName == "TapNoteScore_W1" and HV.EmulateRidiculousEnabled() then
		count = count - gameplay.ridiculousCount
	end
	return count
end

local colSpacing = 70
local showJudgeCounter = HV.ShowJudgeCounter()
local tallyX = SCREEN_CENTER_X + 160
local tallyY = SCREEN_HEIGHT - 176

if showJudgeCounter and not gameplay.isSync then
return Def.ActorFrame {
	Name = "TallyAndMetrics",
	InitCommand = function(self)
		self:xy(gameplayCoord("JudgeCounterX"), gameplayCoord("JudgeCounterY")):diffusealpha(0.8)
		self:visible(minimalisticHUDVisible(showJudgeCounter))
	end,
	HV_MinimalisticModeChangedMessageCommand = function(self, params)
		animateGameplayHUDVisibility(self, minimalisticHUDVisible(showJudgeCounter, params and params.Enabled))
	end,
	OnCommand = function(self)
		setMovableActor({"DeviceButton_p"}, self, self:GetChild("Border"))
	end,

	-- COLUMN 1: Judgments + OK/NG
	Def.ActorFrame {
		Name = "Column1_Judgments",

		-- Loop through standard judgments (W1-Miss)
		(function()
			local g = Def.ActorFrame{}
			for i, label in ipairs(judgmentLabels) do
				g[#g+1] = Def.ActorFrame {
					InitCommand = function(self)
						self:y((i - 1) * 16)
					end,

					LoadFont("Common Normal") .. {
						InitCommand = function(self)
							self:halign(0):valign(0):zoom(0.34):diffuse(judgmentColors[i]):diffusealpha(0.8)
							self:settext(label)
						end
					},

					LoadFont("Common Normal") .. {
						Name = "TallyCount_" .. label,
						InitCommand = function(self)
							self:halign(1):valign(0):x(60):zoom(0.34):diffuse(mainText):diffusealpha(0.8)
							self:settext("0")
						end,
						JudgmentMessageCommand = function(self)
							self:queuecommand("Update")
						end,
						UpdateCommand = function(self)
							local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats()
							if pss then
								self:settext(getGameplayJudgmentCount(pss, judgmentTNS[i]))
							end
						end,
						PracticeModeResetMessageCommand = function(self)
							if judgmentTNS[i] == "Ridiculous" then gameplay.ridiculousCount = 0 end
							self:settext("0")
						end,
						PracticeModeReloadMessageCommand = function(self)
							if judgmentTNS[i] == "Ridiculous" then gameplay.ridiculousCount = 0 end
							self:settext("0")
						end
					}
				}
			end
			return g
		end)(),

		-- OK / NG counters
		Def.ActorFrame {
			Name = "OKNGDisplay",
			InitCommand = function(self)
				self:y(#judgmentLabels * 16 + 4)
			end,

			LoadFont("Common Normal") .. {
				InitCommand = function(self)
					self:halign(0):valign(0):zoom(0.34):diffuse(HVColor.GetJudgmentColor("Held")):diffusealpha(0.8)
					self:settext(THEME:GetString("HoldNoteScore", "OK"))
				end
			},
			LoadFont("Common Normal") .. {
				Name = "OKCount",
				InitCommand = function(self)
					self:halign(1):valign(0):x(60):zoom(0.34):diffuse(mainText):diffusealpha(0.8)
					self:settext("0")
				end,
				JudgmentMessageCommand = function(self)
					self:queuecommand("Update")
				end,
				UpdateCommand = function(self)
					local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats()
					if pss then
						local ok = pss:GetHoldNoteScores("HoldNoteScore_Held")
						self:settext(tostring(ok))
					end
				end,
				PracticeModeResetMessageCommand = function(self) self:settext("0") end,
				PracticeModeReloadMessageCommand = function(self) self:settext("0") end
			},

			LoadFont("Common Normal") .. {
				InitCommand = function(self)
					self:halign(0):valign(0):y(16):zoom(0.34):diffuse(HVColor.GetJudgmentColor("LetGo")):diffusealpha(0.8)
					self:settext(THEME:GetString("HoldNoteScore", "NG"))
				end
			},
			LoadFont("Common Normal") .. {
				Name = "NGCount",
				InitCommand = function(self)
					self:halign(1):valign(0):x(60):y(16):zoom(0.34):diffuse(mainText):diffusealpha(0.8)
					self:settext("0")
				end,
				JudgmentMessageCommand = function(self)
					self:queuecommand("Update")
				end,
				UpdateCommand = function(self)
					local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats()
					if pss then
						local ng = pss:GetHoldNoteScores("HoldNoteScore_LetGo")
						self:settext(tostring(ng))
					end
				end,
				PracticeModeResetMessageCommand = function(self) self:settext("0") end,
				PracticeModeReloadMessageCommand = function(self) self:settext("0") end
			}
		}
	},

	-- COLUMN 2: Performance Metrics (aligned to the right of Column 1)
	Def.ActorFrame {
		Name = "Column2_Metrics",
		InitCommand = function(self)
			self:x(colSpacing)
			-- Hide metrics in Simple mode
			if HV.GetJudgmentTallyMode() == "Simple" then
				self:visible(false)
			end
		end,

		-- MA Ratio (W1/W2)
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:halign(0):valign(0):zoom(0.34):diffuse(dimText)
				self:settext("MA Ratio")
			end
		},
		LoadFont("Common Normal") .. {
			Name = "MARatioValue",
			InitCommand = function(self)
				self:halign(1):valign(0):x(65):zoom(0.34):diffuse(subText)
				self:settext("0.00:1")
			end,
			JudgmentMessageCommand = function(self)
				self:queuecommand("Update")
			end,
			UpdateCommand = function(self)
				local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats()
				if pss then
					local w1 = pss:GetTapNoteScores("TapNoteScore_W1")
					local w2 = pss:GetTapNoteScores("TapNoteScore_W2")
					local ratio = 0
					if w2 > 0 then
						ratio = w1 / w2
						self:settext(string.format("%.2f:1", ratio))
					elseif w1 > 0 then
						self:settext("inf:1")
					else
						self:settext("0.00:1")
					end
				end
			end,
			PracticeModeResetMessageCommand = function(self) self:settext("0.00:1") end,
			PracticeModeReloadMessageCommand = function(self) self:settext("0.00:1") end
		},

		-- PA Ratio (W2/W3)
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:halign(0):valign(0):y(16):zoom(0.34):diffuse(dimText)
				self:settext("PA Ratio")
			end
		},
		LoadFont("Common Normal") .. {
			Name = "PARatioValue",
			InitCommand = function(self)
				self:halign(1):valign(0):x(65):y(16):zoom(0.34):diffuse(subText)
				self:settext("0.00:1")
			end,
			JudgmentMessageCommand = function(self)
				self:queuecommand("Update")
			end,
			UpdateCommand = function(self)
				local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats()
				if pss then
					local w2 = pss:GetTapNoteScores("TapNoteScore_W2")
					local w3 = pss:GetTapNoteScores("TapNoteScore_W3")
					local ratio = 0
					if w3 > 0 then
						ratio = w2 / w3
						self:settext(string.format("%.2f:1", ratio))
					elseif w2 > 0 then
						self:settext("inf:1")
					else
						self:settext("0.00:1")
					end
				end
			end,
			PracticeModeResetMessageCommand = function(self) self:settext("0.00:1") end,
			PracticeModeReloadMessageCommand = function(self) self:settext("0.00:1") end
		},

		-- Longest Combo
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:halign(0):valign(0):y(32):zoom(0.34):diffuse(dimText)
				self:settext("Longest")
			end
		},
		LoadFont("Common Normal") .. {
			Name = "MaxComboValue",
			InitCommand = function(self)
				self:halign(1):valign(0):x(65):y(32):zoom(0.34):diffuse(subText)
				self:settext("0")
			end,
			JudgmentMessageCommand = function(self)
				self:queuecommand("Update")
			end,
			UpdateCommand = function(self)
				local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats()
				if pss then
					self:settext(tostring(pss:MaxCombo()))
				end
			end,
			PracticeModeResetMessageCommand = function(self) self:settext("0") end,
			PracticeModeReloadMessageCommand = function(self) self:settext("0") end
		},

		-- Std Dev
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:halign(0):valign(0):y(48):zoom(0.34):diffuse(dimText)
				self:settext("SD")
			end
		},
		LoadFont("Common Normal") .. {
			Name = "SDValue",
			InitCommand = function(self)
				self:halign(1):valign(0):x(65):y(48):zoom(0.34):diffuse(subText)
				self:settext("0.00")
				-- Optimization
				self.runningmean = 0
				self.runningvariance = 0
				self.tapcount = 0
			end,
			JudgmentMessageCommand = function(self,msg)
				if msg.TapNoteOffset ~= nil and msg.TapNoteScore ~= "TapNoteScore_Miss" then
		            local offset = msg.TapNoteOffset * 1000
		            -- Implementation inspired by Rebirth's displaystddev.lua
		            self.tapcount = self.tapcount + 1
		            local delta = offset - self.runningmean
		            self.runningmean = self.runningmean + (delta / self.tapcount)
		            local delta2 = offset - self.runningmean
		            self.runningvariance = self.runningvariance + (delta * delta2)
					self:queuecommand("Update")
				end
			end,
			UpdateCommand = function(self)
				if self.tapcount > 1 then
					self:settextf("%.2f", math.sqrt(self.runningvariance / (self.tapcount - 1)))
			    else
			        self:settext("0.00ms")
			    end
			end,
			PracticeModeResetMessageCommand = function(self)
			    self.tapcount = 0
			    self.runningmean = 0
			    self.runningvariance = 0
			    self:settext("0.00")
			end,

			PracticeModeReloadMessageCommand = function(self)
			    self.tapcount = 0
			    self.runningmean = 0
			    self.runningvariance = 0
			    self:settext("0.00")
			end
		},

		-- Largest Offset
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:halign(0):valign(0):y(64):zoom(0.34):diffuse(dimText)
				self:settext("Max")
			end
		},
		LoadFont("Common Normal") .. {
			Name = "LargestValue",
			InitCommand = function(self)
				self:halign(1):valign(0):x(65):y(64):zoom(0.34):diffuse(subText)
				self:settext("0.00")
				self.max = 0
			end,
			JudgmentMessageCommand = function(self,msg)
				    if msg.TapNoteOffset ~= nil then
				        local offset = math.abs(msg.TapNoteOffset*1000)
				        if offset <= 180 and offset > self.max then
				            self.max = offset
				            self:settextf("%.2f", self.max)
				        end
				    end
			end,
			PracticeModeResetMessageCommand = function(self)
			    self.max = 0
			    self:settext("0.00")
			end,

			PracticeModeReloadMessageCommand = function(self)
			    self.max = 0
			    self:settext("0.00")
			end
		}
	}
	,
	MovableBorder(140, 100, 1, 70, 50)
}
end
