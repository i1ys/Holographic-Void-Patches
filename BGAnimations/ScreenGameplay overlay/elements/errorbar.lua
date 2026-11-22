local gameplay = ...
local gameplayCoord = gameplay.gameplayCoord
local gameplaySize = gameplay.gameplaySize
local accentColor = gameplay.accentColor
local ThemePrefs = HV.LegacyPrefs

local baseEBW = 240
local ebW = baseEBW * gameplaySize("ErrorBarScale")
local ebH = 2
local ebCenterY = SCREEN_CENTER_Y + SCREEN_HEIGHT * 0.15 - 40
local maxOffset = 180 -- ms
local dotLife = 2.0  -- seconds

-- EWMA state
local ewmaValue = 0
local ewmaAlpha = 0.07
local ebMode = ThemePrefs.Get("HV_ErrorBarMode") or "Standard"
local showEWMA = (ebMode == "EWMAOnly" or ebMode == "Both")
local showStandard = (ebMode == "Standard" or ebMode == "Both")

	return Def.ActorFrame {
		Name = "ErrorBar",
		InitCommand = function(self)
			local ebMode = ThemePrefs.Get("HV_ErrorBarMode") or "Standard"
			self:xy(gameplayCoord("ErrorBarX"), gameplayCoord("ErrorBarY")):visible(ebMode ~= "Off" and not gameplay.isSync)
		end,
		OnCommand = function(self)
			setMovableActor({"DeviceButton_5", "DeviceButton_6"}, self, self:GetChild("Border"))
		end,
		UpdateEBScaleCommand = function(self, params)
			ebW = baseEBW * params.scale
			self:GetChild("Border"):playcommand("ChangeWidth", {val = ebW})
			self:playcommand("UpdateChildrenEBWidth", {width = ebW})
		end,

	-- Background line
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(ebW, ebH):visible(false)
		end
	},

	-- Center Line (0ms)
	Def.Quad {
		Name = "CenterLine",
		InitCommand = function(self)
			self:zoomto(1, ebH + 8):diffuse(color("1,1,1,0.3"))
		end,
		UpdateChildrenEBWidthCommand = function(self, params)
			-- center line doesn't change size usually but we can react if needed
		end
	},

	-- Judgement window highlights (only visible when resizing)
	Def.ActorFrame {
		Name = "Highlights",
		InitCommand = function(self)
			self:visible(false)
		end,
		MovableUpdatedMessageCommand = function(self, params)
			local ebMode = ThemePrefs.Get("HV_ErrorBarMode") or "Standard"
			local isVisible = params and (params.button == "DeviceButton_6") and (ebMode ~= "Off")
			self:visible(isVisible or false)
		end,
		(function()
			local g = Def.ActorFrame{}
			local windows = {180, 135, 90, 45, 22.5}
			local colors = {
				HVColor.GetJudgmentColor("W5"),
				HVColor.GetJudgmentColor("W4"),
				HVColor.GetJudgmentColor("W3"),
				HVColor.GetJudgmentColor("W2"),
				HVColor.GetJudgmentColor("W1")
			}
			if HV.EmulateRidiculousEnabled() then
				table.insert(windows, 11.25 * (tonumber(gameplay.judgeScale) or 1))
				table.insert(colors, HVColor.GetJudgmentColor("Ridiculous"))
			end
			for i=1, #windows do
				g[#g+1] = Def.Quad {
					InitCommand = function(self)
						local w = (windows[i] / maxOffset) * ebW
						self:zoomto(w, ebH + 16):diffuse(colors[i]):diffusealpha(0.35)
					end,
					UpdateChildrenEBWidthCommand = function(self, params)
						local w = (windows[i] / maxOffset) * params.width
						self:zoomto(w, ebH + 16)
					end
				}
			end
			return g
		end)()
	},

	-- Early Indicator (Left)
	LoadFont("Common Normal") .. {
		Text = "EARLY",
		InitCommand = function(self)
			self:x(-ebW/2 - 5):y(-12):zoom(0.25):halign(0):diffusealpha(0)
		end,
		OnCommand = function(self)
			self:sleep(0.5):linear(0.2):diffusealpha(0.6):sleep(1.2):linear(0.2):diffusealpha(0)
		end,
		UpdateChildrenEBWidthCommand = function(self, params)
			self:x(-params.width/2 - 5)
		end
	},
	-- Late Indicator (Right)
	LoadFont("Common Normal") .. {
		Text = "LATE",
		InitCommand = function(self)
			self:x(ebW/2 + 5):y(-12):zoom(0.25):halign(1):diffusealpha(0)
		end,
		OnCommand = function(self)
			self:sleep(0.5):linear(0.2):diffusealpha(0.6):sleep(1.2):linear(0.2):diffusealpha(0)
		end,
		UpdateChildrenEBWidthCommand = function(self, params)
			self:x(params.width/2 + 5)
		end
	},

	Def.Quad {
		Name = "EWMAMarker",
		InitCommand = function(self)
			self:zoomto(2, ebH + 8):diffuse(accentColor):visible(showEWMA)
		end,
		UpdateEWMACommand = function(self, params)
			local offset = params.offset
			ewmaValue = (1 - ewmaAlpha) * ewmaValue + ewmaAlpha * offset
			self:x((ewmaValue / maxOffset) * (ebW / 2))
		end,
		UpdateChildrenEBWidthCommand = function(self, params)
			self:x((ewmaValue / maxOffset) * (params.width / 2))
		end
	},

	JudgmentMessageCommand = function(self, params)
		if params.Player ~= PLAYER_1 then return end
		if not params.TapNoteScore then return end
		if params.HoldNoteScore then return end -- Skip holds

		local offset = params.TapNoteOffset
		if not offset then return end

		-- Exclude misses from EWMA
		if params.TapNoteScore == "TapNoteScore_Miss" then return end

		-- Clamp for visualization
		local visualOffset = offset * 1000 -- to ms

		-- Update EWMA marker if enabled
		if showEWMA then
			self:GetChild("EWMAMarker"):playcommand("UpdateEWMA", {offset = visualOffset})
		end

		if not showStandard then return end
		if math.abs(visualOffset) > maxOffset then return end

		local ebColoring = ThemePrefs.Get("HV_ErrorBarColoringMode") or "Current"
		local jScale = 1
		if ebColoring == "Current" then
			jScale = PREFSMAN:GetPreference("TimingWindowScale")
		end

		local xPos = (visualOffset / maxOffset) * (ebW / 2)
		local jColor = offsetToJudgeColor(visualOffset, jScale)

		-- Pooling system: Cycle through child actors
		local pool = self:GetChild("Pool")
		if pool then
			self.poolIdx = (self.poolIdx or 0) % 50 + 1
			local dot = pool:GetChild("Dot"..self.poolIdx)
			if dot then
				dot:stoptweening():visible(true):x(xPos):diffuse(jColor):diffusealpha(0.8)
					:sleep(dotLife):linear(0.5):diffusealpha(0)
			end
		end
	end,

	(function()
		local poolDef = Def.ActorFrame { Name = "Pool" }
		for i=1, 50 do
			poolDef[#poolDef + 1] = Def.Quad {
				Name = "Dot"..i,
				InitCommand = function(s)
					s:zoomto(1, ebH + 6):visible(false)
				end
			}
		end
		return poolDef
	end)()
	,
	MovableBorder(ebW, ebH + 12, 1, 0, 0)
}
