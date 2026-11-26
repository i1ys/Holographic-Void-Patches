local ThemePrefs = HV.LegacyPrefs

--- Holographic Void: ScreenSelectMusic Decorations

-- ============================================================
-- LAYOUT CONSTANTS
-- ============================================================
local panelX = 8                      -- Left panel left edge
local panelW = SCREEN_WIDTH * 0.36   -- Panel width
local panelY = 48                     -- Top margin (pushed down for header)
local accentColor = HVColor.Accent
local dimText = color("0.45,0.45,0.45,1")
local subText = color("0.65,0.65,0.65,1")
local mainText = color("0.85,0.85,0.85,1")
local brightText = color("1,1,1,1")
local bgCard = color("0.06,0.06,0.06,0.9")
local headerH = 40
local footerH = 40

local profileOverlayActor = nil
local IsMouseInSelectMusicInteractiveArea

local function styleModeSupportsSingleDoubleToggle()
	local game = GAMESTATE:GetCurrentGame()
	local gameName = game and game.GetName and game:GetName() or ""
	gameName = tostring(gameName):lower()
	return gameName == "dance" or gameName == "beat"
end

local root = Def.ActorFrame {
	Name = "SelectMusicDecorations"
}

local t = Def.ActorFrame {
	Name = "SelectMusicContent",
	InitCommand = function(self)
		self.hv_holdLerp = 0
		self.hv_holdTarget = 0
	end,
	OnCommand = function(self)
		self:SetUpdateFunction(function(actor)
			actor.hv_holdLerp = actor.hv_holdLerp + (actor.hv_holdTarget - actor.hv_holdLerp) * 0.16
			local p = actor.hv_holdLerp
			actor:x(-SCREEN_WIDTH * 0.28 * p)
			actor:zoom(1 + 0.18 * p)
			actor:diffusealpha(1 - p)
		end)
	end,
	HVLeftMousePeekHoldChangedMessageCommand = function(self, params)
		local held = params and params.Held and params.Allowed
		self.hv_holdTarget = held and 1 or 0
	end
}
root[#root + 1] = t


HV.LoginState = HV.LoginState or {
	visible = false,
	focused = "email",
	email = "",
	password = "",
	status = "Tab / Enter to switch fields"
}
local loginState = HV.LoginState

local selection = {
	song = nil,
	steps = nil,
	group = nil,
	packSummary = nil,
	rate = 1.0,
	displayCharts = {},    -- List of {steps=steps, difficulty=string, isPlaceholder=bool}
	hasSingle = false,
	hasDouble = false,
	chartOffset = 0,       -- For scrolling
	skillsetMSDs = {},     -- {1=Overall, 2=Stream, ...}
	pbScore = nil,
	pbSSR = 0,
}

local maxVisibleCharts = 6
local standardDifficulties = {"Beginner", "Easy", "Medium", "Hard", "Challenge", "Edit"}

local loginBtnW = 180
local loginBtnH = 28
local loginBtnCX = panelX + panelW / 2
local loginBtnCY = SCREEN_BOTTOM - 24

function IsMouseInSelectMusicInteractiveArea()
	local mx = INPUTFILTER:GetMouseX() or SCREEN_CENTER_X
	local my = INPUTFILTER:GetMouseY() or SCREEN_CENTER_Y
	if HV.ActiveTab and HV.ActiveTab ~= "" then return true end
	if mx <= panelX + panelW + 95 then return true end
	if my >= SCREEN_HEIGHT - footerH then return true end
	if my <= headerH then return true end
	return false
end

local function GetOnlineStatus()
	local connected = DLMAN:IsLoggedIn()
	if connected then
		return true, "EtternaOnline", "Online"
	end
	return false, "", "Offline"
end

local function GetPlayableChartSeconds(song, steps)
	if steps then
		local ok, len = pcall(function() return steps:GetLengthSeconds() end)
		if ok and len and len > 0 then return len end
	end
	if song then
		local ok, len = pcall(function() return song:GetStepsSeconds() end)
		if ok and len and len > 0 then return len end
		ok, len = pcall(function() return song:MusicLengthSeconds() end)
		if ok and len and len > 0 then return len end
	end
	return 0
end

-- The CDTitle can receive a hover event before GAMESTATE has finished
-- updating its player-specific steps. Prefer the selection cache, then use
-- the engine's simfile author lookup before falling back to the chart/song
-- credits.
local function GetCDTitleAuthor(song)
	local function usable(value)
		return type(value) == "string" and value ~= "" and value:lower() ~= "none defined"
	end
	local data = selection
	local steps = data and data.steps
	if not steps then
		local ok, currentSteps = pcall(function() return GAMESTATE:GetCurrentSteps() end)
		if ok then steps = currentSteps end
	end

	if steps then
		local ok, author = pcall(function() return steps:GetAuthorCredit() end)
		if ok and usable(author) then
			return author
		end
		local okCredit, credit = pcall(function() return steps:GetCredit() end)
		if okCredit and usable(credit) then
			return credit
		end
	end

	if song then
		local ok, author = pcall(function() return song:GetOrTryAtLeastToGetSimfileAuthor() end)
		if ok and usable(author) then
			return author
		end
		local okCredit, credit = pcall(function() return song:GetCredit() end)
		if okCredit and usable(credit) then
			return credit
		end
	end

	return "None defined"
end



-- ============================================================
-- LEFT PANEL BACKGROUND
-- ============================================================
t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:halign(0):valign(0)
			:xy(panelX, panelY)
			:zoomto(panelW, SCREEN_HEIGHT - headerH - footerH - 16)
			:diffuse(bgCard)
	end
}

-- Panel left border accent
t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:halign(0):valign(0)
			:xy(panelX, panelY)
			:zoomto(2, SCREEN_HEIGHT - headerH - footerH - 16)
			:diffuse(accentColor):diffusealpha(0.3)
	end
}


-- ============================================================
-- SELECTION MANAGER (Centralized Logic)
-- ============================================================
local function getNativeWheel()
	local screen = SCREENMAN:GetTopScreen()
	return screen and screen.GetMusicWheel and screen:GetMusicWheel()
end

local chartListSong, chartListType, chartListTagMatch

local function getPackSummary(wheel, cachedOnly)
	local group = selection.group
	if not wheel or not group or group == "" then return end
	local style = GAMESTATE:GetCurrentStyle()
	return HV.WheelData.GetSection(wheel, group, style and style:GetStepsType(), cachedOnly)
end

-- Etterna suspends wheel positioning while any descendant has a queued tween.
t[#t + 1] = Def.ActorFrame {
	Name = "WheelRowUpdates",
	BeginCommand = function(self)
		local screen = SCREENMAN:GetTopScreen()
		local wheel = screen and screen.GetMusicWheel and screen:GetMusicWheel()
		if wheel then
			self:SetUpdateFunction(function()
				if SCREENMAN:GetTopScreen() ~= screen then return end
				local updated = HV.WheelData.RefreshNextRow(wheel)
				local data = selection
				if data.group and data.group ~= "" and data.renderedGroup == data.group and not data.packSummary then
					data.packSummary = getPackSummary(wheel, updated or not wheel:IsSettled())
					if data.packSummary then MESSAGEMAN:Broadcast("PackDetailsUpdate") end
				end
			end)
		end
	end,
	OffCommand = function(self)
		self:SetUpdateFunction(nil)
		HV.WheelData.ClearPendingRows()
	end,
}

t[#t + 1] = Def.Actor {
	Name = "SelectionManager",
	BeginCommand = function(self)
		self:queuecommand("RefreshSelection")
	end,
	UpdateDataCommand = function()
		local data = selection
		local song = GAMESTATE:GetCurrentSong()
		if data.song ~= song then data.chartOffset = 0 end
		data.song = song
		data.steps = song and GAMESTATE:GetCurrentSteps() or nil
		data.rate = getCurRateValue() or 1
		local wheel = getNativeWheel()
		local group
		if not song and wheel and wheel:GetSelectedType() == "WheelItemDataType_Section" then
			group = wheel:GetSelectedSection()
		end
		if data.group ~= group then data.packSummary = nil end
		data.group = group
		data.renderedSong = nil
		data.detailsReady = false
		data.pbScore, data.pbSSR, data.skillsetMSDs = nil, 0, {}

		data.length, data.nps = nil, nil
	end,

	UpdateChartListCommand = function()
		local data = selection
		local style = GAMESTATE:GetCurrentStyle()
		local stepsType = style and style:GetStepsType()
		data.renderedSong, data.renderedRate = data.song, data.rate
		local matchesTag = HV.GetCombinedTagChartMatch and HV.GetCombinedTagChartMatch()
		if chartListSong == data.song and chartListType == stepsType and chartListTagMatch == matchesTag
			and #data.displayCharts > 0 then return end
		chartListSong, chartListType, chartListTagMatch = data.song, stepsType, matchesTag
		data.hasSingle = data.song ~= nil and data.song:HasStepsType("StepsType_Dance_Single")
		data.hasDouble = data.song ~= nil and data.song:HasStepsType("StepsType_Dance_Double")

		local grouped = {}
		if data.song then
			for _, chart in ipairs(data.song:GetChartsMatchingFilter()) do
				if chart:GetStepsType() == stepsType and (not matchesTag or matchesTag(chart)) then
					local difficulty = ToEnumShortString(chart:GetDifficulty())
					grouped[difficulty] = grouped[difficulty] or {}
					local author = chart:GetAuthorCredit()
					if author == "" then author = chart:GetDescription() end
					if #author > 15 then author = author:sub(1, 13) .. ".." end
					local rows = grouped[difficulty]
					rows[#rows + 1] = {steps = chart, difficulty = difficulty, author = author}
				end
			end
		end

		local charts = {}
		for _, difficulty in ipairs(standardDifficulties) do
			local rows = grouped[difficulty]
			if rows then
				for _, row in ipairs(rows) do charts[#charts + 1] = row end
			else
				charts[#charts + 1] = {difficulty = difficulty, isPlaceholder = true}
			end
		end
		data.displayCharts = charts
		data.chartOffset = math.min(data.chartOffset, math.max(0, #charts - maxVisibleCharts))
	end,

	UpdateHeavyDataCommand = function()
		local data = selection
		if data.steps then
			for i = 1, 8 do data.skillsetMSDs[i] = data.steps:GetMSD(data.rate, i) end
			data.pbScore = GetDisplayScore()
			data.pbSSR = data.pbScore and data.pbScore:GetSkillsetSSR("Overall") or 0
		end
		data.detailsReady = true
	end,

	FilterResultsMessageCommand = function(self)
		HV.WheelData.FilterResultsChanged()
		chartListSong, chartListType = nil, nil
		selection.packSummary, selection.renderedGroup = nil, nil
		self:stoptweening():sleep(0.05):queuecommand("RefreshSelection")
	end,
	RefreshSelectionCommand = function(self)
		self:playcommand("UpdateData")
		self:playcommand("TriggerInstantUpdate")
		self:playcommand("TriggerDelayedUpdate")
	end,
	HV_WheelScoresChangedMessageCommand = function(self)
		selection.packSummary, selection.renderedGroup = nil, nil
		self:playcommand("RefreshSelection")
	end,
	ReloadedCurrentSongMessageCommand = function(self) self:playcommand("ResetWheelData") end,
	ReloadedCurrentPackMessageCommand = function(self) self:playcommand("ResetWheelData") end,
	DFRFinishedMessageCommand = function(self) self:playcommand("ResetWheelData") end,
	ResetWheelDataCommand = function(self)
		HV.WheelData.Reset()
		chartListSong, chartListType = nil, nil
		selection.packSummary, selection.renderedGroup = nil, nil
		selection.renderedSong = nil
		self:stoptweening():sleep(0.05):queuecommand("RefreshReloadedWheel")
	end,
	RefreshReloadedWheelCommand = function(self)
		local screen = SCREENMAN:GetTopScreen()
		local wheel = screen and screen.GetMusicWheel and screen:GetMusicWheel()
		if wheel then wheel:RebuildWheelItems() end
		self:playcommand("RefreshSelection")
	end,

	CurrentSongChangedMessageCommand = function(self)
		self:playcommand("UpdateData")
		-- Throttle InstantChartUpdate to avoid CPU spikes during fast scrolling
		-- 0.04s is roughly 1-2 frames at high refresh rates, enough to skip redundant zips
		self:stoptweening():sleep(0.04):queuecommand("TriggerInstantUpdate")
		
		-- Deferred update for heavy elements
		self:sleep(0.25):queuecommand("TriggerDelayedUpdate")
	end,
	CurrentStepsChangedMessageCommand = function(self)
		self:playcommand("UpdateData")
		self:stoptweening():sleep(0.04):queuecommand("TriggerInstantUpdate")
		self:sleep(0.15):queuecommand("TriggerDelayedUpdate")
	end,
	CurrentRateChangedMessageCommand = function(self)
		self:playcommand("UpdateData")
		self:stoptweening():sleep(0.04):queuecommand("TriggerInstantUpdate")
		self:sleep(0.15):queuecommand("TriggerDelayedUpdate")
	end,
	TriggerInstantUpdateCommand = function(self)
		self:playcommand("UpdateChartList")
		selection.renderedGroup = selection.group
		selection.packSummary = getPackSummary(getNativeWheel(), true)
		local steps = selection.steps
		if steps then
			selection.length = steps:GetLengthSeconds()
			local notes = steps:GetRadarValues(PLAYER_1):GetValue("RadarCategory_Notes")
			if notes >= 0 then selection.nps = notes / math.max(1, selection.length) end
		end
		MESSAGEMAN:Broadcast("InstantChartUpdate")
		MESSAGEMAN:Broadcast("ChartListUpdate")
	end,
	TriggerDelayedUpdateCommand = function(self)
		local wheel = getNativeWheel()
		if wheel and not wheel:IsSettled() then
			self:sleep(0.05):queuecommand("TriggerDelayedUpdate")
			return
		end
		self:playcommand("UpdateHeavyData")
		MESSAGEMAN:Broadcast("HV_SelectionDetailsReady")
	end,
	
	-- Permamirror Sync Logic
	SyncPermamirrorCommand = function(self)
		local st = GAMESTATE:GetCurrentSteps()
		local isPM = false
		if st and st.IsPermaMirror then
			isPM = st:IsPermaMirror()
		else
			local prof = (GetPlayerOrMachineProfile and GetPlayerOrMachineProfile(PLAYER_1)) or PROFILEMAN:GetProfile(PLAYER_1)
			isPM = prof and prof:IsCurrentChartPermamirror() or false
		end
		
		local po = GAMESTATE:GetPlayerState(PLAYER_1):GetPlayerOptions("ModsLevel_Preferred")

		if isPM then
			-- If Permamirror is ON, the engine mirrors the chart data.
			-- We MUST set the Mirror mod to false to avoid a "double-flip" that cancels it out.
			po:Mirror(false)
		end
	end,
	
	ReportPermamirrorCommand = function(self)
		local st = GAMESTATE:GetCurrentSteps()
		local isPM = false
		if st and st.IsPermaMirror then
			isPM = st:IsPermaMirror()
		else
			local prof = (GetPlayerOrMachineProfile and GetPlayerOrMachineProfile(PLAYER_1)) or PROFILEMAN:GetProfile(PLAYER_1)
			isPM = prof and prof:IsCurrentChartPermamirror() or false
		end
		ms.ok("Permamirror: " .. (isPM and "ON" or "OFF"))
	end,
	
	PermamirrorChangedMessageCommand = function(self) 
		self:stoptweening():sleep(0.05):queuecommand("SyncPermamirror"):queuecommand("ReportPermamirror")
	end,
	HV_SelectionDetailsReadyMessageCommand = function(self) self:playcommand("SyncPermamirror") end
}

local function GetCurrentBannerPath()
	local song = selection.song
	local group = selection.group
	local bnpath = ""
	if song then
		bnpath = song:GetBannerPath()
	elseif group then
		bnpath = SONGMAN:GetSongGroupBannerPath(group)
	end

	if not bnpath or bnpath == "" then
		bnpath = THEME:GetPathG("Common", "fallback banner")
	end

	return bnpath
end

local function GetCurrentSongBackgroundPath()
	local song = (selection and selection.song) or GAMESTATE:GetCurrentSong()
	if song and song.GetBackgroundPath then
		local bgPath = song:GetBackgroundPath()
		if bgPath and bgPath ~= "" then
			return bgPath
		end
	end
	return nil
end

-- ============================================================
-- BANNER AREA
-- ============================================================
t[#t + 1] = Def.ActorFrame {
	Name = "BannerFrame",
	InitCommand = function(self)
		self:xy(panelX + panelW / 2, panelY + 12)
	end,

	-- Banner background placeholder
	Def.Quad {
		InitCommand = function(self)
			self:valign(0):zoomto(panelW - 24, (panelW - 24) / 3.2)
				:diffuse(color("0.04,0.04,0.04,1"))
		end
	},

	-- Banner sprite
	Def.Sprite {
		Name = "Banner",
		InitCommand = function(self)
			self:valign(0):scaletoclipped(panelW - 24, (panelW - 24) / 3.2)
			self.lastPath = ""
		end,
		SetCommand = function(self)
			self.song, self.group = selection.song, selection.group
			local bnpath = GetCurrentBannerPath()

			if bnpath and bnpath ~= "" then
				if bnpath ~= self.lastPath then
					self:Load(bnpath)
					self.lastPath = bnpath
				end
				self:scaletoclipped(panelW - 24, (panelW - 24) / 3.2)
				self:visible(true)
			else
				self:visible(false)
			end
		end,
		InstantChartUpdateMessageCommand = function(self)
			if self.song ~= selection.song or self.group ~= selection.group then self:visible(false) end
		end,
		HV_SelectionDetailsReadyMessageCommand = function(self)
			self:playcommand("Set")
		end
	},

	-- CDTitle
	Def.Sprite {
		Name = "CDTitle",
		InitCommand = function(self)
			-- Placed relative to the SongInfoFrame below instead
			self:visible(false)
		end,
	}
}

local bannerH = (panelW - 24) / 3.2
local infoY = panelY + 12 + bannerH + 16

-- ============================================================
-- SONG INFO TEXT
-- ============================================================
t[#t + 1] = Def.ActorFrame {
	Name = "SongInfoFrame",
	InitCommand = function(self)
		self:xy(panelX + 16, infoY)
	end,

	-- Song Title
	LoadFont("Zpix Normal") .. {
		Name = "SongTitle",
		InitCommand = function(self)
			self:halign(0):valign(0):zoom(0.7)
				:maxwidth((panelW - 32) / 0.7)
				:diffuse(brightText)
		end,
		SetCommand = function(self)
			local song = selection.song
			local group = selection.group
			if song then
				self:settext(song:GetDisplayMainTitle())
			elseif group then
				self:settext(group)
			else
				self:settext("")
			end
		end,
		InstantChartUpdateMessageCommand = function(self)
			self:playcommand("Set")
		end
	},

	-- Pack Stats (Songs and Average MSD)
	LoadFont("Common Normal") .. {
		Name = "PackStats",
		InitCommand = function(self)
			self:halign(0):valign(0):y(22):zoom(0.4)
				:diffuse(subText)
		end,
		SetCommand = function(self)
			local summary = selection.packSummary
			if summary then
				self:settextf("%d Songs\nProgress: %.1f%%", summary.count, summary.progress * 100)
				self:visible(true)
			else
				self:visible(false)
			end
		end,
		InstantChartUpdateMessageCommand = function(self) self:playcommand("Set") end,
		PackDetailsUpdateMessageCommand = function(self) self:playcommand("Set") end
	},

	-- Artist
	LoadFont("Common Normal") .. {
		Name = "SongArtist",
		InitCommand = function(self)
			self:halign(0):valign(0):y(22):zoom(0.45)
				:maxwidth((panelW - 32) / 0.45)
				:diffuse(subText)
		end,
		SetCommand = function(self)
			local song = selection.song
			if song then
				self:settext(song:GetDisplayArtist())
			else
				self:settext("")
			end
		end,
		InstantChartUpdateMessageCommand = function(self)
			self:playcommand("Set")
		end
	},

	-- Pack / Group Name
	LoadFont("Common Normal") .. {
		Name = "GroupName",
		InitCommand = function(self)
			self:halign(0):valign(0):y(40):zoom(0.35)
				:maxwidth((panelW - 32 - 50) / 0.35) -- Leave space for CDTitle
				:diffuse(dimText)
		end,
		SetCommand = function(self)
			local song = selection.song
			if song then
				self:settext(song:GetGroupName())
			else
				self:settext("")
			end
		end,
		InstantChartUpdateMessageCommand = function(self)
			self:playcommand("Set")
		end
	},

	Def.ActorFrame {
		Name = "CDTitleBox",
		InitCommand = function(self)
			self:xy(panelW - 32, 22) -- Align to right edge
		end,
		SetCommand = function(self)
			local song = selection.song
			if song and song:HasCDTitle() then
				self:visible(true)
			else
				self:visible(false)
			end
		end,
		HV_SelectionDetailsReadyMessageCommand = function(self)
			self:playcommand("Set")
		end,
		
		-- Real CDTitle Sprite with Hover tooltips attached natively
		UIElements.SpriteButton(1, 1, nil) .. {
			Name = "CDTitle",
			InitCommand = function(self)
				self:halign(1):valign(0)
			end,
			SetCommand = function(self)
				self:finishtweening()
				self.song = selection.song
				if self.song and self.song:HasCDTitle() then
					local path = self.song:GetCDTitlePath()
					if path and path ~= "" then
						if path ~= self.lastPath then
							self:Load(path)
							self.lastPath = path
						end
						self:visible(true)
					else
						self:visible(false)
					end
				else
					self:visible(false)
				end
				
				local maxDim = 32 -- Smaller to fit next to text
				local w, h = self:GetWidth(), self:GetHeight()
				if w > 0 and h > 0 then
					local scale = math.min(maxDim / w, maxDim / h)
					self:zoom(scale)
				end
			end,
			InstantChartUpdateMessageCommand = function(self)
				if self.song ~= selection.song then self:visible(false) end
			end,
			HV_SelectionDetailsReadyMessageCommand = function(self)
				self:playcommand("Set")
			end,
			ToolTipCommand = function(self)
				if (HV.ActiveTab or "") ~= "" then
					TOOLTIP:Hide()
					return
				end
				if isOver(self) then
					if self.song and self.song:HasCDTitle() and self:GetVisible() then
						TOOLTIP:SetText(GetCDTitleAuthor(self.song))
						TOOLTIP:Show()
					else
						TOOLTIP:Hide()
					end
				end
			end,
			MouseDownCommand = function(self, params)
				if (HV.ActiveTab or "") ~= "" then return end
				if params and params.button and params.button ~= "DeviceButton_left mouse button" then return end
				local author = GetCDTitleAuthor(self.song)
				if type(author) ~= "string" or author == "" or author:lower() == "none defined" then return end
				local currentQuery = HV.GetMusicSearchQuery and HV.GetMusicSearchQuery() or ""
				if HV.SetMusicSearchQuery then
					local authorQuery = "author=" .. author
					HV.SetMusicSearchQuery(currentQuery == authorQuery and "" or authorQuery)
				end
			end,
			MouseOverCommand = function(self)
				self:playcommand("ToolTip")
			end,
			MouseOutCommand = function(self)
				TOOLTIP:Hide()
			end,
			SelectMusicTabChangedMessageCommand = function(self, params)
				if params.Tab and params.Tab ~= "" then TOOLTIP:Hide() end
			end
		}
	},

	-- Separator line
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):y(60)
				:zoomto(panelW - 32, 1)
				:diffuse(color("0.18,0.18,0.18,1"))
		end
	}
}

-- ============================================================
-- CHART DETAILS (BPM, Length)
-- ============================================================
local detailY = infoY + 68

t[#t + 1] = Def.ActorFrame {
	Name = "ChartDetailsFrame",
	InitCommand = function(self)
		self:xy(panelX + 16, detailY)
	end,
	SetCommand = function(self)
		self:visible(selection.song ~= nil)
	end,
	InstantChartUpdateMessageCommand = function(self) self:playcommand("Set") end,

	-- BPM Label
	LoadFont("Common Normal") .. {
		Name = "BPMLabel",
		InitCommand = function(self)
			self:halign(0):valign(0):zoom(0.35):diffuse(dimText)
			self:settext(THEME:GetString("ScreenSelectMusic", "BPM"))
		end
	},
	-- BPM Value
	LoadFont("Common Normal") .. {
		Name = "BPMValue",
		InitCommand = function(self)
			self:halign(0):valign(0):x(40):zoom(0.4):diffuse(mainText)
		end,
		SetCommand = function(self)
			local song = selection.song
			if song then
				local bpms = song:GetDisplayBpms(true)
				local rate = selection.rate
				local b1 = bpms[1] * rate
				local b2 = bpms[2] * rate
				if math.abs(b1 - b2) < 1 then
					self:settext(string.format("%.0f", b1))
				else
					local mainBPM = getMainBPM(song, selection.steps) * rate
					self:settext(string.format("%.0f-%.0f (%.0f)", b1, b2, mainBPM))
				end
			else
				self:settext("---")
			end
		end,
		InstantChartUpdateMessageCommand = function(self)
			self:playcommand("Set")
		end,
		CurrentRateChangedMessageCommand = function(self)
			-- SelectionManager handles this now
		end
	},

	-- Length Label
	LoadFont("Common Normal") .. {
		Name = "LengthLabel",
		InitCommand = function(self)
			self:halign(0):valign(0):x(panelW * 0.35):zoom(0.35):diffuse(dimText)
			self:settext(THEME:GetString("ScreenSelectMusic", "Length"))
		end
	},
	LoadFont("Common Normal") .. {
		Name = "LengthValue",
		InitCommand = function(self)
			self:halign(0):valign(0):x(panelW * 0.35 + 56):zoom(0.4):diffuse(mainText)
		end,
		SetCommand = function(self)
			local len = selection.length
			if len then
				local mins = math.floor(len / 60)
				local secs = math.floor(len % 60)
				self:settext(string.format("%d:%02d", mins, secs))
				
				-- Color gradient based on length
				-- < 1:00 = white, 1:00-3:30 = green to yellow, 3:30-7:00 = yellow to red, 7:00-10:00 = red to purple, > 10:00 = purple
				if len < 60 then
					self:diffuse(color("1,1,1,1"))  -- White
				elseif len < 210 then  
					local t = (len - 60) / 150 
					local g = 1 - t * 0.5
					self:diffuse(color("0.5,"..g..",0.5,1"))  -- Green to Yellow
				elseif len < 420 then  
					local t = (len - 210) / 210 
					local r = 0.5 + t * 0.5 
					local g = 0.5 - t * 0.5 
					self:diffuse(color(r..","..g..",0.5,1"))  -- Yellow to Red
				elseif len < 600 then  
					local t = (len - 420) / 180 
					local b = 0.5 + t * 0.5 
					self:diffuse(color("1,0,"..b..",1"))  -- Red to Purple
				else
					self:diffuse(color("0.7,0,1,1"))  -- Purple
				end
			else
				self:settext("--:--")
				self:diffuse(mainText)
			end
		end,
		InstantChartUpdateMessageCommand = function(self)
			self:playcommand("Set")
		end,
		CurrentRateChangedMessageCommand = function(self)
			-- SelectionManager handles this now
		end
	},

	-- Average chart density uses the engine's rate-adjusted chart length.
	LoadFont("Common Normal") .. {
		Name = "NPSLabel",
		InitCommand = function(self)
			self:halign(0):valign(0):x(panelW * 0.65):zoom(0.35):diffuse(dimText)
			self:settext("NPS")
		end
	},
	LoadFont("Common Normal") .. {
		Name = "NPSValue",
		InitCommand = function(self)
			self:halign(0):valign(0):x(panelW * 0.65 + 40):zoom(0.4):diffuse(mainText)
		end,
		SetCommand = function(self)
			local nps = selection.nps
			if nps then
				self:settextf("%.2f", nps):diffuse(accentColor)
			else
				self:settext("-"):diffuse(dimText)
			end
		end,
		InstantChartUpdateMessageCommand = function(self) self:playcommand("Set") end,
	},
}

-- Separator between Details and MSD
t[#t + 1] = Def.Quad {
	Name = "DetailsMSDSeparator",
	InitCommand = function(self)
		self:halign(0):valign(0):xy(panelX + 16, detailY + 20)
			:zoomto(panelW - 32, 1)
			:diffuse(color("0.12,0.12,0.12,1"))
	end
}

-- ============================================================
-- MSD SKILLSET RATINGS (Simplified)
-- ============================================================
local msdY = detailY + 35
local skillsets = {"Overall", "Stream", "Jumpstream", "Handstream", "Stamina", "JackSpeed", "Chordjack", "Technical"}

t[#t + 1] = Def.ActorFrame {
	Name = "MSDFrame",
	InitCommand = function(self)
		self:xy(panelX + 16, msdY)
		local show = ThemePrefs.Get("HV_ShowMSD")
		self:visible(show == "true" or show == true)
	end,

	LoadFont("Common Normal") .. {
		Name = "MSDRatingsLabel",
		InitCommand = function(self)
			self:halign(0):valign(0):zoom(0.35):diffuse(accentColor)
		end,
		SetCommand = function(self)
			if not selection.song and selection.group then
				self:settext("AVERAGE MSD")
			else
				self:settext(THEME:GetString("ScreenSelectMusic", "MSDRatings"))
			end
		end,
		InstantChartUpdateMessageCommand = function(self) self:playcommand("Set") end,
	}
}

-- Create Overall Rating Row (Large)
t[#t + 1] = Def.ActorFrame {
	Name = "MSDRow_Overall",
	InitCommand = function(self)
		self:xy(panelX + 16, msdY + 18)
		local show = ThemePrefs.Get("HV_ShowMSD")
		self:visible(show == "true" or show == true)
	end,

	LoadFont("Common Large") .. {
		Name = "MSD_Overall",
		InitCommand = function(self)
			self:halign(0):valign(0):zoom(0.45):diffuse(mainText)
		end,
		SetCommand = function(self)
			local data = selection
			local msd = data.skillsetMSDs[1] -- Overall
			
			if data.packSummary then
				msd = data.packSummary.avgMSD
			end
			
			if msd and msd > 0 then
				self:settext(string.format("%.2f", msd))
				self:diffuse(HVColor.GetMSDRatingColor(msd))
			else
				self:settext("-")
				self:diffuse(dimText)
			end
		end,
		InstantChartUpdateMessageCommand = function(self) self:playcommand("Set") end,
		HV_SelectionDetailsReadyMessageCommand = function(self) self:playcommand("Set") end,
		PackDetailsUpdateMessageCommand = function(self) self:playcommand("Set") end,
	},
	
	-- Top 3 Skillsets Displays
	Def.ActorFrame {
		Name = "TopSkillsetIcons",
		InitCommand = function(self)
			self:xy(105, -6) -- Moved down 4px for better vertical alignment
		end,
		
		-- Container for Icon 1
		Def.ActorFrame {
			Name = "IconContainer1",
			InitCommand = function(self) self:x(0) end,
			Def.Sprite { Name = "Img", InitCommand = function(self) self:y(0):zoom(0.5):visible(false) end },
			LoadFont("Common Normal") .. { Name = "Lbl", InitCommand = function(self) self:y(30):zoom(0.28):diffuse(dimText):visible(false) end }
		},
		-- Container for Icon 2
		Def.ActorFrame {
			Name = "IconContainer2",
			InitCommand = function(self) self:x(55) end,
			Def.Sprite { Name = "Img", InitCommand = function(self) self:y(0):zoom(0.5):visible(false) end },
			LoadFont("Common Normal") .. { Name = "Lbl", InitCommand = function(self) self:y(30):zoom(0.28):diffuse(dimText):visible(false) end }
		},
		-- Container for Icon 3
		Def.ActorFrame {
			Name = "IconContainer3",
			InitCommand = function(self) self:x(110) end,
			Def.Sprite { Name = "Img", InitCommand = function(self) self:y(0):zoom(0.5):visible(false) end },
			LoadFont("Common Normal") .. { Name = "Lbl", InitCommand = function(self) self:y(30):zoom(0.28):diffuse(dimText):visible(false) end }
		},
		
		SetCommand = function(self)
			local c1 = self:GetChild("IconContainer1")
			local c2 = self:GetChild("IconContainer2")
			local c3 = self:GetChild("IconContainer3")
			c1:GetChild("Img"):visible(false) c1:GetChild("Lbl"):visible(false)
			c2:GetChild("Img"):visible(false) c2:GetChild("Lbl"):visible(false)
			c3:GetChild("Img"):visible(false) c3:GetChild("Lbl"):visible(false)
			
			local data = selection
			if not data.song or not data.steps then return end
			
			local vals = {}
			local ssNames = {"Stream", "Jumpstream", "Handstream", "Stamina", "JackSpeed", "Chordjack", "Technical"}
			for i, name in ipairs(ssNames) do
				local m = data.skillsetMSDs[i + 1]
				if m and m > 0 then table.insert(vals, {name = name, val = m}) end
			end
			
			table.sort(vals, function(a, b) return a.val > b.val end)
			
			if #vals >= 1 then 
				self:GetParent():playcommand("LoadSkillsetIcon", {container = c1, name = vals[1].name})
			end
			if #vals >= 2 then 
				self:GetParent():playcommand("LoadSkillsetIcon", {container = c2, name = vals[2].name})
			end
			if #vals >= 3 then 
				self:GetParent():playcommand("LoadSkillsetIcon", {container = c3, name = vals[3].name})
			end
		end,
		LoadSkillsetIconCommand = function(self, params)
			local c = params.container
			local name = params.name
			local path = THEME:GetPathG("", "skillsets/" .. string.lower(name) .. ".png")
			c:GetChild("Img"):Load(path):visible(true)
			c:GetChild("Lbl"):settext(name):visible(true)
		end,
		InstantChartUpdateMessageCommand = function(self) self:playcommand("Set") end,
		HV_SelectionDetailsReadyMessageCommand = function(self) self:playcommand("Set") end,
	}
}

-- ============================================================
-- MSD SKILLSET TOOLTIP (Mouse-following, 4-up/3-down grid)
-- ============================================================
local msdTooltipW = 280
local msdTooltipH = 56

local msdTooltipActor = nil
local msdTooltip = Def.ActorFrame {
	Name = "MSDTooltip",
	InitCommand = function(self)
		msdTooltipActor = self
		self:visible(false)
	end,
	-- Background
	HV_SelectionDetailsReadyMessageCommand = function(self)
		if self:GetVisible() then self:playcommand("Set") end
	end,

	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(1):zoomto(msdTooltipW, msdTooltipH):diffuse(color("0.05,0.05,0.05,0.95"))
		end
	},
	-- Border
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(1):zoomto(msdTooltipW, 1):y(-msdTooltipH):diffuse(accentColor):diffusealpha(0.5)
		end
	}
}

-- 7 skillsets (no Overall): 4 on top row, 3 on bottom row
local tooltipSkillsets = {
	{name="Stream", idx=2}, {name="Jumpstream", idx=3}, {name="Handstream", idx=4}, {name="Stamina", idx=5},
	{name="JackSpeed", idx=6}, {name="Chordjack", idx=7}, {name="Technical", idx=8}
}

for i, ss in ipairs(tooltipSkillsets) do
	local col, row, colW, offsetX
	if i <= 4 then
		row = 0
		col = i - 1
		colW = msdTooltipW / 4
		offsetX = col * colW + (colW / 2)
	else
		row = 1
		col = i - 5
		colW = msdTooltipW / 3
		offsetX = col * colW + (colW / 2)
	end

	local offsetY = -msdTooltipH + 12 + row * 24

	msdTooltip[#msdTooltip + 1] = Def.ActorFrame {
		InitCommand = function(self)
			self:xy(offsetX, offsetY)
		end,
		LoadFont("Common Normal") .. {
			InitCommand = function(self) self:y(-7):zoom(0.22):diffuse(subText):settext(ss.name) end
		},
		LoadFont("Common Normal") .. {
			Name = "Val",
			InitCommand = function(self) self:y(5):zoom(0.35):diffuse(mainText) end,
			SetCommand = function(self)
				local msd = selection.skillsetMSDs[ss.idx]
				if msd and msd > 0 then
					self:settextf("%.2f", msd):diffuse(HVColor.GetMSDRatingColor(msd))
				else
					self:settext("-"):diffuse(dimText)
				end
			end
		}
	}
end
t[#t + 1] = msdTooltip

-- Mouse Handler for MSD Tooltip
t[#t + 1] = Def.ActorFrame {
	Name = "MSDTooltipHandler",
	OnCommand = function(self)
		self:queuecommand("Tick")
	end,
	TickCommand = function(self)
		if msdTooltipActor then
			-- The label is at msdY and the number is at msdY + 18 with zoom ~0.45.
			-- The text height is around 40px, so 18 + 40 = 58.
			local isHovering = IsMouseOver(panelX + 10, msdY + 14, 120, 48)
			if isHovering and HV.ShowMSD() then
				local mx, my = INPUTFILTER:GetMouseX(), INPUTFILTER:GetMouseY()
				local wasHidden = not msdTooltipActor:GetVisible()
				msdTooltipActor:visible(true):xy(mx + 5, my - 15)
				if wasHidden then
					msdTooltipActor:playcommand("Set")
				end
			else
				msdTooltipActor:visible(false)
			end
		end
		self:sleep(0.02):queuecommand("Tick")
	end
}



-- ============================================================
-- DIFFICULTY SELECTOR TABS (Vertical, right of sidebar)
-- ============================================================
local diffTabW = 64 -- Smaller
local diffTabH = 26 -- Smaller
local diffShort = {Beginner = "BG", Easy = "EZ", Medium = "MD", Hard = "HD", Challenge = "CH", Edit = "ED"}
local diffSelectorX = panelX + panelW + 14
local diffSelectorTopY = panelY + 8
local diffRowStep = diffTabH + 3
local function diffRowTop(i)
	return diffSelectorTopY + 16 + (i - 1) * diffRowStep
end

t[#t + 1] = Def.ActorFrame {
	Name = "DifficultySelector",
	InitCommand = function(self)
		self:xy(diffSelectorX, diffSelectorTopY)
	end,

	-- Header and Style Toggle
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:halign(0):valign(0):zoom(0.28):diffuse(accentColor)
			self:settext(THEME:GetString("ScreenSelectMusic", "Chart"))
		end
	},

	-- Style Toggle Buttons (S / D)
	Def.ActorFrame {
		Name = "StyleToggle",
		InitCommand = function(self) self:xy(diffTabW - 25, 0) end,
		SetCommand = function(self)
			local data = selection
			self:visible(styleModeSupportsSingleDoubleToggle() and data.hasSingle and data.hasDouble)
		end,
		ChartListUpdateMessageCommand = function(self) self:playcommand("Set") end,
		
		LoadFont("Common Normal") .. {
			Name = "Single",
			InitCommand = function(self) self:x(0):zoom(0.28):settext("S") end,
			SetCommand = function(self)
				local data = selection
				local style = GAMESTATE:GetCurrentStyle()
				local isS = style and style:GetName() == "single"
				self:diffuse(isS and accentColor or dimText)
				self:diffusealpha(data.hasSingle and 1 or 0.2)
			end,
			ChartListUpdateMessageCommand = function(self) self:playcommand("Set") end,
		},
		LoadFont("Common Normal") .. {
			Name = "Double",
			InitCommand = function(self) self:x(12):zoom(0.28):settext("D") end,
			SetCommand = function(self)
				local data = selection
				local style = GAMESTATE:GetCurrentStyle()
				local isD = style and style:GetName() == "double"
				self:diffuse(isD and accentColor or dimText)
				self:diffusealpha(data.hasDouble and 1 or 0.2)
			end,
			ChartListUpdateMessageCommand = function(self) self:playcommand("Set") end,
		}
	}
}

-- Dynamic Chart Slots
for i = 1, maxVisibleCharts do
	t[#t + 1] = Def.ActorFrame {
		Name = "DiffSlot_" .. i,
		InitCommand = function(self)
			self:xy(diffSelectorX, diffRowTop(i)):visible(false)
		end,
		ChartListUpdateMessageCommand = function(self) self:visible(true) end,

		Def.Quad {
			Name = "Bg",
			InitCommand = function(self)
				self:halign(0):valign(0):zoomto(diffTabW, diffTabH)
					:diffuse(color("0.08,0.08,0.08,1"))
			end,
			SetCommand = function(self)
				local data = selection
				local entry = data.displayCharts[i + data.chartOffset]
				if not entry then
					self:visible(false)
					return
				end
				self:visible(true)
				
				if entry.isPlaceholder then
					self:diffuse(color("0.05,0.05,0.05,1")):diffusealpha(0.3)
				else
					local curSteps = data.steps
					if curSteps == entry.steps then
						local dname = entry.difficulty
						local dcolor = (HVColor and HVColor.GetDifficultyColor and HVColor.GetDifficultyColor(dname))
							or (HVColor and HVColor.Difficulty and HVColor.Difficulty[dname])
							or accentColor
						self:diffuse(dcolor):diffusealpha(0.4)
					else
						self:diffuse(color("0.08,0.08,0.08,1")):diffusealpha(1)
					end
				end
			end,
			ChartListUpdateMessageCommand = function(self) self:playcommand("Set") end,
		},

		LoadFont("Common Normal") .. {
			Name = "Label",
			InitCommand = function(self)
				self:halign(0):valign(0.5)
					:xy(5, 13)
					:zoom(0.30):diffuse(mainText)
			end,
			SetCommand = function(self)
				local data = selection
				local entry = data.displayCharts[i + data.chartOffset]
				self:settext(entry and (diffShort[entry.difficulty] or "??") or "")
				self:diffusealpha(entry and entry.isPlaceholder and 0.2 or 1)
			end,
			ChartListUpdateMessageCommand = function(self) self:playcommand("Set") end,
		},

		LoadFont("Common Normal") .. {
			Name = "Author",
			InitCommand = function(self)
				self:halign(0):valign(0.5)
					:xy(5, 20)
					:zoom(0.25):diffuse(dimText)
			end,
			SetCommand = function(self)
				local data = selection
				local entry = data.displayCharts[i + data.chartOffset]
				if not entry or entry.isPlaceholder then 
					self:settext("") 
					return 
				end
				self:settext(entry.author)
			end,
			ChartListUpdateMessageCommand = function(self) self:playcommand("Set") end,
		},

		LoadFont("Common Normal") .. {
			Name = "MSDVal",
			InitCommand = function(self)
				self:halign(1):valign(0.5)
					:xy(diffTabW - 5, diffTabH / 2)
					:zoom(0.30):diffuse(dimText)
			end,
			SetCommand = function(self)
				local data = selection
				local entry = data.displayCharts[i + data.chartOffset]
				if not entry or entry.isPlaceholder then 
					self:settext("") 
					return 
				end
				
				local showMSD = (ThemePrefs.Get("HV_ShowMSD") == "true" or ThemePrefs.Get("HV_ShowMSD") == true)
				if showMSD then
					local msd = entry.steps:GetMSD(data.rate, 1) or 0
					if msd > 0 then
						self:settext(string.format("%.2f", msd))
						self:diffuse(HVColor.GetMSDRatingColor(msd))
					else
						self:settext("-")
						self:diffuse(dimText)
					end
				else
					self:settext(tostring(entry.steps:GetMeter()))
					self:diffuse(mainText)
				end
			end,
			ChartListUpdateMessageCommand = function(self) self:playcommand("Set") end,
		}
	}
end


local function isOverDifficultySelector(x, y)
	return selection.renderedSong ~= nil and selection.renderedSong == GAMESTATE:GetCurrentSong()
		and selection.renderedRate == getCurRateValue()
		and x >= diffSelectorX and x <= diffSelectorX + diffTabW
		and y >= diffRowTop(1) and y <= diffRowTop(maxVisibleCharts) + diffTabH
end

local function canScrollDifficultySelector(button)
	local offset = selection.chartOffset
	if button == "DeviceButton_mousewheel up" then return offset > 0 end
	if button == "DeviceButton_mousewheel down" then return offset < #selection.displayCharts - maxVisibleCharts end
	return false
end

local function capturesDifficultyScroll(button)
	return canScrollDifficultySelector(button)
		and isOverDifficultySelector(INPUTFILTER:GetMouseX(), INPUTFILTER:GetMouseY())
end

-- Difficulty selector click handler (vertical layout)
t[#t + 1] = Def.ActorFrame {
	Name = "DiffSelectorClickHandler",
	BeginCommand = function(self)
		local screen = SCREENMAN:GetTopScreen()
		if not screen or self.inputScreen then return end

		self.inputScreen = screen
		HV.CapturesDifficultyScroll = capturesDifficultyScroll
		self.inputCallback = function(event)
			if not event or not event.DeviceInput then return false end
			if HV.ChartPreviewActive then return false end
			local top = SCREENMAN:GetTopScreen()
			if not top or top:GetName() ~= "ScreenSelectMusic" then return false end
			if event.type ~= "InputEventType_FirstPress" then return false end
			if (HV.ActiveTab and HV.ActiveTab ~= "") then return false end

			local data = selection
			local mx, my = INPUTFILTER:GetMouseX(), INPUTFILTER:GetMouseY()
			if not isOverDifficultySelector(mx, my) then return false end
			local btn = event.DeviceInput.button

			-- Chart Slot Click
			if btn == "DeviceButton_left mouse button" then
				for i = 1, maxVisibleCharts do
					local ty = diffRowTop(i)
					if my >= ty and my <= ty + diffTabH then
						local entry = data.displayCharts[i + data.chartOffset]
						if entry and not entry.isPlaceholder then
							GAMESTATE:SetPreferredDifficulty(PLAYER_1, entry.steps:GetDifficulty())
							GAMESTATE:SetCurrentSteps(PLAYER_1, entry.steps)
							return true
						end
					end
				end
			end

			if canScrollDifficultySelector(btn) then
				data.chartOffset = data.chartOffset + (btn == "DeviceButton_mousewheel down" and 1 or -1)
				MESSAGEMAN:Broadcast("ChartListUpdate")
				return true
			end

			return false
		end
		screen:AddInputCallback(self.inputCallback)
	end,
	OffCommand = function(self)
		if self.inputScreen then self.inputScreen:RemoveInputCallback(self.inputCallback) end
		self.inputScreen, self.inputCallback = nil, nil
		if HV.CapturesDifficultyScroll == capturesDifficultyScroll then HV.CapturesDifficultyScroll = nil end
	end,
}

local pbY = msdY + 60

t[#t + 1] = Def.ActorFrame {
	InitCommand = function(self) self:xy(panelX + 16, pbY) end,
	LoadActor("personal_best.lua", selection, panelX, panelW, pbY),
	LoadActor("pack_msd_graph.lua", selection, panelW),
}

-- ============================================================
-- COMPACT PROFILE + LOGIN (Right of Left Panel / Lower Half)
-- ============================================================
local compactProfileY = SCREEN_HEIGHT - footerH - 75
local compactProfileX = panelX + panelW + 16

t[#t + 1] = Def.ActorFrame {
	Name = "SmallProfileFrame",
	InitCommand = function(self)
		self:xy(compactProfileX, compactProfileY)
		self.hv_nameCycling = false
		self.hv_showingLocalName = false
	end,

	-- Card background for profile
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(-8, -8)
				:zoomto(180, 65)
				:diffuse(color("0.05,0.05,0.05,0.85"))
		end
	},
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(-8, -8)
				:zoomto(2, 65)
				:diffuse(accentColor)
		end
	},

	-- Avatar
	Def.Sprite {
		Name = "PlayerAvatar",
		InitCommand = function(self)
			self:halign(0):valign(0):y(0)
		end,
		SetCommand = function(self)
			local profile = PROFILEMAN:GetProfile(PLAYER_1)
			if profile then
				local avatarPath = getAvatarPath(PLAYER_1)
				if avatarPath and avatarPath ~= "" and FILEMAN:DoesFileExist(avatarPath) then
					self:Load(avatarPath)
				else
					local fallback = "/Assets/Avatars/_fallback.png"
					if FILEMAN:DoesFileExist(fallback) then self:Load(fallback) end
				end
				self:scaletoclipped(49, 49):visible(true)
			else
				self:visible(false)
			end
		end,
		OnCommand = function(self) self:playcommand("Set") end,
		-- Removed CurrentSongChanged trigger to avoid redundant reloads
	},

	-- Profile name
	LoadFont("Common Normal") .. {
		Name = "ProfileName",
		InitCommand = function(self)
			local zoom = 0.44
			self:halign(0):valign(0):x(56):y(6):zoom(zoom):maxwidth(80 / zoom):diffuse(mainText)
			self.showOnline = true
			self.transitionDuration = 0.25
			self.displayDuration = 3
		end,
		SetCommand = function(self)
			self:stoptweening():diffusealpha(1)
			local parent = self:GetParent()
			local profile = PROFILEMAN:GetProfile(PLAYER_1)
			self.onlineName = DLMAN:IsLoggedIn() and DLMAN:GetUsername() or nil
			self.offlineName = profile and profile:GetDisplayName() or nil
			if self.onlineName == "" then self.onlineName = nil end
			if self.offlineName == "" then self.offlineName = nil end

			if parent then
				parent.hv_nameCycling = false
				parent.hv_showingLocalName = false
			end

			if not self.onlineName then
				self:settext(self.offlineName or "Player 1")
			elseif not self.offlineName or self.onlineName == self.offlineName then
				self:settext(self.onlineName)
			else
				self.showOnline = true
				if parent then parent.hv_nameCycling = true end
				self:playcommand("SwapName")
				return
			end

			if parent then
				local rank = parent:GetChild("Rank")
				if rank then rank:playcommand("Set") end
			end
		end,
		UpdateNameCommand = function(self)
			local parent = self:GetParent()
			if not parent or not parent.hv_nameCycling then return end
			local rating = parent:GetChild("Rating")
			if rating then rating:playcommand("FadeOut") end
			self:stoptweening():linear(self.transitionDuration * 0.5):diffusealpha(0):queuecommand("SwapName")
		end,
		SwapNameCommand = function(self)
			local parent = self:GetParent()
			local showingLocal = not self.showOnline
			local nextName = self.showOnline and self.onlineName or self.offlineName
			self:settext(nextName)
			if parent then
				parent.hv_showingLocalName = showingLocal
				local rank = parent:GetChild("Rank")
				if rank then rank:playcommand("Set") end
				local rating = parent:GetChild("Rating")
				if rating then
					rating:stoptweening():playcommand("FadeIn")
				end
			end
			self.showOnline = not self.showOnline
			self:stoptweening():linear(self.transitionDuration * 0.5):diffusealpha(1):sleep(self.displayDuration):queuecommand("UpdateName")
		end,
		LoginMessageCommand = function(self) self:playcommand("Set") end,
		LogOutMessageCommand = function(self) self:playcommand("Set") end,
		OnlineUpdateMessageCommand = function(self) self:playcommand("Set") end,
		OnCommand = function(self) self:playcommand("Set"):diffusealpha(1) end
	},

	-- Rank (Top Right)
	LoadFont("Common Normal") .. {
		Name = "Rank",
		InitCommand = function(self)
			self:halign(1):valign(0):x(164):y(10):zoom(0.30)
		end,
		SetCommand = function(self)
			local showProfileStats = HV.ShowProfileStats()
			if not (showProfileStats == "true" or showProfileStats == true) then
				self:visible(false)
				return
			end

			local parent = self:GetParent()
			if parent and parent.hv_nameCycling and parent.hv_showingLocalName then
				self:visible(false)
				return
			end
			
			if DLMAN:IsLoggedIn() then
				local rank = DLMAN:GetSkillsetRank("Overall")
				local rankColor = color("#A6A6A6")
				if rank and rank > 0 then
					if rank <= 10 then rankColor = color("#CFD198")
					elseif rank <= 50 then rankColor = color("#A0CFAB")
					elseif rank <= 100 then rankColor = color("#80C0CF")
					elseif rank <= 500 then rankColor = color("#D9D9D9")
					end
				else
					rankColor = color("#737373")
				end
				self:settextf("#%d", rank):diffuse(rankColor):visible(true)
			else
				self:settext("OFFLINE"):diffuse(dimText):visible(true)
			end
		end,
		LoginMessageCommand = function(self) self:playcommand("Set") end,
		LogOutMessageCommand = function(self) self:playcommand("Set") end,
		OnlineUpdateMessageCommand = function(self) self:playcommand("Set") end,
		OnCommand = function(self) self:playcommand("Set") end
	},

	-- Rating
	LoadFont("Common Large") .. {
		Name = "Rating",
		InitCommand = function(self)
			self:halign(0):valign(1):x(56):y(30):zoom(0.35)
			self.transitionDuration = 0.25
		end,
		FadeOutCommand = function(self)
			local parent = self:GetParent()
			if not parent or not parent.hv_nameCycling then return end
			self:stoptweening():linear(self.transitionDuration * 0.5):diffusealpha(0)
		end,
		FadeInCommand = function(self)
			local parent = self:GetParent()
			if not parent or not parent.hv_nameCycling then
				self:playcommand("Set")
				self:diffusealpha(1)
				return
			end
			self:playcommand("Set")
			self:stoptweening():linear(self.transitionDuration * 0.5):diffusealpha(1)
		end,
		SetCommand = function(self)
			local showProfileStats = HV.ShowProfileStats()
			local showMSD = HV.ShowMSD()
			if not (showProfileStats == "true" or showProfileStats == true) or not showMSD then
				self:settext("")
				return
			end
			
			local parent = self:GetParent()
			local profile = PROFILEMAN:GetProfile(PLAYER_1)
			local onlineRating = DLMAN:IsLoggedIn() and DLMAN:GetSkillsetRating("Overall") or nil
			local offlineRating = profile and profile:GetPlayerRating() or nil

			local useLocal = parent and parent.hv_nameCycling and parent.hv_showingLocalName
			local rating = useLocal and (offlineRating or 0) or (onlineRating or 0)
			if rating <= 0 then
				rating = useLocal and (onlineRating or 0) or (offlineRating or 0)
			end

			if rating > 0 then
				self:settextf("%.2f", rating):diffuse(HVColor.GetMSDRatingColor(rating))
			else
				self:settext("-"):diffuse(dimText)
			end
		end,
		LoginMessageCommand = function(self) self:playcommand("Set") end,
		LogOutMessageCommand = function(self) self:playcommand("Set") end,
		OnlineUpdateMessageCommand = function(self) self:playcommand("Set") end,
		OnCommand = function(self) self:playcommand("Set") end
	},

	-- Stats (Bottom Right)
	LoadFont("Common Normal") .. {
		Name = "Stats",
		InitCommand = function(self)
			self:halign(1):valign(1):x(164):y(54):zoom(0.30):diffuse(subText)
		end,
		SetCommand = function(self)
			local showProfileStats = HV.ShowProfileStats()
			if not (showProfileStats == "true" or showProfileStats == true) then
				self:visible(false)
				return
			end
			
			local profile = PROFILEMAN:GetProfile(PLAYER_1)
			if profile then
				local notesHit = profile:GetTotalTapsAndHolds()
				local playtimeSecs = profile:GetTotalGameplaySeconds() --profile:GetTotalSessionSeconds() custom edit to show playtime instead of sesh time
				self:settextf("%s: %d\n%s: %d:%02d", 
					THEME:GetString("ScreenSelectMusic", "NotesFormatted"), notesHit, 
					THEME:GetString("ScreenSelectMusic", "PlaytimeFormatted"), math.floor(playtimeSecs/60), playtimeSecs%60):visible(true)
			else
				self:visible(false)
			end
		end,
		LoginMessageCommand = function(self) self:playcommand("Set") end,
		LogOutMessageCommand = function(self) self:playcommand("Set") end,
		OnlineUpdateMessageCommand = function(self) self:playcommand("Set") end,
		OnCommand = function(self) self:playcommand("Set") end
	},

	-- Integrated Login Button Area (Moved Above Profile)
	Def.ActorFrame {
		Name = "LoginButtonUI",
		InitCommand = function(self)
			self:xy(0, -22) -- Above the profile picture
		end,
		BeginCommand = function(self)
			if not DLMAN:IsLoggedIn() then
				local user = ThemePrefs.Get("HV_Username")
				local token = ThemePrefs.Get("HV_PasswordToken")
				if user and token and user ~= "" and token ~= "" then
					DLMAN:LoginWithToken(user, token)
				end
			end
		end,
		Def.Quad {
			Name = "Bg",
			InitCommand = function(self)
				self:halign(0):zoomto(80, 24):diffuse(accentColor):diffusealpha(0.8)
			end,
			SetMessageCommand = function(self)
				if DLMAN:IsLoggedIn() then
					self:diffuse(color("0.1,0.28,0.15,0.8"))
				else
					self:diffuse(accentColor):diffusealpha(0.8)
				end
			end,
			LoginMessageCommand = function(self) self:playcommand("Set") end,
			LogOutMessageCommand = function(self) self:playcommand("Set") end,
		},
		LoadFont("Common Normal") .. {
			Name = "Txt",
			InitCommand = function(self) self:halign(0.5):xy(40, 0):zoom(0.3) end,
			SetMessageCommand = function(self)
				if DLMAN:IsLoggedIn() then
					self:settext(THEME:GetString("ScreenSelectMusic", "LogOut")):diffuse(color("0.65,1,0.72,1"))
				else
					self:settext(THEME:GetString("ScreenSelectMusic", "LogIn")):diffuse(brightText)
				end
			end,
			LoginMessageCommand = function(self) self:playcommand("Set") end,
			LogOutMessageCommand = function(self) self:playcommand("Set") end,
			OnCommand = function(self) self:playcommand("Set") end
		}
	}
}


-- ============================================================
-- MUSIC RATE DISPLAY
-- ============================================================
t[#t + 1] = Def.ActorFrame {
	Name = "RateDisplay",
	InitCommand = function(self) 
		self:xy(panelX + panelW - 40, panelY + 4) 
	end,
	LoadFont("Common Normal") .. {
		Name = "RateLabel",
		InitCommand = function(self) self:halign(1):valign(0):x(-2):zoom(0.35):diffuse(dimText):settext(THEME:GetString("ScreenSelectMusic", "Rate")) end
	},
	LoadFont("Common Normal") .. {
		Name = "RateValue",
		InitCommand = function(self) self:halign(0):valign(0):zoom(0.4):diffuse(accentColor):playcommand("Set") end,
		SetCommand = function(self)
			local rate = getCurRateValue() or 1
			if math.abs(rate - 1.0) < 0.005 then
				self:settext("1.0x"):diffuse(mainText)
			else
				self:settext(string.format("%.2fx", rate)):diffuse(accentColor)
			end
		end,
		CurrentRateChangedMessageCommand = function(self) self:playcommand("Set") end
	}
}

-- ============================================================
-- RADAR INTEGRATION
-- ============================================================
t[#t + 1] = Def.ActorFrame {
	InitCommand = function(self)
		self:xy(compactProfileX + 85, compactProfileY - 80)
		self:zoom(1.0)
	end,
	LoadActor("radar.lua", selection)
}

-- ============================================================
-- CREDIT TOOLTIP (Mouse-following)
-- ============================================================
local creditTooltipActor = nil
local creditTooltip = Def.ActorFrame {
	Name = "CreditTooltip",
	InitCommand = function(self)
		creditTooltipActor = self
		-- Use a very high Z index here
		self:visible(false):z(9000)
	end,
	Def.Quad {
		Name = "Bg",
		InitCommand = function(self)
			self:halign(0):valign(0):diffuse(color("0.05,0.05,0.05,0.95"))
		end
	},
	Def.Quad {
		Name = "Border",
		InitCommand = function(self)
			self:halign(0):valign(0):diffuse(accentColor):diffusealpha(0.5)
		end
	},
	LoadFont("Common Normal") .. {
		Name = "Text",
		InitCommand = function(self)
			self:halign(0):valign(0):xy(8, 8):zoom(0.35):diffuse(mainText)
		end
	}
}
t[#t + 1] = creditTooltip

t[#t + 1] = Def.ActorFrame {
	Name = "CreditTooltipHandler",
	InitCommand = function(self)
		-- Removed redundant input callback to improve performance
	end,
	UpdateHoverCommand = function(self)
		if not creditTooltipActor then return end
		local song = selection.song
		if not song then creditTooltipActor:visible(false) return end

		local isHovering = IsMouseOver(panelX + 16, infoY, panelW - 16, 75)
		
		if isHovering then
			local ok, cStr = pcall(function() return song:GetCredit() end)
			if not ok or not cStr or cStr == "" then
				creditTooltipActor:visible(false)
				return
			end

			local mx, my = INPUTFILTER:GetMouseX(), INPUTFILTER:GetMouseY()
			local wasHidden = not creditTooltipActor:GetVisible()
			creditTooltipActor:visible(true):xy(mx + 15, my + 15)
			
			if wasHidden or creditTooltipActor._lastCredit ~= cStr then
				local txt = creditTooltipActor:GetChild("Text")
				local bg = creditTooltipActor:GetChild("Bg")
				local border = creditTooltipActor:GetChild("Border")
				
				txt:settextf(THEME:GetString("ScreenSelectMusic", "CreditFormatted"), cStr)
				local w = txt:GetZoomedWidth() + 16
				local h = txt:GetZoomedHeight() + 16
				bg:zoomto(w, h)
				border:zoomto(w, 1)
				creditTooltipActor._lastCredit = cStr
			end
		else
			creditTooltipActor:visible(false)
		end
	end,
	InstantChartUpdateMessageCommand = function(self)
		self:playcommand("UpdateHover")
	end
}

root[#root + 1] = Def.ActorFrame {
	Name = "MouseHoldPeekOverlay",
	InitCommand = function(self)
		self:draworder(12000):visible(false)
		self.hv_holdLerp = 0
		self.hv_holdTarget = 0
	end,
	OnCommand = function(self)
		self:playcommand("Set")
		self:SetUpdateFunction(function(actor)
			actor.hv_holdLerp = actor.hv_holdLerp + (actor.hv_holdTarget - actor.hv_holdLerp) * 0.16
			local active = actor.hv_holdLerp > 0.01
			actor:visible(active)

			local cover = actor:GetChild("Cover")
			if cover then
				cover:diffusealpha(actor.hv_holdLerp)
			end

			local bg = actor:GetChild("PeekSongBackground")
			if bg and bg:GetVisible() then
				local mx = INPUTFILTER:GetMouseX() or SCREEN_CENTER_X
				local my = INPUTFILTER:GetMouseY() or SCREEN_CENTER_Y
				local nx = (mx / SCREEN_WIDTH) - 0.5
				local ny = (my / SCREEN_HEIGHT) - 0.5
				local moveScale = 1 - actor.hv_holdLerp
				local zoom = 1.10 + (0.12 * actor.hv_holdLerp)
				bg:xy(
					SCREEN_CENTER_X + (nx * 2 * 40 * moveScale),
					SCREEN_CENTER_Y + (ny * 2 * 24 * moveScale)
				)
				bg:zoomto(SCREEN_WIDTH * zoom, SCREEN_HEIGHT * zoom)
				bg:diffusealpha(actor.hv_holdLerp)
			end
		end)
	end,
	SetCommand = function(self)
		local held = HV.LeftMousePeekHold == true
		local allowed = held and HV.LeftMousePeekHoldAllowed == true
		self.hv_holdTarget = allowed and 1 or 0
		if allowed then
			self:playcommand("UpdateBanner")
		end
	end,
	UpdateBannerCommand = function(self)
		local bg = self:GetChild("PeekSongBackground")
		if not bg then return end
		local bgPath = GetCurrentSongBackgroundPath()
		if not bgPath then
			bg:visible(false)
			return
		end
		if bg.lastPath ~= bgPath then
			-- This overlay is the visible zoomed background.  Do not use the
			-- engine brightness-gated loader: mouse hold always reveals it.
			bg:Load(bgPath)
			bg.lastPath = bgPath
		end
		bg:visible(true):diffuse(color("1,1,1,1")):diffusealpha(self.hv_holdLerp)
	end,
	HVLeftMousePeekHoldChangedMessageCommand = function(self)
		self:playcommand("Set")
	end,
	CurrentSongChangedMessageCommand = function(self)
		if self:GetVisible() then
			self:playcommand("UpdateBanner")
		end
	end,
	HV_SelectionDetailsReadyMessageCommand = function(self)
		if self:GetVisible() then
			self:playcommand("UpdateBanner")
		end
	end,
	Def.Quad {
		Name = "Cover",
		InitCommand = function(self)
			self:xy(SCREEN_CENTER_X, SCREEN_CENTER_Y):zoomto(SCREEN_WIDTH, SCREEN_HEIGHT):diffuse(color("0,0,0,1")):diffusealpha(0)
		end
	},
	Def.Sprite {
		Name = "PeekSongBackground",
		InitCommand = function(self)
			self.lastPath = ""
			self:diffusealpha(0)
		end
	}
}

return root
