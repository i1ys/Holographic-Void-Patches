--- Holographic Void: Goals Tab

local accentColor = HVColor.Accent
local dimText = color("0.45,0.45,0.45,1")
local subText = color("0.65,0.65,0.65,1")
local mainText = color("0.85,0.85,0.85,1")
local brightText = color("1,1,1,1")
local bgCard = color("0.04,0.04,0.04,0.97")

local overlayW = 680
local overlayH = 400
local rowH = 34
local numGoals = 8
local ind = 0 -- scroll offset
local goalsActor = nil
local whee = nil
local goaltable = {}

local function getProfile()
	return PROFILEMAN:GetProfile(PLAYER_1)
end

local function refreshGoals()
	local profile = getProfile()
	profile:SetFromAll()
	goaltable = profile:GetGoalTable()
	ind = math.max(0, math.min(ind, #goaltable - numGoals))
end

local function refreshGoalView()
	refreshGoals()
	goalsActor:playcommand("GoalTableRefresh")
end

local function goalMessage(key)
	ms.ok(THEME:GetString("Goals", key))
end

local function saveGoals()
	if not PROFILEMAN:SaveProfile(PLAYER_1) then goalMessage("SaveFailed") end
end

local function addCurrentGoal()
	local steps = GAMESTATE:GetCurrentSteps()
	if not steps then return end
	-- AddGoal returns a boolean and supplies 93%, current rate and priority 1.
	if getProfile():AddGoal(steps:GetChartKey()) then
		saveGoals()
	else
		goalMessage("DuplicateGoal")
	end
end

local function editGoal(goal, title, maxLength, initialText, apply)
	if goal:IsAchieved() then
		goalMessage("AchievedReadOnly")
		return
	end
	local profile = getProfile()
	local key, assigned = goal:GetChartKey(), goal:WhenAssigned()
	local rate, percent = goal:GetRate(), goal:GetPercent()

	easyInputStringOKCancel(THEME:GetString("Goals", title), maxLength, false, function(answer)
		if profile ~= getProfile() then return end
		-- ScoreGoal objects are backed by a vector that can change during the prompt.
		profile:SetFromAll()
		local selected
		for _, current in ipairs(profile:GetGoalTable()) do
			if current:GetChartKey() == key and current:WhenAssigned() == assigned
				and current:GetRate() == rate and current:GetPercent() == percent then
				if selected then
					goalMessage("GoalChanged")
					refreshGoalView()
					return
				end
				selected = current
			end
		end
		if not selected or selected:IsAchieved() then
			goalMessage("GoalChanged")
		elseif apply(selected, answer) then
			saveGoals()
		end
		refreshGoalView()
	end, nil, initialText)
end

local function setGoalRate(goal, answer)
	local rate = tonumber(answer)
	if not HV.Config.IsFinite(rate) or rate < 0.05 or rate > 3.0 then
		goalMessage("RateOutOfRange")
		return
	end
	if math.abs(rate * 20 - math.floor(rate * 20 + 0.5)) > 0.0001 then
		goalMessage("RateIncrement")
		return
	end
	if math.abs(goal:GetRate() - rate) < 0.00001 then return end
	for _, other in ipairs(getProfile():GetGoalTable()) do
		if other:GetChartKey() == goal:GetChartKey() and other:GetPercent() == goal:GetPercent()
			and math.abs(other:GetRate() - rate) < 0.00001 then
			goalMessage("DuplicateGoal")
			return
		end
	end
	local previous = goal:GetRate()
	goal:SetRate(rate)
	return goal:GetRate() ~= previous
end

local function setGoalPercent(goal, answer)
	local percent = answer and tonumber((answer:gsub("%%%s*$", "")))
	if not HV.Config.IsFinite(percent) or percent < 80 or percent > 100 then
		goalMessage("TargetOutOfRange")
		return
	end
	local previous = goal:GetPercent()
	if math.abs(percent / 100 - previous) < 0.00000005 then return end
	goal:SetPercent(percent / 100)
	return goal:GetPercent() ~= previous
end

local function deleteGoal(goal)
	-- The engine deletes by chart key and assignment second.
	local key, assigned = goal:GetChartKey(), goal:WhenAssigned()
	local matches = 0
	for _, current in ipairs(goaltable) do
		if current:GetChartKey() == key and current:WhenAssigned() == assigned then
			matches = matches + 1
		end
	end
	if matches ~= 1 or not SONGMAN:GetStepsByChartKey(key) then
		goalMessage("DeleteAmbiguous")
		return
	end
	goal:Delete()
	saveGoals()
	refreshGoalView()
	if whee then whee:RebuildWheelItems() end
end

local function formatGoalPercent(pct)
	local p = notShit.round(pct * 100, 5)
	if p < 99 then
		return string.format("%.2f%%", p)
	elseif p < 99.7 then
		return string.format("%.2f%%", p)
	elseif p < 99.955 then
		return string.format("%.3f%%", p)
	elseif p < 99.9935 then
		return string.format("%.4f%%", p)
	else
		return string.format("%.5f%%", p)
	end
end

local t = Def.ActorFrame {
	Name = "GoalsOverlay",
	InitCommand = function(self)
		goalsActor = self
		self:xy(SCREEN_CENTER_X, SCREEN_CENTER_Y):visible(false)
	end,
	BeginCommand = function(self)
		local screen = SCREENMAN:GetTopScreen()
		if screen and screen.GetMusicWheel then whee = screen:GetMusicWheel() end
	end,
	SelectMusicTabChangedMessageCommand = function(self, params)
		if params.Tab == "GOALS" then
			self:visible(not self:GetVisible())
			if self:GetVisible() then
				self:stoptweening():diffusealpha(0):linear(0.2):diffusealpha(1)
				HV.ActiveTab = "GOALS"
				ind = 0
				refreshGoals()
			else
				HV.ActiveTab = ""
			end
		else
			self:visible(false)
			if HV.ActiveTab == "GOALS" then HV.ActiveTab = "" end
		end
		self:playcommand("GoalTableRefresh")
	end,
	GoalTableRefreshMessageCommand = function(self)
		if self:GetVisible() then refreshGoalView() end
	end,
	NextGoalPageMessageCommand = function(self)
		ind = math.max(0, math.min(#goaltable - numGoals, ind + 1 * numGoals))
		self:playcommand("GoalTableRefresh")
	end,
	PrevGoalPageMessageCommand = function(self)
		ind = math.max(0, math.min(#goaltable - numGoals, ind - 1 * numGoals))
		self:playcommand("GoalTableRefresh")
	end,

	-- Glassmorphism Background
	Def.Quad { 
		InitCommand = function(self) 
			self:zoomto(overlayW, overlayH):diffuse(bgCard)
				:diffusealpha(0.98)
		end 
	},
	-- Subtle Glow Border
	Def.Quad { 
		InitCommand = function(self) 
			self:valign(0):y(-overlayH/2):zoomto(overlayW, 1):diffuse(accentColor):diffusealpha(0.4) 
		end 
	},
	Def.Quad { 
		InitCommand = function(self) 
			self:valign(1):y(overlayH/2):zoomto(overlayW, 1):diffuse(accentColor):diffusealpha(0.2) 
		end 
	},

	-- Title
	LoadFont("Common Normal") .. {
		Name = "Title",
		InitCommand = function(self)
			self:halign(0):valign(0):xy(-overlayW/2 + 24, -overlayH/2 + 18):zoom(0.55):diffuse(accentColor)
		end,
		GoalTableRefreshCommand = function(self)
			self:settextf(THEME:GetString("Goals", "Title"), #goaltable)
		end,
	},

	-- Add Goal button
	Def.ActorFrame {
		Name = "AddGoalBtn",
		InitCommand = function(self) self:xy(overlayW/2 - 85, -overlayH/2 + 28) end,
		Def.Quad { 
			InitCommand = function(self) 
				self:zoomto(110, 28):diffuse(accentColor):diffusealpha(0.12)
					:blend(Blend.Add)
			end 
		},
		Def.Quad { 
			InitCommand = function(self) 
				self:zoomto(110, 1):valign(1):y(14):diffuse(accentColor):diffusealpha(0.5)
			end 
		},
		LoadFont("Common Normal") .. { 
			InitCommand = function(self) 
				self:zoom(0.32):diffuse(brightText):settext(THEME:GetString("Goals", "AddGoal")) 
			end 
		},
	},

	-- Page indicator
	LoadFont("Common Normal") .. {
		Name = "PageInfo",
		InitCommand = function(self)
			self:halign(1):valign(0):xy(overlayW/2 - 16, -overlayH/2 + 38):zoom(0.22):diffuse(dimText)
		end,
		GoalTableRefreshCommand = function(self)
			if #goaltable > 0 then
				self:settextf("%d-%d / %d", ind + 1, math.min(ind + numGoals, #goaltable), #goaltable)
			else
				self:settext(THEME:GetString("Goals", "NoGoals"))
			end
		end,
	},

	-- Column Headers
	Def.ActorFrame {
		InitCommand = function(self) self:xy(-overlayW/2 + 24, -overlayH/2 + 52) end,

		LoadFont("Common Normal") .. { InitCommand = function(self) self:halign(0.5):x(45):zoom(0.35):diffuse(accentColor):settext(THEME:GetString("Goals", "PriorityColumn")) end },
		LoadFont("Zpix Normal") .. { InitCommand = function(self) self:halign(0):x(85):zoom(0.4):diffuse(accentColor):settext(THEME:GetString("Goals", "SongColumn")) end },
		LoadFont("Common Normal") .. { InitCommand = function(self) self:halign(0.5):x(385):zoom(0.35):diffuse(accentColor):settext(THEME:GetString("Goals", "RateColumn")) end },
		LoadFont("Common Normal") .. { InitCommand = function(self) self:halign(0.5):x(465):zoom(0.35):diffuse(accentColor):settext(THEME:GetString("Goals", "TargetColumn")) end },
		LoadFont("Common Normal") .. { InitCommand = function(self) self:halign(0.5):x(545):zoom(0.35):diffuse(accentColor):settext(THEME:GetString("Goals", "PBColumn") or "PB") end },
		LoadFont("Common Normal") .. { InitCommand = function(self) self:halign(0.5):x(605):zoom(0.35):diffuse(accentColor):settext(THEME:GetString("Goals", "StatusColumn")) end },
	},
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(-overlayW/2 + 20, -overlayH/2 + 65)
				:zoomto(overlayW - 40, 1):diffuse(color("0.15,0.15,0.15,1"))
		end,
	},
}

-- Row drawing
local rowStartY = -overlayH/2 + 65

local function makeGoalRow(i)
	local sg, ck, goalsong, goalsteps

	local row = Def.ActorFrame {
		Name = "GoalRow_" .. i,
		InitCommand = function(self)
			self:xy(-overlayW/2 + 24, rowStartY + (i - 1) * rowH)
		end,
		GoalTableRefreshCommand = function(self)
			sg = goaltable[i + ind]
			if sg then
				ck = sg:GetChartKey()
				goalsong = SONGMAN:GetSongByChartKey(ck)
				goalsteps = SONGMAN:GetStepsByChartKey(ck)
				self:visible(true)
			else
				self:visible(false)
			end
		end,

		-- Row Highlight Quad
		Def.Quad {
			InitCommand = function(self)
				self:halign(0):valign(0):zoomto(overlayW - 48, rowH - 4)
					:diffuse(color("1,1,1,0.03"))
			end,
			GoalTableRefreshCommand = function(self)
				if sg then
					if sg:IsAchieved() then
						self:diffuse(color("0.1,0.5,0.1,0.15"))
					elseif sg:IsVacuous() then
						self:diffuse(color("0.4,0.4,0.1,0.15"))
					else
						self:diffuse(color("1,1,1,0.03"))
					end
				end
			end,
		},

		-- Delete button (Hoverable style)
		LoadActor(THEME:GetPathG("", "delete")) .. {
			Name = "DeleteBtn",
			InitCommand = function(self)
				self:halign(0.5):valign(0.5):x(15):y(rowH/2 - 2):zoom(0.25):diffuse(color("0.8,0.2,0.2,0.6"))
			end,
		},

		-- Priority
		LoadFont("Common Normal") .. {
			Name = "Priority",
			InitCommand = function(self) self:halign(0.5):valign(0.5):x(45):y(rowH/2 - 2):zoom(0.42):diffuse(mainText) end,
			GoalTableRefreshCommand = function(self)
				if sg then self:settextf("%d", sg:GetPriority()) else self:settext("") end
			end,
		},

		-- Song & Difficulty
		Def.ActorFrame {
			Name = "SongDetails",
			InitCommand = function(self) self:xy(85, rowH/2 - 2) end,
			
			LoadFont("Zpix Normal") .. {
				Name = "SongName",
				InitCommand = function(self)
					self:halign(0):zoom(0.5):diffuse(brightText):maxwidth(280 / 0.5)
				end,
				GoalTableRefreshCommand = function(self)
					if sg then
						if goalsong then self:settext(goalsong:GetDisplayMainTitle())
						else self:settext(THEME:GetString("Goals", "SongMissing")):diffuse(color("1,0.3,0.3,1")) end
					end
				end,
			},
			LoadFont("Common Normal") .. {
				Name = "Diff",
				InitCommand = function(self) self:halign(0):y(12):zoom(0.28) end,
				GoalTableRefreshCommand = function(self)
					if sg and goalsteps then
						local d = ToEnumShortString(goalsteps:GetDifficulty())
						local msd = goalsteps:GetMSD(sg:GetRate(), 1)
						self:settext(string.format("%s %.1f", d, msd)):diffuse(HVColor.Difficulty[d] or subText)
					end
				end,
			},
		},

		-- Rate
		LoadFont("Common Normal") .. {
			Name = "Rate",
			InitCommand = function(self) self:halign(0.5):valign(0.5):x(385):y(rowH/2 - 2):zoom(0.42):diffuse(subText) end,
			GoalTableRefreshCommand = function(self)
				if sg then self:settextf("%.2fx", sg:GetRate()) end
			end,
		},

		-- Target % (Granular)
		LoadFont("Common Normal") .. {
			Name = "Target",
			InitCommand = function(self) self:halign(0.5):valign(0.5):x(465):y(rowH/2 - 2):zoom(0.4):diffuse(brightText) end,
			GoalTableRefreshCommand = function(self)
				if sg then self:settext(formatGoalPercent(sg:GetPercent())) end
			end,
		},

		-- PB
		LoadFont("Common Normal") .. {
			Name = "PB",
			InitCommand = function(self) self:halign(0.5):valign(0.5):x(545):y(rowH/2 - 2):zoom(0.38) end,
			GoalTableRefreshCommand = function(self)
				if sg then
					local pb = sg:GetPBUpTo()
					if pb then
						local pbc = pb:GetWifeScore() * 100
						self:settextf("%.2f%%", pbc):diffuse(sg:IsAchieved() and color("0.4,1,0.4,1") or subText)
					else
						self:settext("-"):diffuse(dimText)
					end
				end
			end,
		},

		-- Status Label (Moved left slightly)
		LoadFont("Common Normal") .. {
			Name = "Status",
			InitCommand = function(self) self:halign(0.5):valign(0.5):x(605):y(rowH/2 - 2):zoom(0.35) end,
			GoalTableRefreshCommand = function(self)
				if sg then
					if sg:IsVacuous() then self:settext(THEME:GetString("Goals", "Vacuous")):diffuse(color("0.9,0.9,0.3,1"))
					elseif sg:IsAchieved() then self:settext(THEME:GetString("Goals", "Achieved")):diffuse(color("0.4,1,0.4,1"))
					else self:settext(THEME:GetString("Goals", "Pending")):diffuse(color("1,0.6,0.2,1")) end
				end
			end,
		},
	}

	return row
end

for i = 1, numGoals do
	t[#t + 1] = makeGoalRow(i)
end

-- Input handler
t[#t + 1] = Def.ActorFrame {
	BeginCommand = function(self)
		local screen = SCREENMAN:GetTopScreen()
		if not screen then return end
		screen:AddInputCallback(function(event)
			if not goalsActor or not goalsActor:GetVisible() then return false end
			if not event or not event.DeviceInput then return true end
			
			local btn = event.DeviceInput.button or ""
			local evType = event.type
			local isRight = btn == "DeviceButton_right mouse button"
			local mx, my = INPUTFILTER:GetMouseX(), INPUTFILTER:GetMouseY()
			
			if evType ~= "InputEventType_FirstPress" then return true end

			-- Add Goal Button (Top Right)
			if btn == "DeviceButton_left mouse button" and evType == "InputEventType_FirstPress" then
				local btnCX = SCREEN_CENTER_X + (overlayW / 2) - 85
				local btnCY = SCREEN_CENTER_Y - (overlayH / 2) + 28
				if mx >= btnCX - 55 and mx <= btnCX + 55 and my >= btnCY - 14 and my <= btnCY + 14 then
					addCurrentGoal()
					return true
				end
			end

			-- Scroll (Now routed via global TabNavigation in default.lua)

			-- Row Clicks
			if btn == "DeviceButton_left mouse button" or btn == "DeviceButton_right mouse button" then
				if mx < SCREEN_CENTER_X - overlayW/2 or mx > SCREEN_CENTER_X + overlayW/2 or my < SCREEN_CENTER_Y - overlayH/2 or my > SCREEN_CENTER_Y + overlayH/2 then
					MESSAGEMAN:Broadcast("SelectMusicTabChanged", {Tab = ""})
					return true
				end

				for ri = 1, numGoals do
					local rowTop = SCREEN_CENTER_Y + rowStartY + (ri - 1) * rowH
					local rowLeft = SCREEN_CENTER_X - overlayW/2 + 24
					if my >= rowTop and my <= rowTop + rowH then
						local gIdx = ri + ind
						if gIdx <= #goaltable then
							local sg = goaltable[gIdx]
							local hx = mx - rowLeft

							if hx >= 0 and hx <= 35 then
								if not isRight then deleteGoal(sg) end
								return true
							end

							if hx > 35 and hx <= 75 then
								if not sg:IsAchieved() then
									local priority = sg:GetPriority()
									sg:SetPriority(priority + (isRight and -1 or 1))
									if sg:GetPriority() ~= priority then saveGoals() end
									goalsActor:playcommand("GoalTableRefresh")
								end
								return true
							end

							if hx >= 360 and hx < 410 then
								editGoal(sg, "RateLabel", 6, string.format("%.2f", sg:GetRate()), setGoalRate)
								return true
							end

							if hx >= 410 and hx <= 510 then
								editGoal(sg, "TargetLabel", 12, formatGoalPercent(sg:GetPercent()), setGoalPercent)
								return true
							end

							-- Song click find
							if hx >= 75 and hx <= 360 and not isRight then
								local ck = sg:GetChartKey()
								if ck then
									local song = SONGMAN:GetSongByChartKey(ck)
									if song and whee then whee:SelectSong(song) end
								end
								MESSAGEMAN:Broadcast("SelectMusicTabChanged", {Tab = ""})
								return true
							end
						end
						return true
					end
				end
				return true
			end

			if event.button == "Back" or event.DeviceInput.button == "DeviceButton_escape" then
				MESSAGEMAN:Broadcast("SelectMusicTabChanged", {Tab = ""})
				return true
			end
			return false
		end)
	end,
}

return t
