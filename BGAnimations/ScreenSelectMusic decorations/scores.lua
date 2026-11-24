--- Holographic Void: Scores Tab
-- Shows local score history and online leaderboard for the current chart
-- Online: DLMAN:GetChartLeaderBoard(ck) / RequestChartLeaderBoardFromOnline(ck, cb)

local accentColor = HVColor.Accent
local dimText = color("0.45,0.45,0.45,1")
local subText = color("0.65,0.65,0.65,1")
local mainText = color("0.85,0.85,0.85,1")
local brightText = color("1,1,1,1")
local bgCard = color("0.04,0.04,0.04,0.97")

local overlayW = 680
local overlayH = 400
local rowH = 34
local pageSize = 8
local rowsStartY = -overlayH/2 + 82
local currentPage = 1
local scoresActor = nil
local whee = nil

-- View modes
local VIEW_LOCAL = 1
local VIEW_ONLINE = 2
local currentView = VIEW_LOCAL

-- Sort modes
local SORT_SSR = 1
local SORT_WIFE = 2
local currentSort = SORT_SSR

-- Data
local localScores = {}
local onlineScores = {}
local displayedScores = {}
local onlineLoading = false
local onlineRequestToken = 0
local replayRequestToken = 0
local filterCurrentRate = true
local showInvalidScores = false
local displayAsJ4 = PREFSMAN:GetPreference("SortBySSRNormPercent")

local function IsOnlineScoreInvalid(score)
	if not score then return false end
	if type(score.GetEtternaValid) == "function" then
		local ok, valid = pcall(score.GetEtternaValid, score)
		if ok and valid == false then return true end
	end
	return IsScoreInvalid(score)
end

local function IsLocalScoreInvalid(score)
	if not score then return false end
	if type(score.GetEtternaValid) == "function" then
		local ok, valid = pcall(score.GetEtternaValid, score)
		if ok and valid == false then return true end
	end
	return IsScoreInvalid(score)
end

local function GetScoreDisplayName(score)
	if not score then return nil end
	local fallback
	local placeholders = {
		["Player 1"] = true, ["Player 2"] = true, ["Replay"] = true,
		["Unknown"] = true, ["???"] = true, [""] = true
	}
	for _, getterName in ipairs({"GetDisplayName", "GetName"}) do
		local getter = score[getterName]
		if type(getter) == "function" then
			local ok, name = pcall(getter, score)
			if ok and name then
				name = tostring(name)
				if not placeholders[name] then return name end
				fallback = fallback or name
			end
		end
	end
	return nil
end

-- ============================================================
-- DATA HELPERS
-- ============================================================

local function GetSSR(s)
	if not s then return 0 end
	if s.GetSkillsetSSR then return s:GetSkillsetSSR("Overall") end
	if s.GetSkillsetSum then return s:GetSkillsetSum() end
	if s.GetSkillSetSum then return s:GetSkillSetSum() end
	return 0
end

local function FiniteScoreValue(value)
	if type(value) == "number" and value == value and math.abs(value) < math.huge then return value end
end

local function SortScores(scores)
	local primary, secondary = "ssr", "wife"
	if currentSort == SORT_WIFE then primary, secondary = secondary, primary end
	table.sort(scores, function(a, b)
		local aPrimary, bPrimary = a[primary] or -math.huge, b[primary] or -math.huge
		if aPrimary ~= bPrimary then return aPrimary > bPrimary end
		local aSecondary, bSecondary = a[secondary] or -math.huge, b[secondary] or -math.huge
		if aSecondary ~= bSecondary then return aSecondary > bSecondary end
		if a.date ~= b.date then return a.date > b.date end
		if a.key ~= b.key then return a.key < b.key end
		return a.sourceIndex < b.sourceIndex
	end)
end

-- ============================================================
-- DATA FETCHING
-- ============================================================

local function GetLocalScores()
	localScores = {}
	local steps = GAMESTATE:GetCurrentSteps()
	if not steps then return end
	local ck = steps:GetChartKey()
	if not ck then return end
	local sl = SCOREMAN:GetScoresByKey(ck)
	if not sl then return end

	local currentRate = getCurRateValue()

	for rateName, scoreList in pairs(sl) do
		local rNum = tonumber((rateName:gsub("x", ""))) or 0
		-- Apply rate filter if enabled (tolerate small floating point differences)
		if not filterCurrentRate or math.abs(rNum - currentRate) < 0.001 then
			local scores = scoreList:GetScores()
			if scores then
				for _, s in ipairs(scores) do
					localScores[#localScores + 1] = s
				end
			end
		end
	end
end

local function FetchOnlineScores()
	onlineRequestToken = onlineRequestToken + 1
	local requestToken = onlineRequestToken
	onlineScores = {}
	onlineLoading = true

	local steps = GAMESTATE:GetCurrentSteps()
	if not steps then
		onlineLoading = false
		return
	end

	local ck = steps:GetChartKey()
	if not ck then
		onlineLoading = false
		return
	end

	if not DLMAN:IsLoggedIn() then
		onlineLoading = false
		return
	end

	-- Try cached first
	local cached = DLMAN:GetChartLeaderBoard(ck)
	if cached and #cached > 0 then
		onlineScores = cached
		onlineLoading = false
		return
	end

	-- Request from server
	DLMAN:RequestChartLeaderBoardFromOnline(
		ck,
		function(leaderboard)
			if requestToken ~= onlineRequestToken then return end
			if type(leaderboard) == "table" then
				onlineScores = leaderboard
			else
				onlineScores = {}
			end
			onlineLoading = false
			local actor = scoresActor
			if actor then
				local ok = pcall(function() actor:queuecommand("RefreshScores") end)
				if not ok then scoresActor = nil end
			end
		end
	)
end

local function ViewScore(score)
	if not score then return end
	local screen = SCREENMAN:GetTopScreen()
	if screen and screen.ShowEvalScreenForScore then
		HV.OnlineReplayActive = false
		HV.OnlineReplayName = nil
		HV.OnlineEvaluationActive = nil
		HV.OnlineEvaluationName = nil
		screen:ShowEvalScreenForScore(score)
	end
end

local function GetOnlineScoreID(score)
	if not score then return nil end
	for _, getterName in ipairs({"GetOnlineScoreID", "GetScoreid", "GetScoreID", "GetID"}) do
		local getter = score[getterName]
		if type(getter) == "function" then
			local ok, id = pcall(getter, score)
			if ok and id ~= nil and tostring(id) ~= "" then return id end
		end
	end
	return nil
end

local function requestSelectedOnlineReplay(score, onReady)
	local screen = SCREENMAN:GetTopScreen()
	replayRequestToken = replayRequestToken + 1
	local token = replayRequestToken
	DLMAN:RequestOnlineScoreReplayData(score, function()
		if token ~= replayRequestToken or SCREENMAN:GetTopScreen() ~= screen or screen:IsTransitioning()
			or currentView ~= VIEW_ONLINE or not scoresActor or not scoresActor:GetVisible() then return end
		local steps = GAMESTATE:GetCurrentSteps()
		if not steps or steps:GetChartKey() ~= score:GetChartKey() then return end
		if not score:HasReplayData() then
			ms.ok("Replay not available")
			return
		end
		onReady(screen)
	end)
end

local function ShowScoreOffsetPlot(score)
	if score and SCREENMAN.AddNewScreenToTop then
		local open = function()
			HV.PendingScoreOffsetPlot = score
			SCREENMAN:AddNewScreenToTop("ScreenScoreTabOffsetPlot")
		end
		if currentView == VIEW_ONLINE and type(DLMAN.RequestOnlineScoreReplayData) == "function" then
			requestSelectedOnlineReplay(score, open)
		else
			open()
		end
		return true
	end
	return false
end

local function OpenOnlinePlayer(score)
	local name = GetScoreDisplayName(score)
	if name and name ~= "" and type(DLMAN.ShowUserPage) == "function" then
		DLMAN:ShowUserPage(name)
		return true
	end
	return false
end

local function OpenOnlineScore(score)
	local name = GetScoreDisplayName(score)
	local id = GetOnlineScoreID(score)
	if name and id and type(DLMAN.ShowScorePage) == "function" then
		DLMAN:ShowScorePage(name, id)
		return true
	end
	return false
end

-- ============================================================
-- UI
-- ============================================================

local t = Def.ActorFrame {
	Name = "ScoresOverlay",
	InitCommand = function(self)
		scoresActor = self
		self:xy(SCREEN_CENTER_X, SCREEN_CENTER_Y):visible(false):diffusealpha(0)
	end,
	OffCommand = function(self)
		if scoresActor == self then scoresActor = nil end
	end,
	BeginCommand = function(self)
		local screen = SCREENMAN:GetTopScreen()
		if screen and screen.GetMusicWheel then whee = screen:GetMusicWheel() end
	end,
	SelectMusicTabChangedMessageCommand = function(self, params)
		replayRequestToken = replayRequestToken + 1
		if params.Tab == "SCORES" then
			self:visible(not self:GetVisible())
			if self:GetVisible() then
				self:stoptweening():diffusealpha(0):linear(0.2):diffusealpha(1)
				HV.ActiveTab = "SCORES"
				currentPage = 1
				currentView = VIEW_LOCAL
				GetLocalScores()
				self:playcommand("RefreshScores")
			else
				HV.ActiveTab = ""
			end
		else
			self:visible(false)
			onlineRequestToken = onlineRequestToken + 1
			if HV.ActiveTab == "SCORES" then HV.ActiveTab = "" end
		end
	end,
	TabNavigationMessageCommand = function(self, params)
		if self:GetVisible() and params and params.dir then
			local totalPages = math.max(1, math.ceil(#displayedScores / pageSize))
			currentPage = math.max(1, math.min(totalPages, currentPage + params.dir))
			self:playcommand("RefreshScoreRows")
		end
	end,
	CurrentStepsChangedMessageCommand = function(self)
		replayRequestToken = replayRequestToken + 1
		if self:GetVisible() then
			currentPage = 1
			if currentView == VIEW_LOCAL then
				GetLocalScores()
			else
				FetchOnlineScores()
			end
			self:playcommand("RefreshScores")
		end
	end,

	-- Background
	Def.Quad { InitCommand = function(self) self:zoomto(overlayW, overlayH):diffuse(bgCard) end },
	Def.Quad { InitCommand = function(self) self:valign(0):y(-overlayH/2):zoomto(overlayW, 2):diffuse(accentColor):diffusealpha(0.7) end },

	-- Title
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(-overlayW/2 + 25, -overlayH/2 + 15):zoom(0.5):diffuse(accentColor)
		end,
		RefreshScoresCommand = function(self)
			local song = GAMESTATE:GetCurrentSong()
			local steps = GAMESTATE:GetCurrentSteps()
			local viewLabel = currentView == VIEW_LOCAL and THEME:GetString("Scores", "Local") or THEME:GetString("Scores", "Online")
			if song and steps then
				local diff = ToEnumShortString(steps:GetDifficulty())
				self:settextf(THEME:GetString("Scores", "TitleGeneric"), viewLabel, song:GetDisplayMainTitle(), diff)
			else
				self:settextf(THEME:GetString("Scores", "TitleGenericNoChart"), viewLabel)
			end
		end
	},

	-- View toggle button (Merged LOCAL/ONLINE)
	Def.ActorFrame {
		InitCommand = function(self) self:xy(overlayW/2 - 55, -overlayH/2 + 18) end,
		Def.Quad {
			Name = "ToggleViewBg",
			InitCommand = function(self) self:zoomto(100, 18):diffuse(accentColor):diffusealpha(0.4) end,
			RefreshScoresCommand = function(self)
				if not DLMAN:IsLoggedIn() and currentView == VIEW_LOCAL then
					self:diffuse(color("#444444"))
				else
					self:diffuse(accentColor)
				end
			end,
		},
		LoadFont("Common Normal") .. {
			Name = "ToggleViewText",
			InitCommand = function(self) self:zoom(0.24):diffuse(brightText) end,
			RefreshScoresCommand = function(self)
				local viewName = currentView == VIEW_LOCAL and THEME:GetString("Scores", "Local") or THEME:GetString("Scores", "Online")
				self:settextf(THEME:GetString("Scores", "ViewToggle"), viewName)
				if currentView == VIEW_ONLINE and not DLMAN:IsLoggedIn() then
					self:diffuse(dimText)
				else
					self:diffuse(brightText)
				end
			end,
		},
	},

	-- Rate filter toggle button
	Def.ActorFrame {
		InitCommand = function(self) self:xy(overlayW/2 - 145, -overlayH/2 + 18) end,
		Def.Quad {
			Name = "RateBtnBg",
			InitCommand = function(self) self:zoomto(65, 18):diffuse(accentColor):diffusealpha(0.15) end,
			RefreshScoresCommand = function(self)
				self:diffusealpha(filterCurrentRate and 0.5 or 0.15)
			end,
		},
		LoadFont("Common Normal") .. {
			InitCommand = function(self) self:zoom(0.24):diffuse(brightText) end,
			RefreshScoresCommand = function(self)
				self:settext(filterCurrentRate and THEME:GetString("Scores", "FilterCurrRate") or THEME:GetString("Scores", "FilterAllRates"))
				self:diffusealpha(filterCurrentRate and 1 or 0.5)
			end,
		},
	},

	-- Sort toggle button
	Def.ActorFrame {
		InitCommand = function(self) self:xy(overlayW/2 - 215, -overlayH/2 + 18) end,
		Def.Quad {
			Name = "SortBtnBg",
			InitCommand = function(self) self:zoomto(65, 18):diffuse(accentColor):diffusealpha(0.15) end,
		},
		LoadFont("Common Normal") .. {
			InitCommand = function(self) self:zoom(0.24):diffuse(brightText) end,
			RefreshScoresCommand = function(self)
				self:settext(currentSort == SORT_SSR and THEME:GetString("Scores", "SortSSR") or THEME:GetString("Scores", "SortWife"))
				local bg = self:GetParent():GetChild("SortBtnBg")
				if bg then bg:diffusealpha(0.5) end
			end,
		},
	},

	-- J4 Display Toggle Button
	Def.ActorFrame {
		Name = "J4ToggleFrame",
		InitCommand = function(self) self:xy(overlayW/2 - 285, -overlayH/2 + 18) end,
		RefreshScoresCommand = function(self)
			local normPref = PREFSMAN:GetPreference("SortBySSRNormPercent")
			self:visible(not normPref)
		end,
		Def.Quad {
			Name = "J4BtnBg",
			InitCommand = function(self) self:zoomto(65, 18):diffuse(accentColor):diffusealpha(0.15) end,
			RefreshScoresCommand = function(self)
				self:diffusealpha(displayAsJ4 and 0.5 or 0.15)
			end,
		},
		LoadFont("Common Normal") .. {
			InitCommand = function(self) self:zoom(0.24):diffuse(brightText) end,
			RefreshScoresCommand = function(self)
				self:settext(displayAsJ4 and "Display: J4" or "Display: Raw")
				self:diffusealpha(displayAsJ4 and 1 or 0.5)
			end,
		},
	},

	-- Page info
	-- Invalid score visibility toggle (Online only)
	Def.ActorFrame {
		Name = "InvalidToggleFrame",
		InitCommand = function(self) self:xy(-overlayW/2 + 75, -overlayH/2 + 40) end,
		RefreshScoresCommand = function(self) self:visible(currentView == VIEW_ONLINE) end,
		Def.Quad { Name = "InvalidBtnBg", InitCommand = function(self) self:zoomto(100, 18):diffuse(color("#B01824")):diffusealpha(0.15) end,
			RefreshScoresCommand = function(self) self:diffusealpha(showInvalidScores and 0.65 or 0.15) end },
		LoadFont("Common Normal") .. { InitCommand = function(self) self:zoom(0.24):diffuse(brightText) end,
			RefreshScoresCommand = function(self)
				self:settext(showInvalidScores and "INVALID: ON" or "INVALID: OFF")
				self:diffusealpha(showInvalidScores and 1 or 0.55)
			end },
	},

	LoadFont("Common Normal") .. {
		Name = "PageInfo",
		InitCommand = function(self)
			self:halign(1):valign(0):xy(overlayW/2 - 16, -overlayH/2 + 30):zoom(0.24):diffuse(dimText)
		end,
	},

	-- Column headers
	Def.ActorFrame {
		InitCommand = function(self) self:xy(-overlayW/2 + 25, -overlayH/2 + 65) end,
		LoadFont("Common Normal") .. { InitCommand = function(self) self:halign(0):zoom(0.32):diffuse(dimText):settext("#") end },
		LoadFont("Common Normal") .. { Name = "HdrName", InitCommand = function(self) self:halign(0):x(30):zoom(0.32):diffuse(dimText):settext(THEME:GetString("Scores", "PlayerColumn")) end },
		LoadFont("Common Normal") .. { InitCommand = function(self) self:halign(0):x(190):zoom(0.32):diffuse(dimText):settext(THEME:GetString("Scores", "WifeColumn")) end },
		LoadFont("Common Normal") .. { InitCommand = function(self) self:halign(0):x(280):zoom(0.32):diffuse(dimText):settext(THEME:GetString("Scores", "SSRColumn")):visible(HV.ShowMSD()) end },
		LoadFont("Common Normal") .. { InitCommand = function(self) self:halign(0):x(345):zoom(0.32):diffuse(dimText):settext(THEME:GetString("Scores", "GradeColumn")) end },
		LoadFont("Common Normal") .. { InitCommand = function(self) self:halign(0):x(415):zoom(0.32):diffuse(dimText):settext(THEME:GetString("Scores", "RateColumn")) end },
		LoadFont("Common Normal") .. { InitCommand = function(self) self:halign(0):x(485):zoom(0.32):diffuse(dimText):settext(THEME:GetString("Scores", "ClearColumn")) end },
		LoadFont("Common Normal") .. { InitCommand = function(self) self:halign(1):x(overlayW - 50):zoom(0.32):diffuse(dimText):settext(THEME:GetString("Scores", "DateColumn")) end },
	},
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):xy(-overlayW/2 + 12, -overlayH/2 + 82)
				:zoomto(overlayW - 24, 1):diffuse(color("0.12,0.12,0.12,1"))
		end,
	},

	-- Loading indicator
	LoadFont("Common Normal") .. {
		Name = "LoadingText",
		InitCommand = function(self)
			self:xy(0, 0):zoom(0.35):diffuse(accentColor):settext(THEME:GetString("Common", "Loading")):visible(false)
		end,
		RefreshScoresCommand = function(self)
			self:visible(onlineLoading and currentView == VIEW_ONLINE)
		end,
	},

	-- Empty state message
	LoadFont("Common Normal") .. {
		Name = "EmptyState",
		InitCommand = function(self)
			self:xy(0, 0):zoom(0.35):diffuse(dimText):visible(false)
		end,
		RefreshScoresCommand = function(self)
			if #displayedScores == 0 and not (onlineLoading and currentView == VIEW_ONLINE) then
				self:visible(true)
				if currentView == VIEW_LOCAL then
					self:settext(THEME:GetString("Scores", "NoScoresLocal"))
				elseif not DLMAN:IsLoggedIn() then
					self:settext(THEME:GetString("Scores", "OnlineLoginRequired"))
				else
					self:settext(THEME:GetString("Scores", "NoScoresOnline"))
				end
			else
				self:visible(false)
			end
		end,
	},

	-- Hint
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:halign(0.5):valign(1):xy(0, overlayH/2 - 8):zoom(0.20):diffuse(dimText)
				:settext(THEME:GetString("Scores", "ScoreHint"))
		end,
	},
}

-- Score rows
for i = 1, pageSize do
	t[#t + 1] = Def.ActorFrame {
		Name = "ScoreRow_" .. i,
		InitCommand = function(self)
			self:xy(-overlayW/2 + 25, rowsStartY + (i-1) * rowH):diffusealpha(0)
		end,

		Def.Quad { Name = "Bg", InitCommand = function(self) self:halign(0):valign(0):zoomto(overlayW - 50, rowH - 4):diffuse(color("0,0,0,0.2")) end },
		LoadFont("Common Normal") .. { Name = "Rank", InitCommand = function(self) self:halign(0):valign(0.5):y(rowH/2):zoom(0.35):diffuse(dimText) end },
		LoadFont("Common Normal") .. { Name = "Player", InitCommand = function(self) self:halign(0):valign(0.5):x(30):y(rowH/2):zoom(0.42):diffuse(mainText):maxwidth(150 / 0.42) end },
		LoadFont("Common Normal") .. { Name = "Wife", InitCommand = function(self) self:halign(0):valign(0.5):x(190):y(rowH/2 - 5):zoom(0.40):diffuse(brightText) end },
		LoadFont("Common Normal") .. { Name = "Judge", InitCommand = function(self) self:halign(1):valign(0.5):x(185):y(rowH/2 - 5):zoom(0.30):diffuse(subText) end },
		LoadFont("Common Normal") .. { Name = "Judgments", InitCommand = function(self) self:halign(0):valign(0.5):x(190):y(rowH/2 + 8):zoom(0.28):diffuse(subText) end },
		LoadFont("Common Normal") .. { Name = "SSR", InitCommand = function(self) self:halign(0):valign(0.5):x(280):y(rowH/2):zoom(0.50):diffuse(brightText):visible(HV.ShowMSD()) end },
		LoadFont("Common Normal") .. { Name = "Grade", InitCommand = function(self) self:halign(0):valign(0.5):x(345):y(rowH/2):zoom(0.38) end },
		LoadFont("Common Normal") .. { Name = "Rate", InitCommand = function(self) self:halign(0):valign(0.5):x(415):y(rowH/2):zoom(0.38):diffuse(mainText) end },
		LoadFont("Common Normal") .. { Name = "Clear", InitCommand = function(self) self:halign(0):valign(0.5):x(485):y(rowH/2):zoom(0.35) end },
		LoadFont("Common Normal") .. { Name = "Date", InitCommand = function(self) self:halign(1):valign(0.5):x(overlayW - 90):y(rowH/2):zoom(0.32):diffuse(subText) end },
		LoadFont("Common Normal") .. { Name = "CC", InitCommand = function(self) self:halign(0):valign(0.5):x(30):y(rowH/2 + 8):zoom(0.28):diffuse(color("#FF0000")):settext("Chord Cohesion ON") end },
		-- Replay Button
		Def.ActorFrame {
			Name = "ReplayButton",
			InitCommand = function(self) self:xy(overlayW - 60, rowH / 2):zoom(0.32) end,
			RefreshScoresCommand = function(self)
				local idx = (currentPage - 1) * pageSize + i
				local entry = displayedScores[idx]
				if entry then
					if currentView == VIEW_LOCAL then
						self:visible(entry.score:HasReplayData())
					else
						self:visible(true)
					end
				else
					self:visible(false)
				end
			end,
			Def.Quad { Name = "Hit", InitCommand = function(self) self:zoomto(60, 60):diffusealpha(0) end },
			LoadActor(THEME:GetPathG("", "mp_play")) .. {
				InitCommand = function(self) self:diffuse(accentColor) end,
			},
		},

		RefreshScoresCommand = function(self)
			local idx = (currentPage - 1) * pageSize + i
			local scores = displayedScores

			if idx <= #scores then
				self:visible(true)
				self:stoptweening():diffusealpha(0):sleep(i * 0.04):linear(0.15):diffusealpha(1)
				local entry = scores[idx]
				local s = entry.score
				local rowInvalid = (currentView == VIEW_ONLINE and IsOnlineScoreInvalid(s))
					or (currentView == VIEW_LOCAL and IsLocalScoreInvalid(s))
				self:GetChild("Bg"):diffuse(rowInvalid and color("#7A1018") or color("0,0,0,0.2"))
				self:GetChild("Rank"):settext(tostring(idx))
				self:GetChild("Date"):settext(entry.date)
				local wifeFormat = entry.wife and (entry.wife >= 99.7 and "%.4f%%" or "%.2f%%")
				self:GetChild("Wife"):settext(wifeFormat and string.format(wifeFormat, entry.wife) or "-")
				self:GetChild("SSR"):settext(entry.ssr and string.format("%.2f", entry.ssr) or "-")
					:diffuse(entry.ssr and HVColor.GetMSDRatingColor(entry.ssr) or subText):visible(HV.ShowMSD())

				if currentView == VIEW_LOCAL then
					self:GetChild("Player"):settext(THEME:GetString("Common", "You"))
					
					local judge = displayAsJ4 and 4 or HV.Score.GetPlayedJudge(s)
					local tally, counts = HV.Score.GetDisplayTally(s, displayAsJ4 and 4 or nil)
					self:GetChild("Judgments"):settext(tally)
					self:GetChild("Judge"):settext(judge and ("J" .. judge) or "")
						:diffuse(displayAsJ4 and accentColor or subText)

					local grade = s:GetWifeGrade()
					if displayAsJ4 and grade ~= "Grade_Failed" then
						grade = entry.wife and GetGradeFromPercent(entry.wife / 100)
					end
					self:GetChild("Grade"):settext(grade and HV.GetGradeName(ToEnumShortString(grade)) or "-")
						:diffuse(grade and HVColor.GetGradeColor(ToEnumShortString(grade)) or subText)
					self:GetChild("Rate"):settextf("%.2fx", s:GetMusicRate())

					local ct = "-"
					if IsLocalScoreInvalid(s) then ct = "Invalid"
					elseif tally ~= "-" then ct = getDetailedClearType(s, counts) end
					self:GetChild("Clear"):settext(ct):diffuse(HVColor.GetClearTypeColor(ct) or subText)

					-- Chord Cohesion indicator
					local cc = self:GetChild("CC")
					if cc then
						cc:visible(s:GetChordCohesion())
					end
				else
					-- Online leaderboard score
					pcall(function()
						local username = GetScoreDisplayName(s) or "Unknown"
						self:GetChild("Player"):settext(username)

						local tally = HV.Score.GetDisplayTally(s)
						self:GetChild("Judgments"):settext(tally)

						self:GetChild("Judge"):settext("")

						local gradeStr = ToEnumShortString(s:GetWifeGrade())
						self:GetChild("Grade"):settext(HV.GetGradeName(gradeStr)):diffuse(HVColor.GetGradeColor(gradeStr))
						self:GetChild("Rate"):settextf("%.2fx", s:GetMusicRate())

						local ct = IsOnlineScoreInvalid(s) and "Invalid" or getDetailedClearType(s)
						self:GetChild("Clear"):settext(ct):diffuse(HVColor.GetClearTypeColor(ct))

						-- Chord Cohesion indicator (online scores might not always have this)
						local cc = self:GetChild("CC")
						if cc then
							if s.GetChordCohesion then
								cc:visible(s:GetChordCohesion())
							else
								cc:visible(false)
							end
						end
					end)
				end
			else
				self:visible(false)
			end
		end,
	}
end

local function UpdateDisplayedScores()
	displayedScores = {}
	local isLocal = currentView == VIEW_LOCAL
	local source = isLocal and localScores or onlineScores
	local currentRate = not isLocal and filterCurrentRate and getCurRateValue()
	for sourceIndex, score in ipairs(source) do
		if isLocal or ((showInvalidScores or not IsOnlineScoreInvalid(score))
			and (not currentRate or math.abs(score:GetMusicRate() - currentRate) < 0.001)) then
			local wife
			if isLocal and displayAsJ4 then
				local percent, available = getJ4NormalizedPercentage(score)
				if available ~= false then wife = percent end
			else
				local fraction = FiniteScoreValue(score:GetWifeScore())
				wife = fraction and fraction * 100
			end
			displayedScores[#displayedScores + 1] = {
				score = score,
				ssr = FiniteScoreValue(GetSSR(score)),
				wife = FiniteScoreValue(wife),
				date = score:GetDate() or "",
				key = score:GetScoreKey() or "",
				sourceIndex = sourceIndex,
			}
		end
	end
	SortScores(displayedScores)
end

t.RefreshScoresCommand = function(self)
	UpdateDisplayedScores()
	self:playcommand("RefreshScoreRows")
end

t.RefreshScoreRowsCommand = function(self)

	local scores = displayedScores
	local totalPages = math.max(1, math.ceil(#scores / pageSize))
	currentPage = math.min(currentPage, totalPages)

	local pageInfo = self:GetChild("PageInfo")
	if pageInfo then
		pageInfo:settextf(THEME:GetString("Common", "PageInfoDetailed"), currentPage, totalPages, #scores)
	end

	for ri = 1, pageSize do
		local row = self:GetChild("ScoreRow_" .. ri)
		if row then row:playcommand("RefreshScores") end
	end
end

-- Input handler
t[#t + 1] = Def.ActorFrame {
	BeginCommand = function(self)
		local screen = SCREENMAN:GetTopScreen()
		if not screen then return end
		screen:AddInputCallback(function(event)
			if not scoresActor or not scoresActor:GetVisible() then return false end
			if not event or not event.DeviceInput then return false end
			
			local btn = event.DeviceInput.button
			local isPress = event.type == "InputEventType_FirstPress"

			-- Right-clicking the online filter toggles invalid-score visibility.
			-- Right-clicking a local row toggles that score's validation state.
			if isPress and btn == "DeviceButton_right mouse button" then
				if currentView == VIEW_ONLINE and IsMouseOverCentered(SCREEN_CENTER_X - overlayW/2 + 75, SCREEN_CENTER_Y - overlayH/2 + 40, 100, 18) then
					showInvalidScores = not showInvalidScores
					currentPage = 1
					scoresActor:playcommand("RefreshScores")
					return true
				end

				if currentView == VIEW_LOCAL then
					for ri = 1, pageSize do
						local ry = SCREEN_CENTER_Y + rowsStartY + (ri - 1) * rowH + rowH / 2
						if IsMouseOverCentered(SCREEN_CENTER_X, ry, overlayW - 50, rowH) then
							local entry = displayedScores[(currentPage - 1) * pageSize + ri]
							local score = entry and entry.score
							if score and type(score) ~= "table" and type(score.ToggleEtternaValidation) == "function" then
								score:ToggleEtternaValidation()
								HV.WheelData.Reset()
								MESSAGEMAN:Broadcast("HV_WheelScoresChanged")
								ms.ok(score:GetEtternaValid() and "Score validated" or "Score invalidated")
								scoresActor:playcommand("RefreshScores")
								return true
							end
						end
					end
				end
				return true
			end

			if isPress and btn == "DeviceButton_left mouse button" then
				-- Close on outside click
				if not IsMouseOverCentered(SCREEN_CENTER_X, SCREEN_CENTER_Y, overlayW, overlayH) then
					MESSAGEMAN:Broadcast("SelectMusicTabChanged", {Tab = ""})
					return true
				end

				-- Close button
				if IsMouseOverCentered(SCREEN_CENTER_X + overlayW/2 - 16, SCREEN_CENTER_Y - overlayH/2 + 16, 24, 24) then
					MESSAGEMAN:Broadcast("SelectMusicTabChanged", {Tab = ""})
					return true
				end

				-- Mode toggle
				if IsMouseOverCentered(SCREEN_CENTER_X + overlayW/2 - 55, SCREEN_CENTER_Y - overlayH/2 + 18, 100, 18) then
					if currentView == VIEW_LOCAL then
						replayRequestToken = replayRequestToken + 1
						currentView = VIEW_ONLINE
						FetchOnlineScores()
					else
						replayRequestToken = replayRequestToken + 1
						currentView = VIEW_LOCAL
						GetLocalScores()
					end
					currentPage = 1
					scoresActor:playcommand("RefreshScores")
					return true
				end

				-- Rate button
				if IsMouseOverCentered(SCREEN_CENTER_X + overlayW/2 - 145, SCREEN_CENTER_Y - overlayH/2 + 18, 65, 18) then
					filterCurrentRate = not filterCurrentRate
					currentPage = 1
					if currentView == VIEW_LOCAL then
						GetLocalScores()
					end
					scoresActor:playcommand("RefreshScores")
					return true
				end

				-- Invalid score visibility button
				if currentView == VIEW_ONLINE and IsMouseOverCentered(SCREEN_CENTER_X - overlayW/2 + 75, SCREEN_CENTER_Y - overlayH/2 + 40, 100, 18) then
					showInvalidScores = not showInvalidScores
					currentPage = 1
					scoresActor:playcommand("RefreshScores")
					return true
				end

				-- Sort button
				if IsMouseOverCentered(SCREEN_CENTER_X + overlayW/2 - 215, SCREEN_CENTER_Y - overlayH/2 + 18, 65, 18) then
					currentSort = (currentSort == SORT_SSR) and SORT_WIFE or SORT_SSR
					currentPage = 1
					scoresActor:playcommand("RefreshScores")
					return true
				end

				-- J4 Display button
				local normPref = PREFSMAN:GetPreference("SortBySSRNormPercent")
				if not normPref and IsMouseOverCentered(SCREEN_CENTER_X + overlayW/2 - 285, SCREEN_CENTER_Y - overlayH/2 + 18, 65, 18) then
					displayAsJ4 = not displayAsJ4
					currentPage = 1
					scoresActor:playcommand("RefreshScores")
					return true
				end

				-- Row interaction
				local replayX = SCREEN_CENTER_X + 305
				for ri = 1, pageSize do
					local ry = SCREEN_CENTER_Y + rowsStartY + (ri - 1) * rowH + rowH / 2
					
					-- Replay button
					-- Check Replay Button.
					if IsMouseOverCentered(replayX, ry, 35, 30) then
						local idx = (currentPage - 1) * pageSize + ri
						local entry = displayedScores[idx]
						if entry then
							local ss = entry.score
							if currentView == VIEW_LOCAL then
								HV.OnlineReplayActive = false
								HV.OnlineReplayName = nil
								HV.OnlineEvaluationName = nil
								if ss:HasReplayData() then
									SCREENMAN:GetTopScreen():PlayReplay(ss)
								end
							else
								-- Online Replay: Request data first, then play
								requestSelectedOnlineReplay(ss, function(owner)
									HV.OnlineReplayActive = true
									HV.OnlineReplayName = GetScoreDisplayName(ss)
									HV.OnlineEvaluationName = HV.OnlineReplayName
									if not owner:PlayReplay(ss) then
										HV.OnlineReplayActive = false
										HV.OnlineReplayName = nil
										HV.OnlineEvaluationName = nil
									end
								end)
							end
						end
						return true
					end

					-- Check Row Click (View Score)
					if IsMouseOverCentered(SCREEN_CENTER_X, ry, overlayW - 50, rowH) then
						local idx = (currentPage - 1) * pageSize + ri
						local entry = displayedScores[idx]
						if entry then
							local ss = entry.score
							local rowLeft = SCREEN_CENTER_X - overlayW / 2 + 25
							local localX = INPUTFILTER:GetMouseX() - rowLeft
							-- Online name and Wife% cells link to EO. If score metadata
							-- is incomplete, retain the normal evaluation behavior.
							if currentView == VIEW_ONLINE and localX >= 30 and localX < 180 then
								if not OpenOnlinePlayer(ss) and not ShowScoreOffsetPlot(ss) then ms.ok("Replay not available") end
							elseif currentView == VIEW_ONLINE and localX >= 180 and localX < 280 then
								-- GetScoreid is the Etterna online-score API method.
								if not OpenOnlineScore(ss) then ms.ok("Online score page unavailable") end
							else
								if currentView == VIEW_LOCAL then
									ViewScore(ss)
								elseif not ShowScoreOffsetPlot(ss) then
									ms.ok("Replay not available")
								end
							end
						end
						return true
					end
				end
			end

			-- Paging handling
			if isPress then
				if btn == "MenuLeft" or event.button == "Left" or event.DeviceInput.button == "DeviceButton_left" then
					MESSAGEMAN:Broadcast("TabNavigation", {dir = -1})
					return true
				elseif btn == "MenuRight" or event.button == "Right" or event.DeviceInput.button == "DeviceButton_right" then
					MESSAGEMAN:Broadcast("TabNavigation", {dir = 1})
					return true
				end
			end

			if event.button == "Back" or event.DeviceInput.button == "DeviceButton_escape" then
				MESSAGEMAN:Broadcast("SelectMusicTabChanged", {Tab = ""})
				return true
			end

			return true
		end)
	end,
}

return t
