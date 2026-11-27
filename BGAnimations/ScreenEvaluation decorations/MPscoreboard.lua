local song = GAMESTATE:GetCurrentSong()
local steps = GAMESTATE:GetCurrentSteps()
local chartKey = steps and steps:GetChartKey()
local title = song and song:GetDisplayMainTitle() or ""
local artist = song and song:GetDisplayArtist() or ""
local rate = getCurRateValue()

local leftX = SCREEN_LEFT + 10
local rightX = SCREEN_CENTER_X + 10
local panelW = SCREEN_CENTER_X - SCREEN_LEFT - 20
local panelH = SCREEN_HEIGHT - 72
local rowHeight = 36
local pageSize = math.max(1, math.floor((panelH - 76) / rowHeight))
local accent = HVColor.Accent
local muted = color("0.65,0.65,0.65,1")
local white = color("0.95,0.95,0.95,1")
local page, entries = 1, {}
local owner, selected, selectedIndex
local userSelected = false
local needsRefresh = false
local judgmentNames = {"Marvelous", "Perfect", "Great", "Good", "Bad", "Miss"}
local judgmentEnums = {"W1", "W2", "W3", "W4", "W5", "Miss"}

local function topIsActive()
	return owner and SCREENMAN:GetTopScreen() == owner and not owner:IsTransitioning()
end

local function label(name, x, y, zoom, tint, align, width)
	return LoadFont("Common Normal") .. {
		Name = name,
		InitCommand = function(self)
			self:xy(x, y):halign(align or 0):zoom(zoom):diffuse(tint):maxwidth((width or panelW - 24) / zoom)
		end,
	}
end

local function box(x, y, width, height, tint)
	return Def.Quad {
		InitCommand = function(self) self:xy(x, y):halign(0):valign(0):zoomto(width, height):diffuse(tint) end,
	}
end

local function pages()
	return math.max(1, math.ceil(#entries / pageSize))
end

local function showPage(self)
	self:GetChild("Rows"):playcommand("RefreshRows")
	self:GetChild("PageNumber"):settext(string.format("%d / %d", page, pages())):visible(pages() > 1)
	self:GetChild("Prev"):visible(page > 1)
	self:GetChild("Next"):visible(page < pages())
end

local function choose(self, result, reveal)
	selected = result and result.key
	local index = result and result.index
	if song and index and (selectedIndex ~= index or owner:GetCurrentPlayer() ~= index) then
		owner:SetCurrentPlayer(index)
	end
	selectedIndex = index
	self:GetChild("Details"):playcommand("SetResult", result)
	if result and reveal then page = math.ceil(result.rank / pageSize) end
	showPage(self)
end

local function refresh(self)
	if not owner or SCREENMAN:GetTopScreen() ~= owner then return end
	local latest = {}
	for i, item in ipairs(NSMAN:GetEvalScores()) do
		local score = item.highscore
		if item.user ~= "" and score then
			local key = score:GetChartKey()
			local wife = score:GetWifeScore()
			if (not chartKey or key == "" or key == chartKey) and wife == wife and math.abs(wife) < math.huge then
				local taps = {}
				for j, judgment in ipairs(judgmentEnums) do
					taps[j] = score:GetTapNoteScore("TapNoteScore_" .. judgment)
				end
				local user = item.user:lower()
				latest[user] = {
					user = item.user, key = user, index = i, wife = wife, grade = score:GetWifeGrade(),
					combo = score:GetMaxCombo(), taps = taps,
					held = score:GetHoldNoteScore("HoldNoteScore_Held"),
					lost = score:GetHoldNoteScore("HoldNoteScore_LetGo") + score:GetHoldNoteScore("HoldNoteScore_Missed"),
					mines = score:GetTapNoteScore("TapNoteScore_HitMine"),
				}
			end
		end
	end
	entries = {}
	for _, result in pairs(latest) do entries[#entries + 1] = result end
	table.sort(entries, function(a, b)
		if a.wife ~= b.wife then return a.wife > b.wife end
		return a.key < b.key
	end)
	for i, result in ipairs(entries) do result.rank = i end

	local saved = selected and latest[selected]
	local localResult = latest[NSMAN:GetLoggedInUsername():lower()]
	local result = (userSelected and saved) or localResult or saved or entries[1]
	page = math.min(page, pages())
	choose(self, result, result ~= saved)
	self:GetChild("Details"):GetChild("Status"):settext(THEME:GetString("ScreenEvaluation",
		IsNetConnected() and "WaitingForMultiplayerScores" or "DisconnectedMultiplayerScores"))
	needsRefresh = false
end

local function invalidate(self)
	if not owner then return end
	needsRefresh = true
	refresh(self)
end

local function stopRefreshing(self)
	owner, needsRefresh = nil, false
	self:SetUpdateFunction(nil)
end

local function scoreRow(i)
	return Def.ActorFrame {
		Name = "Row" .. i,
		InitCommand = function(self) self:y(38 + (i - 1) * rowHeight):visible(false) end,
		RefreshRowsCommand = function(self)
			local result = entries[(page - 1) * pageSize + i]
			self:visible(result ~= nil)
			if not result then return end
			self:GetChild("Highlight"):diffusealpha(result.key == selected and 0.25 or 0)
			self:GetChild("Rank"):settext(result.rank)
			self:GetChild("User"):settext(result.user)
			self:GetChild("Percent"):settext(HV.Score.FormatEvaluationWifePercent(result.wife * 100))
				:diffuse(HVColor.GetGradeColor(result.grade))
		end,
		box(0, 0, panelW, 32, color("0,0,0,0.4")),
		Def.Quad {
			Name = "Highlight",
			InitCommand = function(self) self:halign(0):valign(0):zoomto(panelW, 32):diffuse(accent):diffusealpha(0) end,
		},
		label("Rank", 8, 16, 0.28, muted, 0, 25),
		label("User", 35, 16, 0.35, white, 0, panelW - 120),
		label("Percent", panelW - 8, 16, 0.33, white, 1, 72),
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self) self:zoomto(panelW, 32):halign(0):valign(0):diffusealpha(0) end,
			MouseDownCommand = function(self, params)
				local result = entries[(page - 1) * pageSize + i]
				if result and topIsActive() and params.event == "DeviceButton_left mouse button" then
					userSelected = true
					choose(self:GetParent():GetParent():GetParent(), result)
				end
			end,
		},
	}
end

local function pageButton(name, text, x, direction)
	return Def.ActorFrame {
		Name = name,
		InitCommand = function(self) self:xy(x, 38 + pageSize * rowHeight + 12):visible(false) end,
		label("Label", 0, 0, 0.32, accent, 0.5, 36) .. {
			InitCommand = function(self) self:zoom(0.32):diffuse(accent):settext(text) end,
		},
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self) self:zoomto(32, 22):diffusealpha(0) end,
			MouseDownCommand = function(self, params)
				local nextPage = page + direction
				if topIsActive() and params.event == "DeviceButton_left mouse button" and nextPage >= 1 and nextPage <= pages() then
					page = nextPage
					showPage(self:GetParent():GetParent())
				end
			end,
		},
	}
end

local details = Def.ActorFrame {
	Name = "Details",
	InitCommand = function(self) self:x(leftX + 12) end,
	SetResultCommand = function(self, result)
		self:GetChild("Status"):visible(result == nil)
	end,
	label("Status", 0, 90, 0.45, muted),
}

local resultPanel = Def.ActorFrame {
	Name = "Result",
	InitCommand = function(self) self:visible(false) end,
	SetResultCommand = function(self, result)
		self:visible(result ~= nil)
		if not result then return end
		local tint = HVColor.GetGradeColor(result.grade)
		self:GetChild("Player"):settext(result.user)
		self:GetChild("Grade"):settext(HV.GetGradeName(result.grade)):diffuse(tint)
		self:GetChild("Percent"):settext(HV.Score.FormatEvaluationWifePercent(result.wife * 100)):diffuse(tint)
		self:GetChild("Combo"):settextf("%dx", result.combo)
		for i, taps in ipairs(result.taps) do self:GetChild("Tap" .. i):settext(taps) end
		self:GetChild("HoldOK"):settext(result.held)
		self:GetChild("HoldNG"):settext(result.lost)
		self:GetChild("MinesHit"):settext(result.mines)
	end,
	label("Player", 0, 95, 0.57, white),
	label("Grade", 0, 131, 0.75, white, 0, panelW * 0.32),
	label("Percent", panelW * 0.36, 131, 0.83, white, 0, panelW * 0.61),
	label("Combo", 0, 162, 0.38, muted),
	label("Judgments", 0, 190, 0.4, white) .. {
		OnCommand = function(self) self:settext(THEME:GetString("ScreenEvaluation", "CategoryJudgment")) end,
	},
}
for i, name in ipairs(judgmentNames) do
	local y = 197 + i * 18
	resultPanel[#resultPanel + 1] = label(name, 0, y, 0.36, muted, 0, panelW / 2 - 27) .. {
		OnCommand = function(self) self:settext(name) end,
	}
	resultPanel[#resultPanel + 1] = label("Tap" .. i, panelW / 2, y, 0.36, white, 1, 45)
end
for i, name in ipairs({"HoldOK", "HoldNG", "MinesHit"}) do
	local x, y = panelW * 0.58, 197 + i * 18
	resultPanel[#resultPanel + 1] = label(name .. "Label", x, y, 0.32, muted, 0, panelW * 0.28) .. {
		OnCommand = function(self) self:settext(THEME:GetString("ScreenEvaluation", name)) end,
	}
	resultPanel[#resultPanel + 1] = label(name, panelW - 24, y, 0.36, white, 1, 42)
end
details[#details + 1] = resultPanel

local rows = Def.ActorFrame {Name = "Rows", InitCommand = function(self) self:x(rightX) end}
for i = 1, pageSize do rows[#rows + 1] = scoreRow(i) end

return Def.ActorFrame {
	Name = "MPScoreBoard",
	InitCommand = function(self) self:y(SCREEN_TOP + 42) end,
	BeginCommand = function(self)
		owner = SCREENMAN:GetTopScreen()
		refresh(self)
		self:SetUpdateFunction(function()
			if needsRefresh then refresh(self) end
		end)
	end,
	OnCommand = function()
		local countPlay = HV.GameplaySessionValid and not HV.IsReplayPlayback()
		HV.GameplaySessionValid = false
		if countPlay and GRADECOUNTERSTORAGE then
			local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats(PLAYER_1)
			local highscore = HV.Score.GetEvaluationOpeningScore(steps, pss, false)
			local normalized = PREFSMAN:GetPreference("SortBySSRNormPercent")
			GRADECOUNTERSTORAGE:incrementSession(normalized and highscore and highscore:GetWifeGrade() or pss:GetWifeGrade())
		end
	end,
	OffCommand = stopRefreshing,
	EndCommand = stopRefreshing,
	NewMultiScoreMessageCommand = invalidate,
	MultiplayerDisconnectionMessageCommand = invalidate,
	box(leftX, 0, panelW, panelH, color("0.05,0.05,0.05,0.93")),
	box(rightX, 0, panelW, panelH, color("0.05,0.05,0.05,0.93")),
	label("Song", leftX + 12, 24, 0.7, white) .. {
		OnCommand = function(self) self:settext(title) end,
	},
	label("Artist", leftX + 12, 48, 0.4, muted) .. {
		OnCommand = function(self) self:settext(artist) end,
	},
	label("Rate", leftX + panelW - 12, 67, 0.35, accent, 1) .. {
		OnCommand = function(self) self:settextf("%.2fx", rate) end,
	},
	label("Title", rightX + 8, 20, 0.5, accent) .. {
		OnCommand = function(self) self:settext(THEME:GetString("ScreenEvaluation", "MultiplayerScores")) end,
	},
	details,
	rows,
	label("PageNumber", rightX + panelW / 2, 38 + pageSize * rowHeight + 12, 0.3, muted, 0.5),
	pageButton("Prev", "<", rightX + panelW / 2 - 42, -1),
	pageButton("Next", ">", rightX + panelW / 2 + 42, 1),
	LoadActor("../_cursor"),
}
