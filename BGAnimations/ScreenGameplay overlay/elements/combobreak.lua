local gameplay = ...
local minimalisticHUDVisible = gameplay.minimalisticHUDVisible
local animateGameplayHUDVisibility = gameplay.animateGameplayHUDVisibility

local showComboBreakHighlight = HV.ComboBreakHighlight() and not gameplay.isSync

if showComboBreakHighlight then
local judgmentPalette = HV.Color.GetJudgmentPalette()

-- Helper: build a gradient AMV lane quad.
-- xOffset: lane center X (relative to parent ActorFrame at SCREEN_CENTER)
-- laneW: lane pixel width
-- The quad spans from y=0 (screen center, top of highlight, transparent)
--   to y=SCREEN_HEIGHT/2 (receptor area, bottom, opaque at flash time).
-- Vertices are ordered: TL, TR, BR, BL (quad strip).
local function makeCBLane(name, xOffset, laneW)
	local halfW   = laneW / 2
	-- The parent frame sits at SCREEN_CENTER_Y.
	-- Receptors are near SCREEN_BOTTOM, so the opaque end of the gradient
	-- is SCREEN_HEIGHT/2 pixels below the frame origin (positive Y = down).
	-- 80% height means topY = (bottomY) - (0.8 * SCREEN_HEIGHT) = -0.3 * SCREEN_HEIGHT
	local topY    = -SCREEN_HEIGHT * 0.3 -- 80% height highlight
	local bottomY = SCREEN_HEIGHT / 2    -- receptor area       → opaque at flash peak

	return Def.ActorMultiVertex {
		Name = name,
		InitCommand = function(self)
			self:x(xOffset)
			-- Pre-set vertices with the desired gradient (peak alpha handled in FlashCommand)
			self:SetVertices({
				{{-halfW, topY,    0}, {1, 1, 1, 0}}, -- TL
				{{ halfW, topY,    0}, {1, 1, 1, 0}}, -- TR
				{{ halfW, bottomY, 0}, {1, 1, 1, 1}}, -- BR
				{{-halfW, bottomY, 0}, {1, 1, 1, 1}}, -- BL
			})
			self:SetDrawState({Mode="DrawMode_Quads", First=1, Num=4})
			self:diffusealpha(0)
		end,
		FlashCommand = function(self, params)
			local c = params and params.color or color("#FF5050")
			self:stoptweening()
			self:diffuse(c)

			-- Instant snap to a clearer peak (0.35) and a single linear fade-out.
			-- This avoids the "snapping to dim" feeling of the dual-ramp approach.
			self:diffusealpha(0.35)
			self:linear(0.70)
			self:diffusealpha(0)
		end
	}
end

return Def.ActorFrame {
	Name = "ComboBreakHighlight",
	InitCommand = function(self)
		self:xy(SCREEN_CENTER_X, SCREEN_CENTER_Y)
		self:visible(minimalisticHUDVisible(showComboBreakHighlight))
	end,
	HV_MinimalisticModeChangedMessageCommand = function(self, params)
		animateGameplayHUDVisibility(self, minimalisticHUDVisible(showComboBreakHighlight, params and params.Enabled))
	end,

	-- 4 gradient lane highlights for standard 4K (64px wide, spaced 64px apart)
	makeCBLane("Lane1", -96, 64),
	makeCBLane("Lane2", -32, 64),
	makeCBLane("Lane3",  32, 64),
	makeCBLane("Lane4",  96, 64),

	JudgmentMessageCommand = function(self, params)
		if params.Player ~= PLAYER_1 then return end
		if not params.TapNoteScore then return end

		-- Flash on combo-breaking judgments
		local isComboBreak = (params.TapNoteScore == "TapNoteScore_Miss" or
							  params.TapNoteScore == "TapNoteScore_W5" or
							  params.TapNoteScore == "TapNoteScore_W4")

		if isComboBreak and params.Notes then
			local jColor = judgmentPalette[ToEnumShortString(params.TapNoteScore)]

			-- Flash lanes that had notes in this judgment
			for i = 1, 4 do
				if params.Notes[i] ~= nil then
					local lane = self:GetChild("Lane" .. i)
					if lane then
						lane:playcommand("Flash", {color=jColor})
					end
				end
			end
		end
	end
}
end -- End combo break highlight
