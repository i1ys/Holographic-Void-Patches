--- Holographic Void: Filters Tab
-- Rebuilt from Til Death's implementation using UIElements for proper mouse/keyboard input.
-- Uses FILTERMAN singleton for per-skillset MSD filtering, rate bounds, filter mode, and wheel refresh.

local focus = ...
local accentColor = HVColor.Accent
local dimText = color("0.45,0.45,0.45,1")
local subText = color("0.65,0.65,0.65,1")
local mainText = color("0.85,0.85,0.85,1")
local brightText = color("1,1,1,1")
local bgCard = color("0.04,0.04,0.04,0.97")

local overlayW = 680
local overlayH = 400
local active = false

local hoverAlpha = 0.6
local textzoom = 0.40
local spacingY = 25
local totalRows = #ms.SkillSets + 2
local ActiveSS, activebound = 0, 0
local boundText = ""
local filterRefreshActor

local function refreshWheel(defer)
	filterRefreshActor:stoptweening()
	if defer then
		filterRefreshActor:sleep(0.12):queuecommand("RefreshWheel")
	else
		filterRefreshActor:playcommand("RefreshWheel")
	end
end

local function formatBound(value)
	return string.format("%.3f", value):gsub("0+$", ""):gsub("%.$", "")
end

local function beginEdit(row, bound)
	ActiveSS, activebound = row, bound
	boundText = formatBound(FILTERMAN:GetSSFilter(row, bound))
	MESSAGEMAN:Broadcast("HV_NumericInputActive")
end

local function setBoundLabel(self, row, bound)
	local editing = ActiveSS == row and activebound == bound
	local value = FILTERMAN:GetSSFilter(row, bound)
	self:settext(editing and boundText or formatBound(value))
	self:diffuse(value <= 0 and not editing and dimText or brightText)
end

local function finishEdit(apply)
	if ActiveSS == 0 then return end
	ActiveSS, activebound = 0, 0
	if apply then refreshWheel(false) end
	MESSAGEMAN:Broadcast("HV_NumericInputEnded")
end

-- Numeric input handler (runs when a filter cell is being edited)
local function FilterInput(event)
	if event.type == "InputEventType_Release" or ActiveSS == 0 or not active then return end
	local button = event.DeviceInput.button or ""
	local logical = event.GameButton or event.button
	if logical == "Start" or logical == "Back" or button == "DeviceButton_escape"
		or button == "DeviceButton_enter" or button == "DeviceButton_kp enter" then
		if event.type == "InputEventType_FirstPress" then
			focus.hold(event)
			finishEdit(true)
		end
		return
	end

	local text = boundText
	if button == "DeviceButton_backspace" then
		text = text:sub(1, -2)
	elseif button == "DeviceButton_delete" then
		text = ""
	else
		local digit = button:match("^DeviceButton_(%d)$") or button:match("^DeviceButton_kp (%d)$")
		local decimal = ActiveSS == totalRows and (button == "DeviceButton_period" or event.char == ".")
		if decimal and not text:find(".", 1, true) then
			text = (text == "" and "0" or text) .. "."
		elseif digit then
			if text == "0" then text = "" end
			text = text .. digit
			if ActiveSS < totalRows then
				local limit = ActiveSS <= #ms.SkillSets and 2 or 3
				if #text > limit then text = digit end
			else
				local fraction = text:match("%.(%d*)$")
				if tonumber(text) > 100 or (fraction and #fraction > 3) then return end
			end
		else
			return
		end
	end
	boundText = text
	local value = tonumber(text) or 0
	if value ~= FILTERMAN:GetSSFilter(ActiveSS, activebound) then
		FILTERMAN:SetSSFilter(value, ActiveSS, activebound)
		refreshWheel(true)
	end
	MESSAGEMAN:Broadcast("HV_FilterUpdated")
end

-- Layout constants
local cellW = 50
local cellH = 20
local rowStartY = 55
local labelColX = 20
local minColX = overlayW / 2 + 20
local maxColX = minColX + cellW + 16

-- Build the UI
local t = Def.ActorFrame {
	Def.Actor {
		InitCommand = function(self) filterRefreshActor = self end,
		RefreshWheelCommand = function() if HV.RefreshMusicSearch then HV.RefreshMusicSearch() end end,
		OffCommand = function(self) self:stoptweening() end,
	},
	Name = "FiltersOverlay",
	InitCommand = function(self)
		self:xy(SCREEN_CENTER_X, SCREEN_CENTER_Y):visible(false)
	end,
	SelectMusicTabChangedMessageCommand = function(self, params)
		local wasActive = active
		active = params.Tab == "FILTERS"
		self:visible(active)
		if active and not wasActive then
			self:stoptweening():diffusealpha(0):linear(0.2):diffusealpha(1)
			self:playcommand("Set")
		elseif not active then
			finishEdit(false)
		end
	end,
	OffCommand = function()
		active = false
		finishEdit(false)
	end,

	MouseRightClickMessageCommand = function()
		if active and focus.isCurrent() then finishEdit(true) end
	end,

	-- Background card
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(overlayW, overlayH):diffuse(bgCard)
		end,
	},
	-- Accent bar at top
	Def.Quad {
		InitCommand = function(self)
			self:valign(0):y(-overlayH / 2):zoomto(overlayW, 2):diffuse(accentColor):diffusealpha(0.7)
		end,
	},

	-- Title
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(-overlayW / 2 + 20, -overlayH / 2 + 12):zoom(0.55)
				:diffuse(accentColor):settext(THEME:GetString("Filters", "Title"))
		end,
	},

	-- Instructions (Top Right)
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:halign(1):valign(0):xy(overlayW / 2 - 20, -overlayH / 2 + 15):zoom(0.32):diffuse(dimText)
				:settext(THEME:GetString("Filters", "Instructions"))
		end,
	},
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:halign(1):valign(0):xy(overlayW / 2 - 20, -overlayH / 2 + 30):zoom(0.32):diffuse(dimText)
				:settext(THEME:GetString("Filters", "Hint"))
		end,
	},

	-- Column headers
	Def.ActorFrame {
		InitCommand = function(self)
			self:xy(-overlayW / 2 + labelColX, -overlayH / 2 + rowStartY - 10)
		end,
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:halign(0):zoom(0.35):diffuse(dimText):settext(THEME:GetString("Filters", "SkillsetColumn"))
			end,
		},
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:halign(0.5):x(minColX):zoom(0.35):diffuse(dimText):settext(THEME:GetString("Filters", "MinColumn"))
			end,
		},
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:halign(0.5):x(maxColX):zoom(0.35):diffuse(dimText):settext(THEME:GetString("Filters", "MaxColumn"))
			end,
		},
	},
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(-overlayW / 2 + 12, -overlayH / 2 + rowStartY - 4)
				:zoomto(overlayW - 24, 1):diffuse(color("0.12,0.12,0.12,1"))
		end,
	},
}

-- Helper: create a clickable filter input box for row i
local function CreateFilterInputBox(i)
	local label = ""
	if i <= #ms.SkillSets then
		label = ms.SkillSetsTranslated[i] or ms.SkillSets[i]
	elseif i == #ms.SkillSets + 1 then
		label = THEME:GetString("Filters", "LengthLabel")
	else
		label = THEME:GetString("Filters", "BestPercentLabel")
	end

	local rowY = -overlayH / 2 + rowStartY + (i - 1) * spacingY

	local row = Def.ActorFrame {
		Name = "FilterRow_" .. i,
		InitCommand = function(self)
			self:xy(-overlayW / 2 + labelColX, rowY)
		end,

		-- Row label
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:halign(0):valign(0.5):y(spacingY / 2):zoom(0.38):diffuse(mainText):settext(label)
			end,
		},

		----------- LOWER BOUND (MIN) -----------
		-- Clickable background quad
		UIElements.QuadButton(1, 1) .. {
			Name = "LowerBg",
			InitCommand = function(self)
				self:halign(0.5):valign(0.5):x(minColX):y(spacingY / 2):zoomto(cellW, cellH)
			end,
			SetCommand = function(self)
				if ActiveSS == i and activebound == 0 then
					self:diffuse(color("#666666"))
				else
					self:diffuse(color("#000000"))
				end
			end,
			MouseDownCommand = function(self, params)
				if params.event == "DeviceButton_left mouse button" and active and focus.isCurrent() then
					beginEdit(i, 0)
				end
			end,
			MouseOverCommand = function(self)
				if ActiveSS ~= i or activebound ~= 0 then
					self:diffusealpha(hoverAlpha)
				end
			end,
			MouseOutCommand = function(self)
				self:diffusealpha(1)
			end,
			HV_FilterUpdatedMessageCommand = function(self) self:playcommand("Set") end,
			HV_NumericInputEndedMessageCommand = function(self) self:playcommand("Set") end,
			HV_NumericInputActiveMessageCommand = function(self) self:playcommand("Set") end,
		},

		-- Lower bound value text
		LoadFont("Common Normal") .. {
			Name = "LowerVal",
			InitCommand = function(self)
				self:halign(0.5):valign(0.5):x(minColX):y(spacingY / 2):zoom(0.38):maxwidth(cellW / 0.38 - 4)
			end,
			SetCommand = function(self) setBoundLabel(self, i, 0) end,
			HV_FilterUpdatedMessageCommand = function(self) self:playcommand("Set") end,
			HV_NumericInputActiveMessageCommand = function(self) self:playcommand("Set") end,
			HV_NumericInputEndedMessageCommand = function(self) self:playcommand("Set") end,
		},

		----------- UPPER BOUND (MAX) -----------
		UIElements.QuadButton(1, 1) .. {
			Name = "UpperBg",
			InitCommand = function(self)
				self:halign(0.5):valign(0.5):x(maxColX):y(spacingY / 2):zoomto(cellW, cellH)
			end,
			SetCommand = function(self)
				if ActiveSS == i and activebound == 1 then
					self:diffuse(color("#666666"))
				else
					self:diffuse(color("#000000"))
				end
			end,
			MouseDownCommand = function(self, params)
				if params.event == "DeviceButton_left mouse button" and active and focus.isCurrent() then
					beginEdit(i, 1)
				end
			end,
			MouseOverCommand = function(self)
				if ActiveSS ~= i or activebound ~= 1 then
					self:diffusealpha(hoverAlpha)
				end
			end,
			MouseOutCommand = function(self)
				self:diffusealpha(1)
			end,
			HV_FilterUpdatedMessageCommand = function(self) self:playcommand("Set") end,
			HV_NumericInputEndedMessageCommand = function(self) self:playcommand("Set") end,
			HV_NumericInputActiveMessageCommand = function(self) self:playcommand("Set") end,
		},

		-- Upper bound value text
		LoadFont("Common Normal") .. {
			Name = "UpperVal",
			InitCommand = function(self)
				self:halign(0.5):valign(0.5):x(maxColX):y(spacingY / 2):zoom(0.38):maxwidth(cellW / 0.38 - 4)
			end,
			SetCommand = function(self) setBoundLabel(self, i, 1) end,
			HV_FilterUpdatedMessageCommand = function(self) self:playcommand("Set") end,
			HV_NumericInputActiveMessageCommand = function(self) self:playcommand("Set") end,
			HV_NumericInputEndedMessageCommand = function(self) self:playcommand("Set") end,
		},
	}

	return row
end

-- Add all filter rows
for i = 1, totalRows do
	t[#t + 1] = CreateFilterInputBox(i)
end

-- Controls section (below the rows)
local ctrlSpacing = 22
local controlsY = -overlayH / 2 + rowStartY + totalRows * spacingY + 8

t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:halign(0):valign(0):xy(-overlayW / 2 + 12, controlsY - 4)
			:zoomto(overlayW - 24, 1):diffuse(color("0.12,0.12,0.12,1"))
	end,
}

-- Max Rate (left-click +, right-click -)
t[#t + 1] = UIElements.TextToolTip(1, 1, "Common Normal") .. {
	InitCommand = function(self)
		self:halign(0):valign(0):xy(-overlayW / 2 + labelColX, controlsY + 6):zoom(textzoom)
			:diffuse(accentColor)
	end,
	SetCommand = function(self)
		self:settextf(THEME:GetString("Filters", "MaxRateFormatted"), FILTERMAN:GetMaxFilterRate())
	end,
	HV_FilterUpdatedMessageCommand = function(self) self:playcommand("Set") end,
	HV_ResetFilterMessageCommand = function(self) self:playcommand("Set") end,
	MouseOverCommand = function(self) self:diffusealpha(hoverAlpha) end,
	MouseOutCommand = function(self) self:diffusealpha(1) end,
}
t[#t + 1] = UIElements.QuadButton(1, 1) .. {
	InitCommand = function(self)
		self:halign(0):valign(0):xy(-overlayW / 2 + labelColX, controlsY + 6)
			:zoomto(140, spacingY - 2):diffusealpha(0)
	end,
	MouseDownCommand = function(self, params)
		if params.event == "DeviceButton_left mouse button" and active and focus.isCurrent() then
			FILTERMAN:SetMaxFilterRate(FILTERMAN:GetMaxFilterRate() + 0.1)
			MESSAGEMAN:Broadcast("HV_FilterUpdated")
			refreshWheel(false)
		elseif params.event == "DeviceButton_right mouse button" and active and focus.isCurrent() then
			FILTERMAN:SetMaxFilterRate(FILTERMAN:GetMaxFilterRate() - 0.1)
			MESSAGEMAN:Broadcast("HV_FilterUpdated")
			refreshWheel(false)
		end
	end,
}

-- Min Rate (left-click +, right-click -)
t[#t + 1] = UIElements.TextToolTip(1, 1, "Common Normal") .. {
	InitCommand = function(self)
		self:halign(0):valign(0):xy(-overlayW / 2 + labelColX, controlsY + 6 + ctrlSpacing):zoom(textzoom)
			:diffuse(accentColor)
	end,
	SetCommand = function(self)
		self:settextf(THEME:GetString("Filters", "MinRateFormatted"), FILTERMAN:GetMinFilterRate())
	end,
	HV_FilterUpdatedMessageCommand = function(self) self:playcommand("Set") end,
	HV_ResetFilterMessageCommand = function(self) self:playcommand("Set") end,
	MouseOverCommand = function(self) self:diffusealpha(hoverAlpha) end,
	MouseOutCommand = function(self) self:diffusealpha(1) end,
}
t[#t + 1] = UIElements.QuadButton(1, 1) .. {
	InitCommand = function(self)
		self:halign(0):valign(0):xy(-overlayW / 2 + labelColX, controlsY + 6 + ctrlSpacing)
			:zoomto(140, ctrlSpacing - 2):diffusealpha(0)
	end,
	MouseDownCommand = function(self, params)
		if params.event == "DeviceButton_left mouse button" and active and focus.isCurrent() then
			FILTERMAN:SetMinFilterRate(FILTERMAN:GetMinFilterRate() + 0.1)
			MESSAGEMAN:Broadcast("HV_FilterUpdated")
			refreshWheel(false)
		elseif params.event == "DeviceButton_right mouse button" and active and focus.isCurrent() then
			FILTERMAN:SetMinFilterRate(FILTERMAN:GetMinFilterRate() - 0.1)
			MESSAGEMAN:Broadcast("HV_FilterUpdated")
			refreshWheel(false)
		end
	end,
}

-- Right-side controls (anchored to right half of overlay)
local rightColX = overlayW / 2 - 220

-- Mode toggle (AND / OR)
t[#t + 1] = UIElements.TextToolTip(1, 1, "Common Normal") .. {
	InitCommand = function(self)
		self:halign(0):valign(0):xy(-overlayW / 2 + rightColX, controlsY + 6):zoom(textzoom)
			:diffuse(accentColor)
	end,
	SetCommand = function(self)
		if FILTERMAN:GetFilterMode() then
			self:settext(THEME:GetString("Filters", "ModeAND"))
		else
			self:settext(THEME:GetString("Filters", "ModeOR"))
		end
	end,
	HV_FilterUpdatedMessageCommand = function(self) self:playcommand("Set") end,
	HV_FilterModeChangedMessageCommand = function(self) self:playcommand("Set") end,
	HV_ResetFilterMessageCommand = function(self) self:playcommand("Set") end,
	MouseOverCommand = function(self) self:diffusealpha(hoverAlpha) end,
	MouseOutCommand = function(self) self:diffusealpha(1) end,
}
t[#t + 1] = UIElements.QuadButton(1, 1) .. {
	InitCommand = function(self)
		self:halign(0):valign(0):xy(-overlayW / 2 + rightColX, controlsY + 6)
			:zoomto(120, spacingY - 2):diffusealpha(0)
	end,
	MouseDownCommand = function(self, params)
		if params.event == "DeviceButton_left mouse button" and active and focus.isCurrent() then
			FILTERMAN:ToggleFilterMode()
			MESSAGEMAN:Broadcast("HV_FilterModeChanged")
			MESSAGEMAN:Broadcast("HV_FilterUpdated")
			refreshWheel(false)
		end
	end,
}

-- Highest Skillsets Only toggle (greyed when AND mode)
t[#t + 1] = UIElements.TextToolTip(1, 1, "Common Normal") .. {
	InitCommand = function(self)
		self:halign(0):valign(0):xy(-overlayW / 2 + rightColX, controlsY + 6 + ctrlSpacing):zoom(textzoom)
			:maxwidth((overlayW / 2 - 40) / textzoom)
	end,
	SetCommand = function(self)
		local onoff = FILTERMAN:GetHighestSkillsetsOnly() and THEME:GetString("Filters", "On") or THEME:GetString("Filters", "Off")
		self:settextf(THEME:GetString("Filters", "HighestSSOnly"), onoff)
		if FILTERMAN:GetFilterMode() then
			self:diffuse(color("1,1,1,0.2"))
		else
			self:diffuse(accentColor)
		end
	end,
	HV_FilterModeChangedMessageCommand = function(self) self:playcommand("Set") end,
	HV_FilterUpdatedMessageCommand = function(self) self:playcommand("Set") end,
	HV_ResetFilterMessageCommand = function(self) self:playcommand("Set") end,
	MouseOverCommand = function(self)
		if not FILTERMAN:GetFilterMode() then
			self:diffusealpha(hoverAlpha)
		end
	end,
	MouseOutCommand = function(self)
		if FILTERMAN:GetFilterMode() then
			self:diffusealpha(0.2)
		else
			self:diffusealpha(1)
		end
	end,
}
t[#t + 1] = UIElements.QuadButton(1, 1) .. {
	InitCommand = function(self)
		self:halign(0):valign(0):xy(-overlayW / 2 + rightColX, controlsY + 6 + ctrlSpacing)
			:zoomto(180, ctrlSpacing - 2):diffusealpha(0)
	end,
	MouseDownCommand = function(self, params)
		if params.event == "DeviceButton_left mouse button" and active and focus.isCurrent() and not FILTERMAN:GetFilterMode() then
			FILTERMAN:ToggleHighestSkillsetsOnly()
			MESSAGEMAN:Broadcast("HV_FilterModeChanged")
			MESSAGEMAN:Broadcast("HV_FilterUpdated")
			refreshWheel(false)
		end
	end,
}

-- Highest Difficulty Only toggle (greyed when AND mode)
t[#t + 1] = UIElements.TextToolTip(1, 1, "Common Normal") .. {
	InitCommand = function(self)
		self:halign(0):valign(0):xy(-overlayW / 2 + rightColX, controlsY + 6 + ctrlSpacing * 2):zoom(textzoom)
			:maxwidth((overlayW / 2 - 40) / textzoom)
	end,
	SetCommand = function(self)
		local onoff = FILTERMAN:GetHighestDifficultyOnly() and THEME:GetString("Filters", "On") or THEME:GetString("Filters", "Off")
		self:settextf(THEME:GetString("Filters", "HighestDiffOnly"), onoff)
		if FILTERMAN:GetFilterMode() then
			self:diffuse(color("1,1,1,0.2"))
		else
			self:diffuse(accentColor)
		end
	end,
	HV_FilterModeChangedMessageCommand = function(self) self:playcommand("Set") end,
	HV_FilterUpdatedMessageCommand = function(self) self:playcommand("Set") end,
	HV_ResetFilterMessageCommand = function(self) self:playcommand("Set") end,
	MouseOverCommand = function(self)
		if not FILTERMAN:GetFilterMode() then
			self:diffusealpha(hoverAlpha)
		end
	end,
	MouseOutCommand = function(self)
		if FILTERMAN:GetFilterMode() then
			self:diffusealpha(0.2)
		else
			self:diffusealpha(1)
		end
	end,
}
t[#t + 1] = UIElements.QuadButton(1, 1) .. {
	InitCommand = function(self)
		self:halign(0):valign(0):xy(-overlayW / 2 + rightColX, controlsY + 6 + ctrlSpacing * 2)
			:zoomto(180, ctrlSpacing - 2):diffusealpha(0)
	end,
	MouseDownCommand = function(self, params)
		if params.event == "DeviceButton_left mouse button" and active and focus.isCurrent() and not FILTERMAN:GetFilterMode() then
			FILTERMAN:ToggleHighestDifficultyOnly()
			MESSAGEMAN:Broadcast("HV_FilterModeChanged")
			MESSAGEMAN:Broadcast("HV_FilterUpdated")
			refreshWheel(false)
		end
	end,
}

-- Filter match count
t[#t + 1] = LoadFont("Common Normal") .. {
	Name = "FilterResults",
	InitCommand = function(self)
		self:halign(0):valign(0):xy(-overlayW / 2 + rightColX, controlsY + 6 + ctrlSpacing * 3):zoom(textzoom)
			:diffuse(subText):settext("")
	end,
	FilterResultsMessageCommand = function(self, msg)
		if msg then
			self:settextf(THEME:GetString("Filters", "MatchesFormatted"), msg.Matches or 0, msg.Total or 0)
		end
	end,
}

-- Bottom action bar
local bottomY = overlayH / 2 - 28

-- Reset button
t[#t + 1] = UIElements.TextButton(1, 1, "Common Normal") .. {
	InitCommand = function(self)
		self:xy(overlayW / 2 - 80, bottomY)
		local txt = self:GetChild("Text")
		local bg = self:GetChild("BG")
		txt:zoom(0.38):settext(THEME:GetString("Filters", "ResetAll")):diffuse(color("1,0.4,0.4,1"))
		bg:zoomto(110, 22):diffuse(color("0.15,0,0,0.8"))
	end,
	RolloverUpdateCommand = function(self, params)
		if params.update == "in" then
			self:diffusealpha(hoverAlpha)
		else
			self:diffusealpha(1)
		end
	end,
	ClickCommand = function(self, params)
		if params.update ~= "OnMouseDown" then return end
		if params.event == "DeviceButton_left mouse button" and active and focus.isCurrent() then
			FILTERMAN:ResetAllFilters()
			activebound = 0
			ActiveSS = 0
			MESSAGEMAN:Broadcast("HV_FilterUpdated")
			MESSAGEMAN:Broadcast("HV_ResetFilter")
			MESSAGEMAN:Broadcast("HV_NumericInputEnded")
			MESSAGEMAN:Broadcast("HV_FilterModeChanged")
			refreshWheel(false)
		end
	end,
}

local function handleInput(event)
	if not active then return false end
	local button = event.DeviceInput.button
	if event.DeviceInput.is_mouse or (button and button:find("mouse", 1, true)) then
		if event.type == "InputEventType_FirstPress" and button == "DeviceButton_left mouse button"
			and not IsMouseOverCentered(SCREEN_CENTER_X, SCREEN_CENTER_Y, overlayW, overlayH) then
			focus.hold(event)
			MESSAGEMAN:Broadcast("SelectMusicTabChanged", {Tab = ""})
			return true
		end
		return false
	end
	if ActiveSS > 0 then
		FilterInput(event)
		return true
	end
	return false
end

return t, handleInput
