local judgments = {W1 = 0, W2 = 1, W3 = 2, W4 = 3, W5 = 4, Miss = 5}

local t = Def.ActorFrame {
	JudgmentMessageCommand = function(self, params)
		if params.Player ~= PLAYER_1 then return end
		if not params.TapNoteScore then return end
		if params.HoldNoteScore then return end -- Skip hold/roll end events
		
		local judgment = self:GetChild("PlayerJudgment")
		if not judgment then return end
		local tns = ToEnumShortString(params.TapNoteScore)
		local container = judgment:GetChild("JudgmentContainer")
		local sprite = container:GetChild("JudgmentSprite")
		if not sprite then return end
		
		local jdgIdx = judgments[tns]
		if not jdgIdx then return end
		
		local isRidiculous = false
		if HV.EmulateRidiculousEnabled() and tns == "W1" and params.TapNoteOffset then
			local judgeScale = tonumber(HV_JudgeScale) or PREFSMAN:GetPreference("TimingWindowScale") or 1
			if math.abs(params.TapNoteOffset) <= 0.01125 * judgeScale then
				isRidiculous = true
			end
		end

		-- The engine judgment actor is hidden in metrics.ini; this custom actor
		-- must honor the theme option before rendering a hit judgment.
		if HV.ShowJudgment and not HV.ShowJudgment() then
			return
		end

		local emulateRidiculous = HV.EmulateRidiculousEnabled()
		local numStates = sprite:GetNumStates()
		local state
		local offset = params.TapNoteOffset
		local isLate = (offset and offset >= 0) and 1 or 0

		if numStates == 14 then
			-- 2x7 sprite: Row 0 is Ridiculous only if emulation is enabled
			local baseIdx = jdgIdx
			if emulateRidiculous then
				baseIdx = isRidiculous and 0 or (jdgIdx + 1)
			else
				baseIdx = jdgIdx == 0 and 0 or (jdgIdx + 1)
			end
			state = baseIdx * 2 + isLate
		elseif numStates == 7 then
			-- 1x7 sprite
			local baseIdx = jdgIdx
			if emulateRidiculous then
				baseIdx = isRidiculous and 0 or (jdgIdx + 1)
			else
				baseIdx = jdgIdx == 0 and 0 or (jdgIdx + 1)
			end
			state = baseIdx
		elseif numStates == 12 then
			-- 2x6 sprite: Standard mapping
			state = jdgIdx * 2 + isLate
		else
			-- Standard 1x6 sprite
			state = jdgIdx
		end

		local curTime = GetTimeSinceStart()
		local displayDuration = 0.5
		if HV.PrioritizeLowerJudgements and HV.PrioritizeLowerJudgements() then
			if curTime < judgment.lockedUntil and jdgIdx <= judgment.lockedIndex then
				return
			end

			local isLower = false
			if jdgIdx >= 3 then
				isLower = true
			else
				local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats(params.Player or PLAYER_1)
				if pss then
					local w1 = pss:GetTapNoteScores("TapNoteScore_W1")
					local w2 = pss:GetTapNoteScores("TapNoteScore_W2")
					local w3 = pss:GetTapNoteScores("TapNoteScore_W3")
					
					if jdgIdx == 1 then
						if w1 > (w2 * 2.5) then isLower = true end
					elseif jdgIdx == 2 then
						if w2 > (w3 * 5.0) then isLower = true end
					end
				end
			end

			if isLower then
				displayDuration = 0.3
				judgment.lockedUntil = curTime + displayDuration
				judgment.lockedIndex = jdgIdx
			else
				judgment.lockedUntil = 0
				judgment.lockedIndex = -1
			end
		else
			judgment.lockedUntil = 0
			judgment.lockedIndex = -1
		end

		-- Apply state and show the judgment container
		judgment:visible(true)
		container:stoptweening():visible(true):diffusealpha(1)
		sprite:setstate(state)

		local ridiculousIndicator = container:GetChild("RidiculousIndicator")
		if ridiculousIndicator then
			-- Only show text indicator for 6-row sprites
			if isRidiculous and numStates ~= 7 and numStates ~= 14 then
				ridiculousIndicator:stoptweening():visible(true):diffusealpha(1)
				if HV.JudgmentAnimation and HV.JudgmentAnimation() then
					ridiculousIndicator:glow(color("1,1,1,0.5")):linear(0.05):glow(color("1,1,1,0"))
				end
			else
				ridiculousIndicator:visible(false)
			end
		end

		-- Apply Animation if enabled (only to the judgment container)
		if HV.JudgmentAnimation and HV.JudgmentAnimation() then
			container:zoom(0.81) -- Start slightly larger for the pulse
			container:linear(0.05):zoom(0.65)
			container:glow(color("1,1,1,0.5")):linear(0.05):glow(color("1,1,1,0"))
		else
			container:zoom(0.65)
		end
		
		container:sleep(displayDuration):linear(0.1):diffusealpha(0)
	end,
	Def.ActorFrame {
		Name = "PlayerJudgment",
		InitCommand = function(self)
			self:addx((MovableValues and MovableValues.JudgeX) or getDefaultGameplayCoordinate("JudgeX") or 0):addy((MovableValues and MovableValues.JudgeY) or getDefaultGameplayCoordinate("JudgeY") or 0):zoom((MovableValues and MovableValues.JudgeZoom) or getDefaultGameplaySize("JudgeZoom") or 1)
			self:visible(false)
			self.lockedUntil = 0
			self.lockedIndex = -1
		end,
		OnCommand = function(self)
			setMovableActor({"DeviceButton_1", "DeviceButton_2"}, self, self:GetChild("Border"))
		end,

		Def.ActorFrame {
			Name = "JudgmentContainer",
			Def.Sprite {
				Name = "JudgmentSprite",
				InitCommand = function(self)
					-- The customization cursor marks the center of the judgment
					-- element.  Set the sprite's anchor explicitly so texture
					-- alignment cannot introduce a half-width/half-height offset.
					self:halign(0.5):valign(0.5)
					local path = getAssetPath("judgment")
					if path and path ~= "" then
						self:Load(path)
						if self.pause then self:pause() end
						self:setstate(0)
					end
				end
			},
			LoadFont("Common Normal") .. {
				Name = "RidiculousIndicator",
				InitCommand = function(self)
					self:y(-22):zoom(0.4):visible(false):maxwidth(200)
					self:settext("RIDICULOUS")
					self:diffuse(color("#E6FFFF")) -- Very light cyan
					self:strokecolor(color("#1A2B2B"))
				end
			}
		},
		MovableBorder(120, 40, 1, 0, 0)
	},
}

return t
