-- Holographic Void: Online Leaderboard (ported from spawncamping-wallhack)
-- Displays EtternaOnline chart leaderboard with Local/Online toggle.
-- Current Rate: same-rate only, sorted by Wife%.
-- All Rates: all rates, sorted by SSR.
-- maybe merge this with MPscoreboard.lua?

local selectEvaluationScore, score = ...
local steps = GAMESTATE:GetCurrentSteps()
local chartKey = steps and steps:GetChartKey()
local viewedRate = score and score:GetMusicRate() or getCurRateValue()
local accentColor = HVColor.Accent
local brightText = color("1,1,1,1")
local dimText = brightText
local subText = brightText
local mainText = brightText
local selectedScoreKey = score and score:GetScoreKey()

local owner, lbActor
local isLocal = true
local allLocalRates, allOnlineRates = false, false
local localScores, onlineScores = {}, nil
local leaderboardState = "idle"
local replayRequest = 0
local leaderboardRequest = 0
local scoresPerPage = 4
local maxPages, curPage = 1, 1
local scoreList = {}
local showInvalidScores = false

local function showAllRates()
	if isLocal then return allLocalRates end
	return allOnlineRates
end

local function isOnlineScoreInvalid(score)
	return not score:GetEtternaValid() or score:GetChordCohesion()
end

local function getJudge(score)
	local scale = (score and type(score.GetJudgeScale) == "function") and score:GetJudgeScale() or 1.0
	if not scale then return "J4" end
	scale = math.floor(scale * 100 + 0.5) / 100
	for k, v in pairs(ms.JudgeScalers) do
		if math.floor(v * 100 + 0.5) / 100 == scale then
			return "J" .. math.max(4, k)
		end
	end
	return "J4"
end

local function refreshScores(preferredKey)
	scoreList = HV.Score.BuildEvaluationLeaderboard(
		isLocal and localScores or (onlineScores or {}), viewedRate, showAllRates(),
		not isLocal, showInvalidScores
	)
	maxPages = math.max(1, math.ceil(#scoreList / scoresPerPage))
	curPage = 1
	if preferredKey then
		for i, entry in ipairs(scoreList) do
			if entry.key == preferredKey then
				curPage = math.ceil(i / scoresPerPage)
				break
			end
		end
	end
	if lbActor then lbActor:playcommand("RefreshUI") end
end

local function movePage(n)
	if maxPages <= 1 then return false end
	curPage = ((curPage + n - 1) % maxPages) + 1
	MESSAGEMAN:Broadcast("UpdateOnlineList")
	return true
end

local function getHoveredRow(self)
	for i = 1, scoresPerPage do
		local row = self:GetChild("OnlineRow" .. i)
		local bg = row and row:GetChild("RowBackground")
		if row and row:IsVisible() and bg and isOver(bg) then
			return scoreList[(curPage - 1) * scoresPerPage + i]
		end
	end
end

local function isCurrentRequest(screen)
	return lbActor and owner == screen and SCREENMAN:GetTopScreen() == screen
		and not screen:IsTransitioning() and not isLocal
end

local function selectRow(entry)
	if not entry then return false end
	if not selectEvaluationScore(entry.score, not isLocal) then return false end
	replayRequest = replayRequest + 1
	if not isLocal and entry.score:HasReplayData() then
		local token, screen = replayRequest, owner
		DLMAN:RequestOnlineScoreReplayData(entry.score, function(replayScore)
			if not isCurrentRequest(screen) or token ~= replayRequest or selectedScoreKey ~= entry.key then return end
			if replayScore and replayScore:GetChartKey() == chartKey and replayScore:GetScoreKey() == entry.key then
				selectEvaluationScore(replayScore, true, true)
			end
		end)
	end
	return true
end

local function loadOnlineScores()
	if leaderboardState == "loading" or leaderboardState == "ready" or not chartKey then return end
	leaderboardState = "loading"
	leaderboardRequest = leaderboardRequest + 1
	local token, screen = leaderboardRequest, owner
	lbActor:GetChild("LeaderboardRequestTimer"):stoptweening():sleep(12):queuecommand("Expire")
	DLMAN:RequestChartLeaderBoardFromOnline(chartKey, function(scores)
		if token ~= leaderboardRequest or not lbActor or owner ~= screen
			or SCREENMAN:GetTopScreen() ~= screen or screen:IsTransitioning() then return end
		lbActor:GetChild("LeaderboardRequestTimer"):stoptweening()
		onlineScores = scores
		leaderboardState = type(scores) == "table" and "ready" or "unavailable"
		if not isLocal then refreshScores(selectedScoreKey) end
	end)
end

local function setAllRates(allRates)
	if isLocal then allLocalRates = allRates else allOnlineRates = allRates end
	refreshScores(selectedScoreKey)
end

local function scoreItem(i)
	return Def.ActorFrame {
		Name = "OnlineRow" .. i,
		InitCommand = function(self) self:y((i - 1) * 46):diffusealpha(0) end,
		OnCommand = function(self) self:playcommand("UpdateRow") end,
		UpdateOnlineListMessageCommand = function(self) self:playcommand("UpdateRow") end,
		RefreshOnlineScoreboardMessageCommand = function(self) self:playcommand("UpdateRow") end,
		UpdateRowCommand = function(self)
			local idx = (curPage - 1) * scoresPerPage + i
			if scoreList and scoreList[idx] then
				self:visible(true)
				self:stoptweening():diffusealpha(0):sleep(i * 0.05):linear(0.15):diffusealpha(1)
				self:RunCommandsOnChildren(function(child) child:playcommand("SetScore", {index = idx}) end)
			else
				self:visible(false)
			end
		end,

		-- Row BG
		Def.Quad {
			Name = "RowBackground",
			InitCommand = function(self)
				self:halign(0):valign(0):zoomto(SCREEN_CENTER_X - 40, 42):diffuse(color("0,0,0,0.4"))
			end,
			SetScoreCommand = function(self, params)
				local s = scoreList[params.index].score
				if not isLocal and isOnlineScoreInvalid(s) then
					self:diffuse(color("#7A1018"))
				elseif scoreList[params.index].key == selectedScoreKey then
					self:diffuse({accentColor[1], accentColor[2], accentColor[3], 0.26})
				else
					self:diffuse(color("0,0,0,0.4"))
				end
			end,
		},

		-- Rank #
		LoadFont("Common Normal") .. {
			InitCommand = function(self) self:xy(10, 21):zoom(0.45):diffuse(accentColor):halign(0) end,
			SetScoreCommand = function(self, params)
				self:settext(params.index)
			end
		},

		-- Clear type
		LoadFont("Common Normal") .. {
			InitCommand = function(self) self:xy(220, 8):zoom(0.32):halign(0):diffuse(subText) end,
			SetScoreCommand = function(self, params)
				local s = scoreList[params.index].score
				local ct = (not isLocal and isOnlineScoreInvalid(s)) and "Invalid" or getDetailedClearType(s)
				self:settext(ct):diffuse(HVColor.GetClearTypeColor(ct))
			end
		},

		-- Player name (online only) or date (local + optional judge)
		LoadFont("Common Normal") .. {
			InitCommand = function(self) self:xy(40, 8):zoom(0.4):halign(0):diffuse(brightText) end,
			SetScoreCommand = function(self, params)
				local s = scoreList[params.index].score
				if isLocal then
					local judgeStr = ""
					if not PREFSMAN:GetPreference("SortBySSRNormPercent") then
						judgeStr = " (" .. getJudge(s) .. ")"
					end
					self:settext(s:GetDate() .. judgeStr)
				else
					local name = s:GetDisplayName()
					if name and name ~= "" then
						self:settext(name)
					else
						self:settext("Unknown")
					end
				end
			end
		},

		-- Grade
		LoadFont("Common Normal") .. {
			InitCommand = function(self) self:xy(40, 26):zoom(0.5):halign(0) end,
			SetScoreCommand = function(self, params)
				local s = scoreList[params.index].score
				local grade = s:GetWifeGrade()
				self:settext(HV.GetGradeName(ToEnumShortString(grade)))
				self:diffuse(HVColor.GetGradeColor(ToEnumShortString(grade)))
			end
		},

		-- Score %
		LoadFont("Common Normal") .. {
			InitCommand = function(self) self:xy(90, 26):zoom(0.5):halign(0):diffuse(mainText) end,
			SetScoreCommand = function(self, params)
				local ws = scoreList[params.index].wife
				self:settext(HV.Score.FormatEvaluationWifePercent(ws * 100))
			end
		},

		-- SSR
		LoadFont("Common Normal") .. {
			InitCommand = function(self) self:xy(SCREEN_CENTER_X - 50, 8):zoom(0.55):halign(1) end,
			SetScoreCommand = function(self, params)
				if not HV.ShowMSD() then
					self:settext("")
					return
				end
				local ssr = scoreList[params.index].ssr
				if ssr > 0 then
					self:settextf("%.2f", ssr)
					self:diffuse(HVColor.GetMSDRatingColor(ssr))
				else
					self:settext(""):diffuse(dimText)
				end
			end
		},

		-- Judgment tally (no labels)
		LoadFont("Common Normal") .. {
			InitCommand = function(self) self:xy(SCREEN_CENTER_X - 50, 26):zoom(0.35):halign(1):diffuse(subText) end,
			SetScoreCommand = function(self, params)
				local s = scoreList[params.index].score
				self:settext(HV.GetRidiculousTallyString(s))
			end
		},

		-- Rate Display (only for All Rates)
		LoadFont("Common Normal") .. {
			InitCommand = function(self) self:xy(135, 24):zoom(0.3):halign(0):diffuse(mainText) end,
			SetScoreCommand = function(self, params)
				if showAllRates() then
					local s = scoreList[params.index].score
					self:settextf("%.2fx", s:GetMusicRate()):visible(true)
				else
					self:visible(false)
				end
			end
		},

	}
end

local t = Def.ActorFrame {
	Name = "OnlineLeaderboard",
	InitCommand = function(self) self:diffusealpha(0) end,
	OnCommand = function(self)
		lbActor, owner = self, SCREENMAN:GetTopScreen()
		self:sleep(0.6):linear(0.2):diffusealpha(1)
		if chartKey then
			for _, bucket in pairs(SCOREMAN:GetScoresByKey(chartKey) or {}) do
				for _, localScore in ipairs(bucket:GetScores()) do
					localScores[#localScores + 1] = localScore
				end
			end
		end
		refreshScores(selectedScoreKey)
		owner:AddInputCallback(function(event)
			if SCREENMAN:GetTopScreen() ~= owner or not self:IsVisible() or not event.DeviceInput
				or event.type ~= "InputEventType_FirstPress" then return false end
			local button = event.DeviceInput.button
			if event.button == "MenuLeft" or button == "DeviceButton_left" or event.button == "Left" then return movePage(-1) end
			if event.button == "MenuRight" or button == "DeviceButton_right" or event.button == "Right" then return movePage(1) end
			if button == "DeviceButton_mousewheel up" or button == "DeviceButton_mousewheel down" then
				return getHoveredRow(self) and movePage(button == "DeviceButton_mousewheel up" and -1 or 1) or false
			end
			if button == "DeviceButton_left mouse button" then
				if selectRow(getHoveredRow(self)) then return true end
				for _, tab in ipairs({"LocalTab", "OnlineTab", "CurrentRateTab", "AllRatesTab", "InvalidToggle"}) do
					local target = self:GetChild(tab)
					if target:IsVisible() and isOver(target) then
						target:playcommand("MouseDown")
						return true
					end
				end
			end
			return false
		end)
	end,
	OffCommand = function(self)
		lbActor, owner = nil, nil
		replayRequest = replayRequest + 1
		leaderboardRequest = leaderboardRequest + 1
	end,
	ScoreChangedMessageCommand = function(self, params)
		selectedScoreKey = params.score:GetScoreKey()
		self:playcommand("RefreshUI")
	end,
	Def.Actor {
		Name = "LeaderboardRequestTimer",
		ExpireCommand = function()
			if leaderboardState ~= "loading" then return end
			leaderboardRequest = leaderboardRequest + 1
			leaderboardState = "unavailable"
			if not isLocal then refreshScores() end
		end,
	},
	RefreshUICommand = function(self)
		MESSAGEMAN:Broadcast("RefreshOnlineScoreboard")
	end,

	-- ============================================================
	-- TAB BUTTONS: Local / Online
	-- ============================================================
	Def.Quad {
		Name = "LocalTab",
		InitCommand = function(self)
			self:xy(0, -38):zoomto(60, 16):halign(0):valign(0)
			self:diffuse(accentColor):diffusealpha(isLocal and 0.4 or 0.1)
		end,
		RefreshOnlineScoreboardMessageCommand = function(self)
			self:diffusealpha(isLocal and 0.4 or 0.1)
		end,
		MouseDownCommand = function(self)
			if isOver(self) and not isLocal then
				isLocal = true
				replayRequest = replayRequest + 1
				refreshScores(selectedScoreKey)
			end
		end
	},
	LoadFont("Common Normal") .. {
		InitCommand = function(self) self:xy(30, -30):zoom(0.32):diffuse(brightText):settext("Local") end
	},

	Def.Quad {
		Name = "OnlineTab",
		InitCommand = function(self)
			self:xy(64, -38):zoomto(60, 16):halign(0):valign(0)
			self:diffuse(accentColor):diffusealpha(not isLocal and 0.4 or 0.1)
		end,
		RefreshOnlineScoreboardMessageCommand = function(self)
			self:diffusealpha(not isLocal and 0.4 or 0.1)
		end,
		MouseDownCommand = function(self)
			if isOver(self) and DLMAN:IsLoggedIn() and chartKey then
				isLocal = false
				loadOnlineScores()
				refreshScores(selectedScoreKey)
			end
		end
	},
	LoadFont("Common Normal") .. {
		InitCommand = function(self) self:xy(94, -30):zoom(0.32):diffuse(brightText):settext("Online") end
	},

	-- ============================================================
	-- RATE FILTER: Current / All
	-- ============================================================
	Def.Quad {
		Name = "CurrentRateTab",
		InitCommand = function(self)
			self:xy(160, -38):zoomto(70, 16):halign(0):valign(0)
			self:diffuse(color("#555555"))
		end,
		RefreshOnlineScoreboardMessageCommand = function(self)
			self:diffusealpha(not showAllRates() and 0.4 or 0.1)
		end,
		MouseDownCommand = function(self) setAllRates(false) end,
	},
	LoadFont("Common Normal") .. {
		InitCommand = function(self) self:xy(195, -30):zoom(0.3):diffuse(brightText):settext("Current") end
	},

	Def.Quad {
		Name = "AllRatesTab",
		InitCommand = function(self)
			self:xy(234, -38):zoomto(60, 16):halign(0):valign(0)
			self:diffuse(color("#555555"))
		end,
		RefreshOnlineScoreboardMessageCommand = function(self)
			self:diffusealpha(showAllRates() and 0.4 or 0.1)
		end,
		MouseDownCommand = function(self) setAllRates(true) end,
	},
	LoadFont("Common Normal") .. {
		InitCommand = function(self) self:xy(264, -30):zoom(0.3):diffuse(brightText):settext("All") end
	},

	-- Invalid score visibility
	Def.Quad {
		Name = "InvalidToggle",
		InitCommand = function(self)
			self:xy(305, -38):zoomto(92, 16):halign(0):valign(0):diffuse(color("#B01824"))
			self:diffusealpha(0)
		end,
		RefreshOnlineScoreboardMessageCommand = function(self)
			self:visible(not isLocal):diffusealpha(showInvalidScores and 0.65 or 0.2)
		end,
		MouseDownCommand = function(self)
			if isOver(self) and not isLocal then
				showInvalidScores = not showInvalidScores
				refreshScores(selectedScoreKey)
			end
		end
	},
	LoadFont("Common Normal") .. {
		InitCommand = function(self) self:xy(351, -30):zoom(0.28):diffuse(brightText) end,
		RefreshOnlineScoreboardMessageCommand = function(self)
			self:visible(not isLocal):settext(showInvalidScores and "Invalid ON" or "Invalid OFF")
		end
	},

	-- Page info
	LoadFont("Common Normal") .. {
		Name = "PageInfo",
		InitCommand = function(self) self:xy(150, scoresPerPage * 46 + 8):zoom(0.28):diffuse(dimText) end,
		OnCommand = function(self) self:playcommand("UpdateText") end,
		UpdateOnlineListMessageCommand = function(self) self:playcommand("UpdateText") end,
		RefreshOnlineScoreboardMessageCommand = function(self) self:playcommand("UpdateText") end,
		UpdateTextCommand = function(self)
			if scoreList and #scoreList > 0 then
				local src = isLocal and "Local" or "Online"
				local rateLabel = showAllRates() and "All Rates" or "Current Rate"
				self:settextf("%s (%s) - Page %d/%d - %d scores", src, rateLabel, curPage, maxPages, #scoreList)
			elseif not isLocal and leaderboardState == "loading" then
				self:settext("Loading scores…")
			elseif not isLocal and leaderboardState == "unavailable" then
				self:settext("Leaderboard unavailable")
			else
				self:settext("No scores")
			end
		end
	},
}

for i = 1, scoresPerPage do
	t[#t + 1] = scoreItem(i)
end

return t
