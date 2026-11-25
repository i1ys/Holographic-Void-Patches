local practiceMode = GAMESTATE:IsPracticeMode()

if not practiceMode then
	return Def.ActorFrame {}
end

HV = HV or {}

local prevZoom = 0.65
local graphWidth = 300 * prevZoom
local graphHeight = 40 * prevZoom
local chartLength, timing = 0, nil
local practiceUsesMP3 = false
local inputScreen
local previousCursorPreference
local loopStartPos
local loopEndPos
local pausedCoinPress, previousBookmark
local doubleCoinWindow = 0.35

local function notify(message)
	if ms and ms.ok then
		ms.ok(message)
	end
end

local function getTop()
	return SCREENMAN:GetTopScreen()
end

local function getSongPos()
	local top = getTop()
	if top and top.GetSongPosition then
		local ok, pos = pcall(function() return top:GetSongPosition() end)
		if ok and type(pos) == "number" then return pos end
	end
	local sp = GAMESTATE:GetSongPosition()
	return sp and sp:GetMusicSeconds()
end

local function updateChartBounds()
	local steps = GAMESTATE:GetCurrentSteps()
	local song = GAMESTATE:GetCurrentSong()
	chartLength = steps and math.max(0, steps:GetLastSecond()) or 0
	timing = steps and steps:GetTimingData()
	local path = steps and steps:GetPreviewMusicPath()
	if song and (not path or path == "" or path == song:GetPreviewMusicPath()) then
		path = song:GetMusicPath()
	end
	practiceUsesMP3 = path ~= nil and path:lower():match("%.mp3$") ~= nil
end

local function chartPosition(pos)
	if type(pos) ~= "number" or pos ~= pos or math.abs(pos) == math.huge or chartLength <= 0 then return end
	return math.max(0, math.min(pos, chartLength))
end

local function noteRow(pos)
	-- Mirror Etterna's BeatToNoteRow for the bounds used by SetSongPosition.
	local row = timing:GetBeatFromElapsedTime(pos) * 48
	return row >= 0 and math.floor(row + 0.5) or math.ceil(row - 0.5)
end

local function isBeforeLoopEnd(pos, finish)
	return pos < finish and (not timing or noteRow(pos) < noteRow(finish))
end

local function setSongPos(pos, unpause)
	local top = getTop()
	pos = chartPosition(pos)
	if not top or not pos then return false end
	if loopEndPos and (pos < loopStartPos or not isBeforeLoopEnd(pos, loopEndPos)) then return false end
	if unpause and top.SetSongPositionAndUnpause then
		local ok = pcall(function() top:SetSongPositionAndUnpause(pos, 1, true) end)
		if ok then return true end
	end
	if top.SetSongPosition then
		-- Etterna otherwise uses approximate MP3 seeking while Practice is paused.
		return pcall(top.SetSongPosition, top, pos, 0, practiceUsesMP3 and GAMESTATE:IsPaused())
	end
	return false
end

local function isPaused()
	local top = getTop()
	if top and top.GetPaused then
		local ok, paused = pcall(function() return top:GetPaused() end)
		if ok then return paused and true or false end
	end
	return GAMESTATE:IsPaused() and true or false
end

-- Direct reference to the graph Hitbox, set once actors are ready
local graphHitboxRef = nil

local function graphMouseFraction(hitbox)
	if not hitbox then return end
	local width, height = hitbox:GetZoomedWidth(), hitbox:GetZoomedHeight()
	if width <= 0 or height <= 0 then return end
	local left = hitbox:GetTrueX() - width * hitbox:GetHAlign()
	local top = hitbox:GetTrueY() - height * hitbox:GetVAlign()
	local x, y = INPUTFILTER:GetMouseX() - left, INPUTFILTER:GetMouseY() - top
	if x >= 0 and x <= width and y >= 0 and y <= height then return x / width end
end

local function isMouseOverGraph()
	return graphMouseFraction(graphHitboxRef) ~= nil
end

local function positionX(pos)
	pos = chartPosition(pos)
	return pos and pos / chartLength * graphWidth or 0
end

local function setRegion(startPos, endPos)
	if endPos and not isBeforeLoopEnd(startPos, endPos) then
		notify("Loop end must be after the start on a different note row.")
		return false
	end
	if startPos == loopStartPos and endPos == loopEndPos then return true end

	local top = getTop()
	if endPos then
		if not top or not top.SetLoopRegion or not pcall(top.SetLoopRegion, top, startPos, endPos) then return false end
	elseif loopEndPos then
		if not top or not top.ResetLoopRegion or not pcall(top.ResetLoopRegion, top) then return false end
	end

	loopStartPos, loopEndPos = startPos, endPos
	HV.PracticeLoopStart, HV.PracticeLoopEnd = startPos or 0, endPos or 0
	local length = endPos and endPos - startPos
	MESSAGEMAN:Broadcast("RegionSet", length and {loopLength = length} or nil)
	MESSAGEMAN:Broadcast("PracticeLoopChanged")
	return true
end

local function handleRegionSetting(pos)
	pos = chartPosition(pos)
	if not pos then return end
	if not loopStartPos or pos == loopStartPos or pos == loopEndPos then
		setRegion(pos)
	elseif not loopEndPos then
		setRegion(math.min(pos, loopStartPos), math.max(pos, loopStartPos))
	elseif math.abs(pos - loopStartPos) < math.abs(pos - loopEndPos) then
		setRegion(pos, loopEndPos)
	else
		setRegion(loopStartPos, pos)
	end
end

local function frameStep(delta)
	local pos = getSongPos()
	if not pos then return end
	local ps = GAMESTATE:GetPlayerState(PLAYER_1)
	if ps and ps:GetCurrentPlayerOptions():UsingReverse() then delta = -delta end
	local first = loopEndPos and loopStartPos or 0
	local nextPos = chartPosition(math.max(first, pos + delta))
	if nextPos and nextPos ~= pos then setSongPos(nextPos, false) end
end

local function togglePause()
	local top = getTop()
	if top and top.TogglePause then top:TogglePause() end
end

local function handlePracticeCommand(name)
	if name == "PracPause" then
		togglePause()
		return
	end
	local top = getTop()
	if not top then return end

	if name == "PracRateUp" or name == "PracRateDown" then
		local delta = (name == "PracRateUp" and 1 or -1) * HV.GetRateIncrement()
		if top.AddToRate then
			pcall(function() top:AddToRate(delta) end)
		else
			changeMusicRate(delta)
		end
	elseif name == "PracRestart" then
		setSongPos(loopStartPos or 0, true)
	elseif name == "PracLoopStart" then
		local pos = chartPosition(getSongPos())
		if pos and setRegion(pos, loopEndPos) then notify(string.format("Loop Start: %.2fs", pos)) end
	elseif name == "PracLoopEnd" then
		local pos = chartPosition(getSongPos())
		if not loopStartPos then
			notify("Set a loop start first.")
		elseif pos and setRegion(loopStartPos, pos) then
			notify(string.format("Loop End: %.2fs", pos))
		end
	elseif name == "PracLoopClear" then
		if setRegion(nil) then notify("Loop Cleared") end
	elseif name == "PracClap" then
		local cur = PREFSMAN:GetPreference("CenterClap")
		PREFSMAN:SetPreference("CenterClap", not cur)
		notify("Clap: " .. (not cur and "ON" or "OFF"))
	elseif name == "PracMetronome" then
		local ps = GAMESTATE:GetPlayerState(PLAYER_1)
		local po = ps and ps:GetPlayerOptions("ModsLevel_Current")
		if po then
			local cur = po:AssistTick()
			po:AssistTick(not cur)
			notify("Metronome: " .. (not cur and "ON" or "OFF"))
		end
	elseif name == "PracAutoplay" then
		local cur = getAutoplay and getAutoplay() ~= 0
		GAMESTATE:SetAutoplay(not cur)
		notify("Autoplay: " .. (not cur and "ON" or "OFF"))
	end
end

local function duminput(event)
	if event.type == "InputEventType_FirstPress" then
		local button = event.DeviceInput and event.DeviceInput.button
		if button == "DeviceButton_right mouse button" then
			if not isMouseOverGraph() then
				togglePause()
				return true
			end
		end
		if button == "DeviceButton_backspace" then
			if loopStartPos ~= nil then return setSongPos(loopStartPos, true) end
		elseif event.button == "Coin" then
			local now = GetTimeSinceStart()
			local paused = isPaused()
			if paused and pausedCoinPress and now - pausedCoinPress <= doubleCoinWindow then
				local bookmark = previousBookmark or loopStartPos
				if bookmark and setRegion(bookmark) then notify("Loop Reset to Bookmark") end
				pausedCoinPress, previousBookmark = nil, nil
			else
				pausedCoinPress = paused and now or nil
				previousBookmark = paused and loopStartPos or nil
				handleRegionSetting(getSongPos())
			end
			return true
		elseif button == "DeviceButton_mousewheel up" or button == "DeviceButton_mousewheel down" then
			if not isPaused() then return false end
			frameStep(button == "DeviceButton_mousewheel up" and 0.05 or -0.05)
			return true
		end
	end
	return false
end

local function UpdatePreviewPos(self)
	self:GetChild("CurrentPos"):x(positionX(getSongPos()))
	local fraction = graphMouseFraction(graphHitboxRef)
	local hoverMarker = self:GetChild("HoverMarker")
	hoverMarker:visible(fraction ~= nil)
	if fraction then hoverMarker:x(fraction * graphWidth) end
end

local function drawRegion(self)
	self:visible(loopStartPos ~= nil)
	if not loopStartPos then return end
	local x = positionX(loopStartPos)
	local width = loopEndPos and positionX(loopEndPos) - x or 2
	local tint = loopEndPos and color(".7,.2,.7,0.5") or color(".2,.5,1,1")
	self:x(x):zoomto(width, graphHeight):diffuse(tint)
end

local pm = Def.ActorFrame {
	Name = "ChartPreview",
	InitCommand = function(self)
		local x = (MovableValues and MovableValues.PracticeCDGraphX) or getDefaultGameplayCoordinate("PracticeCDGraphX") or SCREEN_LEFT + 20
		local y = (MovableValues and MovableValues.PracticeCDGraphY) or getDefaultGameplayCoordinate("PracticeCDGraphY") or SCREEN_CENTER_Y
		self:xy(x, y)
		self:SetUpdateFunction(UpdatePreviewPos)
	end,
	OnCommand = function(self)
		-- Disable the chord density graph's internal hover marker since it doesn't account for zoom
		local cdg = self:GetChild("ChordDensityGraph")
		if cdg then
			local seekMarker = cdg:GetChild("SeekMarker")
			if seekMarker then seekMarker:diffusealpha(0) end
		end
	end,
	BeginCommand = function(self)
		updateChartBounds()
		HV.PracticeLoopStart, HV.PracticeLoopEnd = 0, 0
		-- Store direct reference to Hitbox for input hit-testing
		graphHitboxRef = self:GetChild("Hitbox")
		local top = getTop()
		if not inputScreen and top and top.AddInputCallback then
			top:AddInputCallback(duminput)
			inputScreen = top
		end
		self:SortByDrawOrder()
		self:queuecommand("GraphUpdate")
	end,
	EndCommand = function(self)
		if inputScreen and inputScreen.RemoveInputCallback then
			inputScreen:RemoveInputCallback(duminput)
		end
		inputScreen = nil
		HV.PracticeLoopStart, HV.PracticeLoopEnd = 0, 0
		if previousCursorPreference ~= nil then
			PREFSMAN:SetPreference("ShowMouseCursor", previousCursorPreference)
			previousCursorPreference = nil
		end
	end,
	PracticeModeReloadMessageCommand = function(self)
		updateChartBounds()
		pausedCoinPress, previousBookmark = nil, nil
		-- Native reload can adjust the loop independently. Keep a still-valid
		-- bookmark and clear the loop so both the chart and engine agree.
		local bookmark = chartLength > 0 and loopStartPos and loopStartPos < chartLength and loopStartPos or nil
		setRegion(bookmark)
		drawRegion(self:GetChild("BookmarkPos"))
	end,
	LoadActor("../_chorddensitygraph.lua") .. {
		InitCommand = function(self)
			self:zoom(prevZoom)
		end
	},
	UIElements.QuadButton(1, 1) .. {
		Name = "Hitbox",
		InitCommand = function(self)
			self:halign(0):valign(1):zoomto(graphWidth, graphHeight):diffusealpha(0):draworder(1099)
		end,
		MouseDownCommand = function(self, params)
			local event = params.event or params.button
			local fraction = graphMouseFraction(self)
			if not fraction then return end
			local pos = fraction * chartLength
			if event == "DeviceButton_right mouse button"
				or (event == "DeviceButton_left mouse button" and INPUTFILTER:IsControlPressed()) then
				handleRegionSetting(pos)
			elseif event == "DeviceButton_left mouse button" then
				if not setSongPos(pos, false) and loopEndPos then notify("Seek inside the loop, or clear it first.") end
			end
		end
	},
	Def.Quad {
		Name = "BookmarkPos",
		InitCommand = function(self)
			self:zoomto(2, graphHeight):diffuse(color(".2,.5,1,1")):halign(0):valign(1):draworder(1100):visible(false)
		end,
		RegionSetMessageCommand = drawRegion
	},
	Def.Quad {
		Name = "CurrentPos",
		InitCommand = function(self)
			self:zoomto(2, graphHeight):diffuse(HVColor.Accent):halign(0.5):valign(1):draworder(1101)
		end
	},
	-- Custom hover marker that accounts for zoom
	Def.Quad {
		Name = "HoverMarker",
		InitCommand = function(self)
			self:zoomto(1, graphHeight):diffuse(color("1,1,1,0.5")):halign(0.5):valign(1):visible(false):draworder(1100)
		end
	}
}

local t = Def.ActorFrame {
	OnCommand = function(self)
		if previousCursorPreference == nil then
			previousCursorPreference = PREFSMAN:GetPreference("ShowMouseCursor")
		end
		PREFSMAN:SetPreference("ShowMouseCursor", true)
	end,
	CodeMessageCommand = function(self, params)
		handlePracticeCommand(params.Name)
	end,
	pm
}

return t
