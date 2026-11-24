-- Holographic Void: ScreenChartPreview Overlay
-- Integrated sc-wh logic with HV Aesthetics (Glassmorphism, Accents, OLED Blacks).

local chartDensity = LoadActor("../ChartDensity.lua")
local pn = PLAYER_1
local song = GAMESTATE:GetCurrentSong()
local steps = GAMESTATE:GetCurrentSteps()

local ssm
local musicLength = 0
local loadedRate
local densityVectors, densityStats
local densityGraphWidth = SCREEN_WIDTH - 120

-- Safe fallbacks for engine globals that may not exist in all contexts
local function getCurRateValue()
	local ok, rate = pcall(function()
		return GAMESTATE:GetSongOptionsObject("ModsLevel_Preferred"):MusicRate()
	end)
	return (ok and type(rate) == "number") and rate or 1.0
end

local function changeMusicRate(delta)
	local curRate = getCurRateValue()
	-- Round to 2 dp to avoid floating-point drift (matches adjustRate in song select)
	local newRate = math.floor((curRate + delta) * 100 + 0.5) / 100
	newRate = math.max(0.05, math.min(3.0, newRate))
	pcall(function()
		GAMESTATE:GetSongOptionsObject("ModsLevel_Preferred"):MusicRate(newRate)
		GAMESTATE:GetSongOptionsObject("ModsLevel_Song"):MusicRate(newRate)
		GAMESTATE:GetSongOptionsObject("ModsLevel_Current"):MusicRate(newRate)
	end)
	MESSAGEMAN:Broadcast("CurrentRateChanged", {rate = newRate, oldRate = curRate})
end

-- References for sync
local cdgFrameRef = nil
local noteCanvas
local noteSprite
local hasNoteFrame = false
local rootRef = nil
local cdgInfoTimeRef = nil
local cdgInfoBPMRef  = nil
local cdgInfoNPSRef  = nil

local npsTooltipActor
local msdTooltipActor
local isPaused = false
local reachedEnd = false
local previewPosition = 0
local previewAudioPath
local previewEnd
local requestedPosition
local requestedAt
local lastPositionAt
local previousRedirection
local returnScreen
local readyAt = 0
local lastDirection
local lastDirectionAt

local function hoveredChartPosition()
	local clickArea = cdgFrameRef and cdgFrameRef:GetChild("ClickArea")
	if not clickArea or not isOver(clickArea) then return end
	local width = clickArea:GetZoomedWidth()
	if width <= 0 then return end
	local left = clickArea:GetTrueX() - width * clickArea:GetHAlign()
	local fraction = (INPUTFILTER:GetMouseX() - left) / width
	return math.max(0, math.min(1, fraction)) * musicLength
end

local function applyPreviewPosition(pos)
	local proportion = pos / musicLength

	if cdgFrameRef then
		local seek = cdgFrameRef:GetChild("ProgressMarker")
		if seek then
			seek:x((proportion - 0.5) * densityGraphWidth)
		end
	end
end

local function ownsPreview()
	return HV.ChartPreviewActive and ssm and ssm == SCREENMAN:GetTopScreen() and not ssm:IsTransitioning()
end

local function validMusicPath(path)
	return path and path ~= "" and FILEMAN:DoesFileExist(path)
end

local function getPreviewAudioPath(song, steps)
	local path = steps:GetPreviewMusicPath()
	local songMusic = song:GetMusicPath()
	if path == song:GetPreviewMusicPath() and validMusicPath(songMusic) then
		return songMusic
	end
	return path
end

local function getPreviewEnd()
	if previewAudioPath == song:GetMusicPath() then
		local soundLength = song:MusicLengthSeconds()
		if soundLength > 0 then return math.min(musicLength, soundLength) end
	end
	return musicLength
end

local function finishPreview()
	previewPosition = previewEnd
	requestedPosition = nil
	reachedEnd = true
	SOUND:StopMusic()
end

local function playFrom(position)
	local start = math.max(0, math.min(position, previewEnd))
	if previewEnd - start <= 0.05 * getCurRateValue() then
		finishPreview()
		return
	end
	reachedEnd = false
	previewPosition = start
	requestedPosition = start
	requestedAt = GetTimeSinceStart()
	lastPositionAt = nil
	-- Queue an offset in the new play request so it never refers to the old sound.
	SOUND:PlayMusicPart(previewAudioPath, start, previewEnd - start, 0, 0, false, true, false)
end

local function playPreview()
	local start = song:GetSampleStart()
	if start < 0 or previewEnd - start < 1 then start = 0 end
	playFrom(start)
end

-- Helper: format seconds as m:ss.x
local function formatTime(s)
	if not s or s < 0 then return "-:--" end
	local m = math.floor(s / 60)
	local sec = s - m * 60
	return string.format("%d:%04.1f", m, sec)
end

-- HV Aesthetics constants
local accentColor = HVColor.Accent
local textDim = HVColor.TextDim
local textSub = HVColor.TextSub
local textMain = HVColor.Text
local textBright = HVColor.TextBright
local bgCard = HVColor.BG2
local bgDark = HVColor.BG1

-- Layout constants
local sidePanelWidth = 140
local headerHeight = 60
local footerHeight = 100
local innerPadding = 10
local frameWidth = SCREEN_WIDTH - (sidePanelWidth * 2) - (innerPadding * 4)
local frameHeight = SCREEN_HEIGHT - headerHeight - footerHeight - (innerPadding * 4)

local function updateNoteDisplay(synchronized)
	local drawing = synchronized ~= false and not isPaused and not reachedEnd and not requestedPosition
	noteCanvas:visible(drawing)
	noteSprite:visible(hasNoteFrame)
end

-- Helper: Steps identification
local stepsTable = {}
local curStepIndex = 0

local function findCurStepIndex(givenSteps)
	if not givenSteps then return 0 end
	for i = 1, #stepsTable do
		if stepsTable[i]:GetChartKey() == givenSteps:GetChartKey() then
			return i
		end
	end
	return 0
end

local function meterComparator(stepA, stepB)
	return Enum.Reverse(Difficulty)[stepA:GetDifficulty()] < Enum.Reverse(Difficulty)[stepB:GetDifficulty()]
end

-- HV Helper fallbacks
local function getDifficultyShort(diff)
	local d = ToEnumShortString(diff):gsub("Difficulty_", "")
	local map = {
		Beginner = "BG",
		Easy = "EZ",
		Medium = "MD",
		Hard = "HD",
		Challenge = "CH",
		Edit = "ED"
	}
	return map[d] or d:sub(1,2):upper()
end

local function getDifficultyColor(diff)
	return HVColor and HVColor.GetDifficultyColor(diff) or textBright
end

local function GetCustomDifficulty(stype, diff)
	return diff
end

local function getSongLengthColor(len)
	return HVColor and HVColor.GetSongLengthColor(len) or textBright
end

function getMSDColor(msd)
	if not msd or msd == 0 then return textDim end
	return (HVColor and HVColor.GetMSDRatingColor) and HVColor.GetMSDRatingColor(msd) or textBright
end


------------------------------------------------------------
-- AUDIO CONTROL & SYNC
------------------------------------------------------------
local function bpmAt(position, rate)
	local timing = steps:GetTimingData()
	local beat = timing:GetBeatFromElapsedTime(position)
	return timing:GetBPMAtBeat(beat) * rate
end

local function updatePlaybackPosition()
	if isPaused or reachedEnd or SOUND:GetMusicPath() ~= previewAudioPath then return false end

	local position = ssm:GetSampleMusicPosition()
	local now, rate = GetTimeSinceStart(), getCurRateValue()
	if requestedPosition then
		local expectedPosition = requestedPosition + (now - requestedAt) * rate
		if SOUND:IsTimingDelayed() or position < requestedPosition or position > expectedPosition + 0.5 then
			-- A very short tail can finish before the first accurate clock sample.
			if position >= previewEnd and expectedPosition >= previewEnd + 0.5 then finishPreview() end
			return false
		end
		requestedPosition = nil
	end
	if position < previewPosition then
		-- Etterna can loop files with "loop" in their path even without force loop.
		if lastPositionAt and previewPosition + (now - lastPositionAt) * rate >= previewEnd then
			finishPreview()
		end
		return false
	end
	if position >= previewEnd then
		finishPreview()
		return false
	end
	previewPosition, lastPositionAt = position, now
	return true
end

local function updateSync()
	if not ownsPreview() then return end

	updateNoteDisplay(updatePlaybackPosition())
	local pos = previewPosition
	applyPreviewPosition(pos)

	local hovered = hoveredChartPosition()
	local chartTime = hovered or pos
	-- Sample Music Position and the seek API use chart seconds. Density bins use playback seconds.
	local playbackTime = loadedRate and chartTime / loadedRate
	local nps = playbackTime and chartDensity.At(densityVectors, playbackTime)
	local npsText = nps and string.format("%.1f NPS", nps) or "-"

	if npsTooltipActor then
		npsTooltipActor:visible(hovered ~= nil)
		if hovered then
			npsTooltipActor:xy(INPUTFILTER:GetMouseX() + 15, INPUTFILTER:GetMouseY() - 35)
			npsTooltipActor:GetChild("NPSText"):settext(npsText)
		end
	end

	if steps and playbackTime and cdgInfoTimeRef and cdgInfoBPMRef and cdgInfoNPSRef then
		cdgInfoTimeRef:settext(formatTime(playbackTime)):diffuse(hovered and accentColor or textDim)
		cdgInfoBPMRef:settextf("%.0f BPM", bpmAt(chartTime, loadedRate)):diffuse(hovered and accentColor or textSub)
		cdgInfoNPSRef:settext(npsText):diffuse(hovered and accentColor or textSub)
	end

	-- MSD Tooltip hover check
	if msdTooltipActor and rootRef and rootRef:GetVisible() then
		local rightSidebar = rootRef:GetChild("RightSidebar")
		local chartPanelRef = rightSidebar and rightSidebar:GetChild("ChartPanel")
		local hoveredSteps = nil
		if chartPanelRef and chartPanelRef:GetVisible() then
			local list = chartPanelRef:GetChild("List")
			if list then
				local diffs = {"Beginner", "Easy", "Medium", "Hard", "Challenge", "Edit"}
				for _, d in ipairs(diffs) do
					local short = getDifficultyShort("Difficulty_"..d)
					local item = list:GetChild("Item_" .. short)
					if item then
						local clickArea = item:GetChild("ClickArea")
						if clickArea and clickArea:GetVisible() and isOver(clickArea) then
							hoveredSteps = chartPanelRef.available and chartPanelRef.available[d]
							break
						end
					end
				end
			end
		end
		
		if hoveredSteps and HV.ShowMSD() then
			local mx2, my2 = INPUTFILTER:GetMouseX(), INPUTFILTER:GetMouseY()
			msdTooltipActor:visible(true):xy(mx2 + 5, my2 - 15)
			msdTooltipActor:playcommand("SetHover", {steps = hoveredSteps})
		else
			msdTooltipActor:visible(false)
		end
	end
end

------------------------------------------------------------
-- INPUT HANDLING
------------------------------------------------------------
local function input(event)
	if not ownsPreview() or event.type ~= "InputEventType_FirstPress" then return end
	local btn = event.DeviceInput.button
	local button = event.GameButton or event.button
	local direction = (button == "MenuUp" or button == "Up" or btn == "DeviceButton_up") and -1
		or (button == "MenuDown" or button == "Down" or btn == "DeviceButton_down") and 1
	local now = GetTimeSinceStart()
	if direction then
		if direction == lastDirection and now - lastDirectionAt <= 0.6 then
			lastDirection = nil
			ssm:ChangeSteps(direction)
		else
			lastDirection, lastDirectionAt = direction, now
		end
		return
	end
	lastDirection = nil

	if button == "EffectUp" then
		changeMusicRate(0.05)
		return
	elseif button == "EffectDown" then
		changeMusicRate(-0.05)
		return
	end

	-- Mouse Interaction
	if btn == "DeviceButton_left mouse button" then
		if not rootRef or not rootRef:GetVisible() then return false end

		-- Difficulty Selection (New Location: RightSidebar -> ChartPanel)
		local chartPanelRef = rootRef:GetChild("RightSidebar"):GetChild("ChartPanel")
		if chartPanelRef then
			local list = chartPanelRef:GetChild("List")
			local diffs = {"Beginner", "Easy", "Medium", "Hard", "Challenge", "Edit"}
			for i, d in ipairs(diffs) do
				local short = getDifficultyShort("Difficulty_"..d)
				local item = list:GetChild("Item_" .. short)
				if item and isOver(item:GetChild("ClickArea")) then
					local s = chartPanelRef.available and chartPanelRef.available[d]
					if s then
						GAMESTATE:SetCurrentSteps(PLAYER_1, s)
						return true
					end
				end
			end
		end

		-- Rate Control
		local rateFrame = rootRef:GetChild("HeaderFrame"):GetChild("RateController")
		if rateFrame then
			if isOver(rateFrame:GetChild("Dec")) then 
				changeMusicRate(-0.05)
				return true 
			end
			if isOver(rateFrame:GetChild("Inc")) then 
				changeMusicRate(0.05)
				return true 
			end
		end

		local position = hoveredChartPosition()
		if position then
			if isPaused then
				previewPosition = math.min(position, previewEnd)
			else
				playFrom(position)
				updateNoteDisplay()
			end
			applyPreviewPosition(previewPosition)
			return true
		end
	end

	if btn == "DeviceButton_right mouse button" then
		if reachedEnd then
			playFrom(0)
		elseif isPaused then
			isPaused = false
			playFrom(previewPosition)
		else
			updatePlaybackPosition()
			if not reachedEnd then
				isPaused = true
				requestedPosition = nil
				SOUND:StopMusic()
			end
		end
		updateNoteDisplay()
		local text = rootRef:GetChild("NoteFieldContainer"):GetChild("PausedText")
		text:diffusealpha(isPaused and 1 or 0)
	end
end

------------------------------------------------------------
-- UI COMPONENTS
------------------------------------------------------------

-- 1. HEADER (Song Info + Diff + Rate)
local function header()
	return Def.ActorFrame {
		Name = "HeaderFrame",
		InitCommand = function(self) self:xy(SCREEN_CENTER_X, 40) end,
		ReloadCommand = function(self) self:RunCommandsOnChildren(function(c) c:playcommand("Reload") end) end,
		-- Glassmorphism Base
		Def.Quad { InitCommand = function(self) self:zoomto(SCREEN_WIDTH - 40, 60):diffuse(bgCard):diffusealpha(0.9) end },
		Def.Quad { InitCommand = function(self) self:zoomto(SCREEN_WIDTH - 40, 1):valign(0):y(-30):diffuse(accentColor):diffusealpha(0.5) end },
		
		-- Song Data
		Def.ActorFrame {
			Name = "SongInfo",
			InitCommand = function(self) self:x(-(SCREEN_WIDTH-40)/2 + 20) end,
			LoadFont("Common Normal") .. {
				Name = "Title",
				ReloadCommand = function(self) self:settext(song:GetMainTitle()):zoom(0.6):halign(0):y(-10):diffuse(textBright) end
			},
			LoadFont("Common Normal") .. {
				Name = "Artist",
				ReloadCommand = function(self) self:settext(song:GetDisplayArtist()):zoom(0.35):halign(0):y(10):diffuse(textSub) end
			}
		},

		-- Rate Controller
		Def.ActorFrame {
			Name = "RateController",
			InitCommand = function(self) self:x((SCREEN_WIDTH-40)/2 - 100) end,
			Def.Quad { Name = "Dec", InitCommand = function(self) self:x(-60):zoomto(30, 40):diffusealpha(0) end },
			Def.Quad { Name = "Inc", InitCommand = function(self) self:x(60):zoomto(30, 40):diffusealpha(0) end },
			LoadFont("Common Normal") .. { InitCommand = function(self) self:x(-60):settext("<"):zoom(0.6):diffuse(textDim) end },
			LoadFont("Common Normal") .. { InitCommand = function(self) self:x(60):settext(">"):zoom(0.6):diffuse(textDim) end },
			LoadFont("Common Normal") .. {
				Name = "RateVal",
				ReloadCommand = function(self) 
					local rate = getCurRateValue()
					self:settextf("%.2fx", rate):zoom(0.5):diffuse(accentColor)
				end
			},
			LoadFont("Common Normal") .. {
				Name = "BPM",
				ReloadCommand = function(self)
					local curSong = song or GAMESTATE:GetCurrentSong()
					if curSong then
						local rate = getCurRateValue()
						local bpms = curSong:GetDisplayBpms(true)
						local b1 = bpms[1] * rate
						local b2 = bpms[2] * rate
						if math.abs(b1 - b2) < 1 then
							self:settext(string.format("%.0f BPM", b1)):y(18):zoom(0.25):diffuse(textDim)
						else
							self:settext(string.format("%.0f-%.0f BPM", b1, b2)):y(18):zoom(0.25):diffuse(textDim)
						end
					else
						self:settext("--- BPM"):y(18):zoom(0.25):diffuse(textDim)
					end
				end
			}
		},

	}
end

-- 2. SIDEBARS (Skillsets & Analysis)
local function skillsetPanel()
	local skillsets = {"Overall", "Stream", "Jumpstream", "Handstream", "Stamina", "JackSpeed", "Chordjack", "Technical"}
	return Def.ActorFrame {
		Name = "SkillsetPanel",
		InitCommand = function(self)
			self:visible(HV.ShowMSD())
		end,
		Def.Quad { InitCommand = function(self) self:zoomto(sidePanelWidth, 240):diffuse(bgCard):diffusealpha(0.8) end },
		LoadFont("Common Normal") .. { InitCommand = function(self) self:y(-135):settext("SKILLSETS"):zoom(0.4):diffuse(accentColor) end },
		Def.ActorFrame {
			Name = "Grid",
			InitCommand = function(self) self:y(-110) end,
		} .. (function()
			local rows = {}
			for i, ss in ipairs(skillsets) do
				rows[#rows+1] = Def.ActorFrame {
					Name = "Row"..i,
					InitCommand = function(self) self:y((i-1)*30) end,
					LoadFont("Common Normal") .. { InitCommand = function(self) self:halign(0):x(-sidePanelWidth/2 + 10):settext(ss:upper()):zoom(0.25):diffuse(textSub) end },
					LoadFont("Common Normal") .. {
						Name = "Val",
						ReloadCommand = function(self)
							local val = steps:GetMSD(getCurRateValue(), i)
							if val > 0 then
								self:settextf("%.2f", val):diffuse(HVColor.GetMSDRatingColor(val))
							else
								self:settext("-"):diffuse(textDim)
							end
							self:halign(1):x(sidePanelWidth/2 - 10):zoom(0.35)
						end
					}
				}
			end
			return rows
		end)()
	}
end

local function radarPanel()
	local categories = {
		{"TAPS", "RadarCategory_Notes"}, {"JUMPS", "RadarCategory_Jumps"}, {"HANDS", "RadarCategory_Hands"},
		{"HOLDS", "RadarCategory_Holds"}, {"ROLLS", "RadarCategory_Rolls"}, {"MINES", "RadarCategory_Mines"}
	}
	return Def.ActorFrame {
		Name = "RadarPanel",
		Def.Quad { InitCommand = function(self) self:zoomto(sidePanelWidth, 240):diffuse(bgCard):diffusealpha(0.8) end },
		LoadFont("Common Normal") .. { InitCommand = function(self) self:y(-135):settext("ANALYSIS"):zoom(0.4):diffuse(accentColor) end },
		Def.ActorFrame {
			Name = "Grid",
			InitCommand = function(self) self:y(-110) end,
		} .. (function()
			local rows = {}
			for i, c in ipairs(categories) do
				rows[#rows+1] = Def.ActorFrame {
					Name = "Row"..i,
					InitCommand = function(self) self:y((i-1)*30) end,
					LoadFont("Common Normal") .. { InitCommand = function(self) self:halign(0):x(-sidePanelWidth/2 + 10):settext(c[1]):zoom(0.25):diffuse(textSub) end },
					LoadFont("Common Normal") .. {
						Name = "Val",
						ReloadCommand = function(self)
							local val = steps:GetRadarValues(pn):GetValue(c[2])
							self:settext(val):halign(1):x(sidePanelWidth/2 - 10):zoom(0.35):diffuse(textBright)
						end
					}
				}
			end
			return rows
		end)()
	}
end

-- 2. CHART Panel (New Difficulty Selector)
local function chartPanel()
	local diffs = {"Beginner", "Easy", "Medium", "Hard", "Challenge", "Edit"}
	return Def.ActorFrame {
		Name = "ChartPanel",
		ReloadCommand = function(self)
			stepsTable = song:GetStepsByStepsType(steps:GetStepsType())
			self.available = {}
			for _, s in ipairs(stepsTable) do
				local dStr = ToEnumShortString(s:GetDifficulty()):gsub("Difficulty_", "")
				self.available[dStr] = s
			end
			self:RunCommandsOnChildren(function(c) c:playcommand("Update") end)
		end,

		LoadFont("Common Normal") .. { 
			InitCommand = function(self) self:y(-135):settext("CHART"):zoom(0.4):diffuse(accentColor) end 
		},

		Def.ActorFrame {
			Name = "List",
			InitCommand = function(self) self:y(-100) end,
		} .. (function()
			local items = {}
			for i, d in ipairs(diffs) do
				local short = getDifficultyShort("Difficulty_"..d)
				items[#items+1] = Def.ActorFrame {
					Name = "Item_" .. short,
					InitCommand = function(self) self:y((i-1)*30) end,
					
					Def.Quad {
						Name = "Bg",
						InitCommand = function(self) self:zoomto(sidePanelWidth - 10, 26):diffuse(bgDark):diffusealpha(0.8) end,
						UpdateCommand = function(self)
							local panel = self:GetParent():GetParent():GetParent()
							local s = panel.available and panel.available[d]
							local isCur = s and (s:GetChartKey() == steps:GetChartKey())
							if isCur then
								self:diffuse(HVColor.GetDifficultyColor(s:GetDifficulty())):diffusealpha(0.5)
							else
								self:diffuse(bgDark):diffusealpha(0.8)
							end
						end
					},

					LoadFont("Common Normal") .. {
						InitCommand = function(self) self:halign(0):x(-sidePanelWidth/2 + 10):settext(short):zoom(0.3):diffuse(textSub) end,
						UpdateCommand = function(self)
							local panel = self:GetParent():GetParent():GetParent()
							local s = panel.available and panel.available[d]
							self:diffuse(s and textBright or textDim)
						end
					},

					LoadFont("Common Normal") .. {
						Name = "Meter",
						InitCommand = function(self) self:halign(1):x(sidePanelWidth/2 - 10):zoom(0.3) end,
						UpdateCommand = function(self)
							local panel = self:GetParent():GetParent():GetParent()
							local s = panel.available and panel.available[d]
							if s then
								if HV.ShowMSD() then
									local val = s:GetMSD(getCurRateValue(), 1)
									self:settextf("%.2f", val):diffuse(HVColor.GetMSDRatingColor(val)):visible(true)
								else
									self:settext(tostring(s:GetMeter())):diffuse(textMain):visible(true)
								end
							else
								self:visible(false)
							end
						end
					},

					Def.Quad {
						Name = "ClickArea",
						InitCommand = function(self) self:zoomto(sidePanelWidth - 10, 26):diffusealpha(0) end,
						UpdateCommand = function(self)
							local panel = self:GetParent():GetParent():GetParent()
							local s = panel.available and panel.available[d]
							self:visible(s ~= nil)
						end
					}
				}
			end
			return items
		end)()
	}
end

-- 3. SIDEBARS (Skillsets & Analysis)
local function skillsetPanelComp()
	return skillsetPanel()
end

local function radarPanelComp()
	return radarPanel()
end

-- 3. CHORD DENSITY GRAPH
local function densityGraphComp()
	return Def.ActorFrame {
		Name = "CDGFrame",
		InitCommand = function(self) self:xy(SCREEN_CENTER_X, SCREEN_HEIGHT - 60); cdgFrameRef = self end,
		ReloadCommand = function(self) self:RunCommandsOnChildren(function(c) c:playcommand("Reload") end) end,
		-- BG
		Def.Quad { InitCommand = function(self) self:zoomto(densityGraphWidth, 80):diffuse(bgCard):diffusealpha(0.9) end },
		
		Def.Quad { Name = "ClickArea", InitCommand = function(self) self:zoomto(densityGraphWidth, 80):diffusealpha(0) end },

		-- Graph (AMV)
		Def.ActorMultiVertex {
			Name = "GraphAMV",
			ReloadCommand = function(self)
				local verts = {}
				if densityStats and densityStats.peak > 0 then
					local bins = #densityVectors[1]
					local binWidth = densityGraphWidth / (musicLength / loadedRate)
					local heightPerNote = 80 / densityStats.peak
					local columns = steps:GetNumColumns()

					for chordSize = 1, columns do
						local vector = densityVectors[chordSize] or {}
						local brightness = 0.2 + (columns - chordSize + 1) * 0.6 / columns
						local tint = color(brightness .. "," .. brightness .. "," .. brightness .. ",1")
						for bin = 1, bins do
							local left = (bin - 1) * binWidth
							if left >= densityGraphWidth then break end
							local count = vector[bin] or 0
							if count > 0 then
								local x = left - densityGraphWidth / 2
								local right = math.min(densityGraphWidth, bin * binWidth) - densityGraphWidth / 2
								local y = 40 - count * heightPerNote
								verts[#verts + 1] = {{x, 40, 0}, tint}
								verts[#verts + 1] = {{right, 40, 0}, tint}
								verts[#verts + 1] = {{right, y, 0}, tint}
								verts[#verts + 1] = {{x, y, 0}, tint}
							end
						end
					end
				end
				self:SetVertices(verts):SetDrawState({Mode = "DrawMode_Quads", First = 1, Num = #verts})
			end
		},

		-- Mean NPS Reference Line (drawn on top of graph)
		Def.ActorFrame {
			Name = "MeanNPSContainer",
			InitCommand = function(self)
				self:xy(-(densityGraphWidth)/2, 0)
				self:halign(0)
				self:z(1000)  -- Ensure it's above all other elements
			end,
			ReloadCommand = function(self)
				local show = densityStats ~= nil and densityStats.peak > 0
				self:visible(show)
				if show then
					self:y(40 - densityStats.denseMean / densityStats.peak * 80)
					self:GetChild("MeanNPSText"):settextf("%.1f", densityStats.denseMean)
				end
			end,

			-- The line (thicker with accent color)
			Def.Quad {
				Name = "MeanNPSLine",
				InitCommand = function(self)
					self:zoomto(densityGraphWidth, 2)
					self:diffuse(accentColor)
					self:diffusealpha(0.6)
					self:halign(0)
				end,
			},

			-- The text label (with accent color)
			LoadFont("Common Normal") .. {
				Name = "MeanNPSText",
				InitCommand = function(self)
					self:x(SCREEN_WIDTH - 130)
					self:y(-4)
					self:zoom(0.28)
					self:diffuse(accentColor)
					self:halign(1)
					self:settext("--")
				end
			}
		},

		-- ProgressMarker drawn AFTER the graph so it renders on top
		Def.Quad { Name = "ProgressMarker", InitCommand = function(self) self:x(-(densityGraphWidth)/2):zoomto(2, 80):diffuse(accentColor) end },

		-- Floating density value for the hovered playback second.
		Def.ActorFrame {
			Name = "NPSTooltip",
			InitCommand = function(self)
				npsTooltipActor = self
				self:visible(false)
				self:z(500)
			end,

			-- Background
			Def.Quad {
				InitCommand = function(self)
					self:zoomto(90, 26)
					self:diffuse(bgDark):diffusealpha(0.95)
					self:halign(0):valign(1)
				end
			},

			-- Border
			Def.Quad {
				InitCommand = function(self)
					self:zoomto(90, 2)
					self:y(-26)
					self:diffuse(accentColor)
					self:halign(0)
				end
			},

			-- Text
			LoadFont("Common Normal") .. {
				Name = "NPSText",
				InitCommand = function(self)
					self:halign(0):valign(0)
					self:x(5):y(-22)
					self:zoom(0.35)
					self:diffuse(accentColor)
					self:settext("-- NPS")
				end
			}
		},

		-- Info bar below CDG: centered TIME · BPM · NPS; accent color on hover
		Def.ActorFrame {
			Name = "CDGInfoBar",
			-- CDGFrame center is at SCREEN_HEIGHT-60; place bar 48px below that
			InitCommand = function(self) self:y(48) end,

			-- Time (left of center trio)
			LoadFont("Common Normal") .. {
				Name = "CDGInfoTime",
				InitCommand = function(self)
					self:halign(1):x(-90)
					self:zoom(0.3):diffuse(textDim):settext("-:--")
					cdgInfoTimeRef = self
				end
			},

			-- BPM (center)
			LoadFont("Common Normal") .. {
				Name = "CDGInfoBPM",
				InitCommand = function(self)
					self:halign(0.5):x(0)
					self:zoom(0.3):diffuse(textSub):settext("-- BPM")
					cdgInfoBPMRef = self
				end
			},

			-- NPS (right of center trio)
			LoadFont("Common Normal") .. {
				Name = "CDGInfoNPS",
				InitCommand = function(self)
					self:halign(0):x(90)
					self:zoom(0.3):diffuse(textSub):settext("-- NPS")
					cdgInfoNPSRef = self
				end
			},
		}
	}
end

-- ============================================================
-- MSD SKILLSET TOOLTIP
-- ============================================================
local tooltipW = 280
local tooltipH = 56

local msdTooltip = Def.ActorFrame {
	Name = "MSDTooltip",
	InitCommand = function(self)
		msdTooltipActor = self
		self:visible(false)
		self:z(1000)
	end,
	-- Background
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(1):zoomto(tooltipW, tooltipH):diffuse(bgDark):diffusealpha(0.95)
		end
	},
	-- Border
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(1):zoomto(tooltipW, 1):y(-tooltipH):diffuse(accentColor):diffusealpha(0.5)
		end
	}
}

local skillsetsList = {
	{name="Stream", idx=2}, {name="Jumpstream", idx=3}, {name="Handstream", idx=4}, {name="Stamina", idx=5},
	{name="JackSpeed", idx=6}, {name="Chordjack", idx=7}, {name="Technical", idx=8}
}

for i, ss in ipairs(skillsetsList) do
	local col, row, colW, offsetX
	if i <= 4 then
		row = 0
		col = i - 1
		colW = tooltipW / 4
		offsetX = col * colW + (colW / 2)
	else
		row = 1
		col = i - 5
		colW = tooltipW / 3
		offsetX = col * colW + (colW / 2)
	end

	local offsetY = -tooltipH + 12 + row * 24

	msdTooltip[#msdTooltip + 1] = Def.ActorFrame {
		InitCommand = function(self)
			self:xy(offsetX, offsetY)
		end,
		LoadFont("Common Normal") .. {
			InitCommand = function(self) self:y(-7):zoom(0.25):diffuse(textSub):settext(ss.name) end
		},
		LoadFont("Common Normal") .. {
			Name = "Val",
			InitCommand = function(self) self:y(5):zoom(0.35):diffuse(textMain) end,
			SetHoverCommand = function(self, params)
				if params.steps then
					local rate = getCurRateValue and getCurRateValue() or 1
					local msd = params.steps:GetMSD(rate, ss.idx)
					if msd and msd > 0 then
						self:settext(string.format("%.2f", msd)):diffuse(getMSDColor(msd))
					else
						self:settext("-"):diffuse(textDim)
					end
				else
					self:settext("-"):diffuse(textDim)
				end
			end
		}
	}
end

------------------------------------------------------------
-- ROOT ACTORFRAME
------------------------------------------------------------
local function restoreWheelAudio(screen)
	if screen:IsTransitioning() then return end
	if HV.LegacyPrefs.Get("HV_SongPreview") == 1 then
		SOUND:StopMusic()
		if GAMESTATE:GetCurrentSong() then
			screen:PlayCurrentSongSampleMusic(false, false)
		else
			screen:PlayLoopMusic()
		end
	end
	MESSAGEMAN:Broadcast("ChartPreviewOff")
end

local function closePreview(self, restoreAudio)
	if not HV.ChartPreviewActive or not ssm then return end
	local screen = ssm
	HV.ChartPreviewActive = false
	ssm = nil
	requestedPosition = nil
	lastDirection = nil
	densityVectors, densityStats = nil, nil
	loadedRate = nil
	self:visible(false)

	if screen == SCREENMAN:GetTopScreen() then
		SCREENMAN:set_input_redirected(PLAYER_1, previousRedirection)
		if restoreAudio then restoreWheelAudio(screen) end
	end
end

local function reloadPreviewChart(self)
	if not ownsPreview() then return end
	local selected = GAMESTATE:GetCurrentSteps()
	if GAMESTATE:GetCurrentSong() ~= song or not selected then
		closePreview(self, true)
		return
	end
	local rate = math.max(MIN_MUSIC_RATE, getCurRateValue())
	if selected == steps and loadedRate == rate then return end
	if selected ~= steps then hasNoteFrame = false end
	steps, loadedRate = selected, rate
	local path = getPreviewAudioPath(song, steps)
	if path ~= previewAudioPath then
		if not validMusicPath(path) then
			closePreview(self, true)
			return
		end
		previewAudioPath = path
		previewEnd = getPreviewEnd()
		if isPaused then previewPosition = math.min(previewPosition, previewEnd)
		else playPreview() end
	end
	densityVectors, densityStats = nil, nil
	local radar = steps:GetRadarValues(PLAYER_1)
	if radar and radar:GetValue("RadarCategory_TapsAndHolds") > 0 then
		densityVectors = steps:GetCDGraphVectors(rate)
		densityStats = chartDensity.Summarize(densityVectors)
	end
	self:RunCommandsOnChildren(function(child) child:playcommand("Reload") end)
	updateNoteDisplay()
end

local t = Def.ActorFrame {
	Name = "ChartPreviewRoot",
	InitCommand = function(self)
		rootRef = self
		self:SetUpdateFunction(function()
			local screen = SCREENMAN:GetTopScreen()
			if returnScreen and screen == returnScreen then
				returnScreen = nil
				SCREENMAN:set_input_redirected(PLAYER_1, previousRedirection)
				restoreWheelAudio(screen)
			elseif HV.ChartPreviewActive then
				if screen ~= ssm then
					returnScreen = ssm
					closePreview(self, false)
				elseif screen:IsTransitioning() then
					closePreview(self, false)
				else
					updateSync()
				end
			end
		end)
		self:visible(false)
	end,
	BeginCommand = function(self)
		local delay = tonumber(THEME:GetMetric("ScreenSelectMusic", "SampleMusicDelayInit")) or 0
		readyAt = GetTimeSinceStart() + delay
	end,
	ToggleChartPreviewCommand = function(self)
		if HV.ChartPreviewActive then
			closePreview(self, true)
			return
		end

		local screen = SCREENMAN:GetTopScreen()
		local selectedSong = GAMESTATE:GetCurrentSong()
		local selectedSteps = GAMESTATE:GetCurrentSteps()
		if not screen or screen:GetName() ~= "ScreenSelectMusic" or screen:IsTransitioning()
			or not selectedSong or not selectedSteps or GetTimeSinceStart() < readyAt then return end
		local wheel = screen:GetMusicWheel()
		if not wheel:IsSettled() or wheel:GetSelectedType() ~= "WheelItemDataType_Song" then return end

		local path = getPreviewAudioPath(selectedSong, selectedSteps)
		local length = selectedSong:GetLastSecond()
		if not validMusicPath(path) or length <= 0 then return end

		ssm, song, musicLength, previewAudioPath = screen, selectedSong, length, path
		previewEnd = getPreviewEnd()
		returnScreen = nil
		loadedRate = nil
		isPaused = false
		hasNoteFrame = false
		lastDirection = nil
		previousRedirection = SCREENMAN:get_input_redirected(PLAYER_1)
		SCREENMAN:set_input_redirected(PLAYER_1, true)
		HV.ChartPreviewActive = true
		self:GetChild("NoteFieldContainer"):GetChild("PausedText"):diffusealpha(0)
		self:visible(true)
		MESSAGEMAN:Broadcast("ChartPreviewOn")
		playPreview()
		reloadPreviewChart(self)
	end,
	PreviewInputCommand = function(self, event)
		input(event)
	end,
	CloseChartPreviewCommand = function(self)
		closePreview(self, true)
	end,
	EndCommand = function(self)
		returnScreen = nil
		closePreview(self, false)
	end,
	CurrentSongChangedMessageCommand = function(self)
		if HV.ChartPreviewActive and GAMESTATE:GetCurrentSong() ~= song then
			closePreview(self, true)
		end
	end,
	CurrentStepsChangedMessageCommand = function(self)
		if HV.ChartPreviewActive then self:queuecommand("ReloadPreviewChart") end
	end,
	CurrentRateChangedMessageCommand = function(self)
		if HV.ChartPreviewActive then self:queuecommand("ReloadPreviewChart") end
	end,
	ReloadPreviewChartCommand = reloadPreviewChart,

	-- Screen Dim & Input Guard
	Def.Quad { InitCommand = function(self) self:FullScreen():diffuse(color("0,0,0,0.85")) end },
	Def.Quad { Name = "InputGuard", InitCommand = function(self) self:FullScreen():diffusealpha(0) end },

	-- Main Components
	header(),
	
	-- Sidebar (Left): Skillsets (Far Left)
	Def.ActorFrame {
		Name = "LeftSidebar",
		InitCommand = function(self) self:xy(sidePanelWidth/2 + 20, SCREEN_CENTER_Y) end,
		skillsetPanelComp()
	},

	densityGraphComp(),

	Def.ActorFrame {
		Name = "NoteFieldContainer",
		InitCommand = function(self) self:xy(SCREEN_CENTER_X, SCREEN_CENTER_Y - 40) end,
		ReloadCommand = function(self) self:RunCommandsOnChildren(function(c) c:playcommand("Reload") end) end,
		Def.Quad { InitCommand = function(self) self:zoomto(frameWidth, frameHeight):diffuse(bgDark):diffusealpha(0.5) end },
		Def.ActorFrameTexture {
			Name = "NoteFieldCanvas",
			InitCommand = function(self)
				noteCanvas = self
				self:setsize(frameWidth, frameHeight):EnableAlphaBuffer(true):EnableDepthBuffer(true):Create():visible(false)
				self:SetDrawFunction(function(canvas)
					canvas:GetChild("NoteField"):Draw()
					hasNoteFrame = true
					if noteSprite then noteSprite:visible(true) end
				end)
			end,
			Def.NoteFieldPreview {
				Name = "NoteField",
				DrawDistanceBeforeTargetsPixels = 1200, DrawDistanceAfterTargetsPixels = 0,
				InitCommand = function(self) self:xy(frameWidth / 2, frameHeight / 2):zoom(0.7) end,
				ReloadCommand = function(self) if steps then self:LoadNoteData(steps) end end,
			},
		},
		Def.Sprite {
			Name = "NoteFieldImage",
			InitCommand = function(self)
				noteSprite = self
				self:visible(false)
			end,
			OnCommand = function(self) self:SetTexture(noteCanvas:GetTexture()):zoomto(frameWidth, frameHeight) end,
		},
		Def.Quad { InitCommand = function(self) self:zoomto(frameWidth, 1):y(-frameHeight/2):diffuse(accentColor):diffusealpha(0.3) end },
		Def.Quad { InitCommand = function(self) self:zoomto(frameWidth, 1):y(frameHeight/2):diffuse(accentColor):diffusealpha(0.3) end },
		
		LoadFont("Common Large") .. {
			Name = "PausedText",
			InitCommand = function(self) self:settext("PAUSED"):zoom(0.5):diffuse(color("1,0.2,0.2,1")):diffusealpha(0):shadowlength(1):shadowcolor(0,0,0,1) end
		}
	},

	-- Right Area: CHART + ANALYSIS (Moved to end for draw order)
	Def.ActorFrame {
		Name = "RightSidebar",
		InitCommand = function(self) self:xy(SCREEN_WIDTH - 20, SCREEN_CENTER_Y):SortByDrawOrder() end,
		
		-- CHART (Difficulty Selector) - To the left of Radar
		chartPanel() .. { InitCommand = function(self) self:x(-sidePanelWidth * 1.5 - innerPadding):draworder(1000) end },
		
		-- ANALYSIS (Radar) - Far Right
		radarPanelComp() .. { InitCommand = function(self) self:x(-sidePanelWidth/2) end },
	},

	-- Tooltip (drawn last for z-order)
	msdTooltip
}

return t
