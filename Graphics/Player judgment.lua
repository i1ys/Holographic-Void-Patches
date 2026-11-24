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
		
		-- The engine judgment actor is hidden in metrics.ini; this custom actor
		-- must honor the theme option before rendering a hit judgment.
		if HV.ShowJudgment and not HV.ShowJudgment() then
			return
		end

		local numStates = sprite:GetNumStates()
		local state = jdgIdx
		-- Legacy seven-row assets reserve their first row for the extra judgment.
		if numStates == 7 or numStates == 14 then state = state + 1 end
		if numStates == 12 or numStates == 14 then
			local offset = params.TapNoteOffset
			state = state * 2 + ((offset and offset >= 0) and 1 or 0)
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
		},
		MovableBorder(120, 40, 1, 0, 0)
	},
}

return t
