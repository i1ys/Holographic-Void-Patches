local selection, x, y, visibleRows = ...
local rowWidth, rowHeight = 64, 26
local rowStep = rowHeight + 3
local firstRowY = 16
local shortLabels = {Beginner = "BG", Easy = "EZ", Medium = "MD", Hard = "HD", Challenge = "CH", Edit = "ED"}
local accentColor = HVColor.Accent
local dimText = color("0.45,0.45,0.45,1")
local mainText = color("0.85,0.85,0.85,1")
local rowColor = color("0.08,0.08,0.08,1")
local placeholderColor = color("0.05,0.05,0.05,1")

local function getRow(index)
	return selection.displayCharts[index + selection.chartOffset]
end

local function getScrollDirection(button)
	if button == "DeviceButton_mousewheel up" and selection.chartOffset > 0 then return -1 end
	if button == "DeviceButton_mousewheel down" and selection.chartOffset < #selection.displayCharts - visibleRows then
		return 1
	end
end

local function styleModeSupportsSingleDoubleToggle()
	local game = GAMESTATE:GetCurrentGame()
	local gameName = game and game.GetName and game:GetName() or ""
	gameName = tostring(gameName):lower()
	return gameName == "dance" or gameName == "beat"
end

local selector = Def.ActorFrame {
	Name = "DifficultySelector",
	InitCommand = function(self) self:xy(x, y) end,
	BeginCommand = function(self)
		local screen = SCREENMAN:GetTopScreen()
		if self.inputScreen or not screen or screen:GetName() ~= "ScreenSelectMusic" then return end

		local function getMouseRowPosition()
			if self.inputScreen ~= screen or SCREENMAN:GetTopScreen() ~= screen or screen:IsTransitioning()
				or HV.ChartPreviewActive or (HV.ActiveTab and HV.ActiveTab ~= "") then return end
			local song = selection.renderedSong
			if not song or song ~= GAMESTATE:GetCurrentSong() or selection.renderedRate ~= getCurRateValue() then return end

			local mx = INPUTFILTER:GetMouseX()
			local rowY = INPUTFILTER:GetMouseY() - y - firstRowY
			if mx >= x and mx <= x + rowWidth and rowY >= 0 and rowY <= (visibleRows - 1) * rowStep + rowHeight then
				return rowY
			end
		end

		self.inputScreen = screen
		self.capturesScroll = function(button)
			return getScrollDirection(button) ~= nil and getMouseRowPosition() ~= nil
		end
		HV.CapturesDifficultyScroll = self.capturesScroll
		self.inputCallback = function(event)
			if not event or not event.DeviceInput or event.type ~= "InputEventType_FirstPress" then return false end
			local rowY = getMouseRowPosition()
			if not rowY then return false end
			local button = event.DeviceInput.button

			if button == "DeviceButton_left mouse button" and rowY % rowStep <= rowHeight then
				local entry = getRow(math.floor(rowY / rowStep) + 1)
				if entry and entry.steps then
					GAMESTATE:SetPreferredDifficulty(PLAYER_1, entry.steps:GetDifficulty())
					GAMESTATE:SetCurrentSteps(PLAYER_1, entry.steps)
					return true
				end
			end

			local direction = getScrollDirection(button)
			if direction then
				selection.chartOffset = selection.chartOffset + direction
				MESSAGEMAN:Broadcast("ChartListUpdate")
				return true
			end
			return false
		end
		screen:AddInputCallback(self.inputCallback)
	end,
	OffCommand = function(self)
		if self.inputScreen then self.inputScreen:RemoveInputCallback(self.inputCallback) end
		if HV.CapturesDifficultyScroll == self.capturesScroll then HV.CapturesDifficultyScroll = nil end
		self.inputScreen, self.inputCallback, self.capturesScroll = nil, nil, nil
	end,

	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:halign(0):valign(0):zoom(0.28):diffuse(accentColor)
				:settext(THEME:GetString("ScreenSelectMusic", "Chart"))
		end,
	},

	Def.ActorFrame {
		Name = "StyleToggle",
		InitCommand = function(self) self:xy(rowWidth - 25, 0) end,
		ChartListUpdateMessageCommand = function(self)
			local show = styleModeSupportsSingleDoubleToggle() and selection.hasSingle and selection.hasDouble
			self:visible(show == true)
			if not show then return end

			local style = GAMESTATE:GetCurrentStyle()
			local name = style and style:GetName()
			self:GetChild("Single"):diffuse(name == "single" and accentColor or dimText)
			self:GetChild("Double"):diffuse(name == "double" and accentColor or dimText)
		end,
		LoadFont("Common Normal") .. {
			Name = "Single",
			InitCommand = function(self) self:zoom(0.28):settext("S") end,
		},
		LoadFont("Common Normal") .. {
			Name = "Double",
			InitCommand = function(self) self:x(12):zoom(0.28):settext("D") end,
		},
	},
}

for i = 1, visibleRows do
	selector[#selector + 1] = Def.ActorFrame {
		Name = "DiffSlot_" .. i,
		InitCommand = function(self) self:y(firstRowY + (i - 1) * rowStep):visible(false) end,
		ChartListUpdateMessageCommand = function(self)
			local entry = getRow(i)
			self:visible(entry ~= nil)
			if not entry then return end

			local bg = self:GetChild("Bg")
			local label = self:GetChild("Label")
			local author = self:GetChild("Author")
			local rating = self:GetChild("MSDVal")
			label:settext(shortLabels[entry.difficulty] or "??"):diffusealpha(entry.isPlaceholder and 0.2 or 1)

			local steps = entry.steps
			if not steps then
				bg:diffuse(placeholderColor):diffusealpha(0.3)
				author:settext("")
				rating:settext("")
				return
			end

			local tint, alpha = rowColor, 1
			if selection.steps == steps then
				local difficulty = entry.difficulty
				tint = (HVColor.GetDifficultyColor and HVColor.GetDifficultyColor(difficulty))
					or (HVColor.Difficulty and HVColor.Difficulty[difficulty]) or accentColor
				alpha = 0.4
			end
			bg:diffuse(tint):diffusealpha(alpha)
			author:settext(entry.author)

			local msd = steps:GetMSD(selection.rate, 1)
			if msd and msd > 0 then
				rating:settextf("%.2f", msd):diffuse(HVColor.GetMSDRatingColor(msd))
			else
				rating:settext("-"):diffuse(dimText)
			end
		end,
		Def.Quad {
			Name = "Bg",
			InitCommand = function(self) self:halign(0):valign(0):zoomto(rowWidth, rowHeight):diffuse(rowColor) end,
		},
		LoadFont("Common Normal") .. {
			Name = "Label",
			InitCommand = function(self) self:halign(0):valign(0.5):xy(5, 13):zoom(0.30):diffuse(mainText) end,
		},
		LoadFont("Common Normal") .. {
			Name = "Author",
			InitCommand = function(self) self:halign(0):valign(0.5):xy(5, 20):zoom(0.25):diffuse(dimText) end,
		},
		LoadFont("Common Normal") .. {
			Name = "MSDVal",
			InitCommand = function(self)
				self:halign(1):valign(0.5):xy(rowWidth - 5, rowHeight / 2):zoom(0.30):diffuse(dimText)
			end,
		},
	}
end

return selector
