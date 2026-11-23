local gameplay = ...
local gameplayCoord = gameplay.gameplayCoord
local gameplaySize = gameplay.gameplaySize
local minimalisticHUDVisible = gameplay.minimalisticHUDVisible
local animateGameplayHUDVisibility = gameplay.animateGameplayHUDVisibility
local dimText = gameplay.dimText
local subText = gameplay.subText
local brightText = gameplay.brightText

local showCombo = HV.ShowCombo()

if showCombo then
return Def.ActorFrame {
	Name = "ComboDisplay",
	InitCommand = function(self)
		self:xy(SCREEN_CENTER_X + gameplayCoord("ComboX"), SCREEN_CENTER_Y + gameplayCoord("ComboY")):zoom(gameplaySize("ComboZoom"))
		self.comboBreaks = 0
		self:visible(minimalisticHUDVisible(showCombo))
	end,
	HV_MinimalisticModeChangedMessageCommand = function(self, params)
		animateGameplayHUDVisibility(self, minimalisticHUDVisible(showCombo, params and params.Enabled))
	end,
	OnCommand = function(self)
		setMovableActor({"DeviceButton_3", "DeviceButton_4"}, self, self:GetChild("Border"))
	end,

	LoadFont("combo/_mochiy pop one 24px") .. {
		Name = "ComboNumber",
		InitCommand = function(self)
			self:zoom(0.75):diffuse(brightText):y(-4)
			self:settext("0"):shadowlength(0)
		end
	},

	Def.ActorFrame {
		Name = "ComboLabel",
		InitCommand = function(self)
			self:y(16)
		end,

		-- Graphic for "Combo"
		Def.Sprite {
			Name = "ComboGraphic",
			Texture = THEME:GetPathG("", "combo_label.png"),
			InitCommand = function(self)
				self:zoom(0.25):diffuse(subText):visible(true)
			end
		},

		-- Text for "Misses" (fallback if no graphic, or for text-specific label)
		LoadFont("Common Normal") .. {
			Name = "MissesText",
			InitCommand = function(self)
				self:zoom(0.22):diffuse(color("#FF5050")):visible(false)
				self:settext(THEME:GetString("ScreenGameplay", "Misses"))
			end
		}
	},

	JudgmentMessageCommand = function(self, params)
		if params.Player ~= PLAYER_1 then return end
		local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats()
		if not pss then return end

		-- Synchronously calculate consecutive combo breaks
		-- This prevents C++ CNote jumps from overwriting 'Update' queue params resulting in total missed sums
		if not params.HoldNoteScore and params.TapNoteScore then
			local tns = params.TapNoteScore
			if tns == "TapNoteScore_Miss" or tns == "TapNoteScore_W5" or tns == "TapNoteScore_W4" then
				self.comboBreaks = self.comboBreaks + 1
			elseif tns == "TapNoteScore_W1" or tns == "TapNoteScore_W2" or tns == "TapNoteScore_W3" then
				self.comboBreaks = 0
			end
		end

		-- Apply Combo Animation if enabled
		-- Triggering here avoids Engine race conditions on key release
		if HV.ComboAnimation and HV.ComboAnimation() then
			-- Avoid 1.3 zoom mistakenly triggering on hold releases
			if not params.HoldNoteScore then
				local tns = params.TapNoteScore
				if tns and tns ~= "TapNoteScore_None" and tns ~= "TapNoteScore_Miss" and tns ~= "TapNoteScore_HitMine" and tns ~= "TapNoteScore_AvoidMine" and tns ~= "TapNoteScore_CheckpointHit" and tns ~= "TapNoteScore_CheckpointMiss" then
					if pss:GetCurrentCombo() > 0 then
						self.lastHitTime = GetTimeSinceStart()
						self:stoptweening():zoom(1.3):linear(0.05):zoom(1.0)
					end
				end
			end
		end

		-- Redraw miss UI if combo is 0 (as combo=0 judgments don't reliably trigger ComboChanged per C++ implementation)
		if pss:GetCurrentCombo() == 0 then
			local numActor = self:GetChild("ComboNumber")
			local labelContainer = self:GetChild("ComboLabel")
			local graphic = labelContainer:GetChild("ComboGraphic")
			local text = labelContainer:GetChild("MissesText")

			if self.comboBreaks >= 5 then
				numActor:settext(tostring(self.comboBreaks)):diffuse(color("#FF5050")):shadowlength(0)
				graphic:visible(false)
				text:visible(true):settext(THEME:GetString("ScreenGameplay", "Misses"))
			else
				numActor:settext("0"):diffuse(dimText):shadowlength(0)
				graphic:visible(true):diffusealpha(0.5)
				text:visible(false)
			end
		end
	end,

	ComboChangedMessageCommand = function(self, params)
		local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats()
		if not pss then return end

		local combo = pss:GetCurrentCombo()
		local numActor = self:GetChild("ComboNumber")
		local labelContainer = self:GetChild("ComboLabel")
		local graphic = labelContainer:GetChild("ComboGraphic")
		local text = labelContainer:GetChild("MissesText")

		if combo > 0 then
			local totalNotes = getMaxNotes(PLAYER_1) or 1
			local threshold = math.floor(totalNotes * 0.25)
			local ct = getDetailedClearType(pss)
			local ctColor = getClearTypeColor(ct)

			numActor:settext(tostring(combo)):diffuse(brightText)

			-- Shadow display logic: 25% threshold + No combo breaks (FC status so far)
			local isFC = (ct ~= "MF" and ct ~= "SDCB" and ct ~= "Clear" and ct ~= "Failed")

			if combo >= threshold and isFC then
				numActor:shadowcolor(ctColor)
				numActor:shadowlength(1.5) -- Improved visibility
			else
				numActor:shadowlength(0)
			end

			graphic:visible(true):diffusealpha(1)
			text:visible(false)
		elseif self.comboBreaks < 5 then
			numActor:settext("0"):diffuse(dimText):shadowlength(0)
			graphic:visible(true):diffusealpha(0.5)
			text:visible(false)
		end
	end,

	GhostTapMessageCommand = function(self)
		if HV.ComboAnimation and HV.ComboAnimation() then
			-- Prevent Ghost Tap from overriding the 1.3 zoom from a valid hit
			if self.lastHitTime and GetTimeSinceStart() - self.lastHitTime < 0.05 then return end
			self:stoptweening():zoom(1.08):linear(0.05):zoom(1.0)
		end
	end,

	MovableBorder(120, 40, 1, 0, 0),
}
end -- End combo visibility check
