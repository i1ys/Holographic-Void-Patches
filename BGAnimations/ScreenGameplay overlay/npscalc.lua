local ThemePrefs = HV.LegacyPrefs

-- Holographic Void: NPS Calculator
-- Ported from spawncamping-wallhack
-- Time-based moving average with ActorMultiVertex graph display

local pn = GAMESTATE:GetEnabledPlayers()[1]
local showText, showGraph = HV.ShowNPS(), HV.ShowNPSGraph()
if not showText and not showGraph then
	return Def.ActorFrame {}
end

local minWindow = 0.5
local function getWindowSize()
	return math.max(minWindow, tonumber(ThemePrefs.Get("HV_NPSWindowSize")) or 1.5)
end
local npsWindow = getWindowSize()

-- HV Specific Styling & Position
local graphWidth = 140
local graphHeight = 50
local graphX = 10
local graphY = SCREEN_CENTER_Y + 100
local fontZoom = 0.65
local accentColor = HVColor.Accent or color("#00CFFF")

local maxSamples = 150
local sampleInterval = 0.2
local initialPeak = 1

local noteTable = {}
local noteSum, peakNPS = 0, 0
local lastSongSeconds, lastRate, referenceSeconds, wasPaused
local samples = {}
local lastSampleTime
local npsTextActor, graphActor

local function animateNPSVisibility(self, visible)
	self:stoptweening()
	if visible then
		self:visible(true):diffusealpha(0):decelerate(0.18):diffusealpha(1)
	else
		self:accelerate(0.14):diffusealpha(0)
	end
end

local function resetNPS()
	noteTable = {}
	noteSum, peakNPS = 0, 0
	lastSongSeconds, lastRate, referenceSeconds, wasPaused = nil, nil, nil, nil
	samples, lastSampleTime = {}, nil
	if npsTextActor then npsTextActor:settext("NPS: 0  Peak: 0") end
	if graphActor then
		graphActor:SetDrawState {First = 1, Num = 0}
	end
end

local function sampleClock()
	local songSeconds = math.max(0, GAMESTATE:GetSongPosition():GetMusicSeconds())
	local rate = getCurRateValue()
	local paused = GAMESTATE:IsPaused()
	if lastSongSeconds then
		local jump = songSeconds - lastSongSeconds
		if rate ~= lastRate or jump < -0.05 or (paused and wasPaused and jump > 0.05) then
			resetNPS()
		else
			-- The audio clock can move slightly backward when it resumes.
			songSeconds = math.max(songSeconds, lastSongSeconds)
		end
	end
	lastSongSeconds, lastRate, wasPaused = songSeconds, rate, paused
	referenceSeconds = referenceSeconds or songSeconds
	return (songSeconds - referenceSeconds) / rate
end

local function updateGraph(elapsed, nps)
	if not graphActor or (lastSampleTime and elapsed - lastSampleTime < sampleInterval) then return end
	lastSampleTime = elapsed
	samples[#samples + 1] = nps
	if #samples > maxSamples then table.remove(samples, 1) end

	local verts = {}
	local peak = math.max(peakNPS, initialPeak)
	for i, sample in ipairs(samples) do
		local x = (i - #samples) * graphWidth / maxSamples
		verts[i] = {{x, -sample / peak * graphHeight, 0}, accentColor}
	end
	graphActor:SetVertices(verts)
	graphActor:SetDrawState {First = 1, Num = #verts > 1 and #verts or 0}
end

local function update()
	-- Clock discontinuities may clear the queue. Sample before accessing it.
	local elapsed = sampleClock()
	while noteTable[1] and elapsed - noteTable[1].time > npsWindow do
		noteSum = noteSum - table.remove(noteTable, 1).size
	end
	local nps = noteSum / clamp(elapsed, minWindow, npsWindow)
	peakNPS = math.max(peakNPS, nps)
	if npsTextActor then npsTextActor:settextf("NPS: %0.0f  Peak: %0.0f", nps, peakNPS) end
	updateGraph(elapsed, nps)
end

local t = Def.ActorFrame {
	Name = "NPSCalcContainer",
	InitCommand = function(self)
		self:visible(not HV.MinimalisticMode())
		self:diffusealpha(HV.MinimalisticMode() and 0 or 1)
	end,
	HV_MinimalisticModeChangedMessageCommand = function(self, params)
		animateNPSVisibility(self, not (params and params.Enabled))
	end,
	OnCommand = function(self)
		if showText then
			local text = self:GetChild("NPSTextContainer")
			setMovableActor({"DeviceButton_y", "DeviceButton_u"}, text, text:GetChild("Border"))
		end
		if showGraph then
			local graph = self:GetChild("NPSGraph")
			setMovableActor({"DeviceButton_i", "DeviceButton_o"}, graph, graph:GetChild("Border"))
		end
		self:SetUpdateFunction(update)
	end,

	Def.Actor {
		JudgmentMessageCommand = function(self, params)
			if params.Player ~= pn or params.Type ~= "Tap" or params.FromReplay then return end

			local size = 0
			if params.Notes then
				-- Etterna sends only the judged lane when chord cohesion is off.
				for _ in pairs(params.Notes) do size = size + 1 end
			elseif GAMESTATE:CountNotesSeparately() then
				size = 1
			end
			if size == 0 then return end

			local elapsed = sampleClock()
			noteTable[#noteTable + 1] = {time = elapsed, size = size}
			noteSum = noteSum + size
		end,
		PracticeLoopChangedMessageCommand = resetNPS,
		PracticeModeResetMessageCommand = resetNPS,
		PracticeModeReloadMessageCommand = resetNPS,
		CurrentSongChangedMessageCommand = resetNPS,
		CurrentRateChangedMessageCommand = function()
			sampleClock()
		end,
		ThemePrefChangedMessageCommand = function(self, params)
			if params and params.Name == "HV_NPSWindowSize" then
				local size = getWindowSize()
				if npsWindow ~= size then
					npsWindow = size
					resetNPS()
				end
			end
		end
	},
}

-- Text Container
local text = Def.ActorFrame {
	Name = "NPSTextContainer",
	InitCommand = function(self)
		self:xy((MovableValues and MovableValues.NPSDisplayX) or getDefaultGameplayCoordinate("NPSDisplayX") or graphX, (MovableValues and MovableValues.NPSDisplayY) or getDefaultGameplayCoordinate("NPSDisplayY") or (graphY - 5)):zoom((MovableValues and MovableValues.NPSDisplayZoom) or getDefaultGameplaySize("NPSDisplayZoom") or fontZoom)
	end,
	LoadFont("Common Normal") .. {
		Name = "Text",
		InitCommand = function(self)
			self:halign(0):valign(1):diffuse(accentColor)
			self:settext("NPS: 0  Peak: 0")
			npsTextActor = self
		end
	},
	MovableBorder(110, 18, 1, 55, -9)
}

if showText then t[#t + 1] = text end

-- Graph Container
local graphVerts = Def.ActorFrame {
	Name = "NPSGraph",
	InitCommand = function(self)
		self:xy((MovableValues and MovableValues.NPSGraphX) or getDefaultGameplayCoordinate("NPSGraphX") or graphX, (MovableValues and MovableValues.NPSGraphY) or getDefaultGameplayCoordinate("NPSGraphY") or graphY):zoomtowidth((MovableValues and MovableValues.NPSGraphWidth) or getDefaultGameplaySize("NPSGraphWidth") or 1):zoomtoheight((MovableValues and MovableValues.NPSGraphHeight) or getDefaultGameplaySize("NPSGraphHeight") or 1)
	end,
	
	-- Background Quad
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(graphWidth, graphHeight)
			self:xy(0, graphHeight)
			self:diffuse(color("0.03,0.03,0.03")):diffusealpha(0.7)
			self:halign(0):valign(1)
		end
	},
	
	-- Top Line
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(graphWidth, 1)
			self:xy(0, 0)
			self:diffusealpha(0.2)
			self:halign(0)
		end
	},

	-- Base Line
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(graphWidth, 1)
			self:xy(0, graphHeight)
			self:diffusealpha(0.5)
			self:halign(0)
		end
	},

	-- AMV Graph
	Def.ActorMultiVertex {
		Name = "AMV_QuadStrip",
		InitCommand = function(self)
			graphActor = self
			self:xy(graphWidth, graphHeight)
			self:SetDrawState {Mode = "DrawMode_LineStrip", First = 1, Num = 0}
		end,
	},
	MovableBorder(graphWidth, graphHeight, 1, graphWidth / 2, graphHeight / 2)
}

if showGraph then t[#t + 1] = graphVerts end

return t
