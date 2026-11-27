local selection, panelX, panelW, pbY = ...
local accentColor = HVColor.Accent
local dimText = color("0.45,0.45,0.45,1")
local subText = color("0.65,0.65,0.65,1")
local mainText = color("0.85,0.85,0.85,1")
local brightText = color("1,1,1,1")

local function getPBView(frame)
	local score = selection.pbScore
	if not score then return end
	local normalized = PREFSMAN:GetPreference("SortBySSRNormPercent")
	local j4 = normalized or frame.isHovering
	local cached = frame.pbView
	if cached and cached.score == score and cached.j4 == j4 then return cached end

	local playedJudge = HV.Score.GetPlayedJudge(score)
	local stats = {
		score = score,
		j4 = j4,
		judge = j4 and 4 or playedJudge,
		wife = score:GetWifeScore() * 100,
		grade = score:GetWifeGrade(),
	}
	if j4 then
		local percent, available = getJ4NormalizedPercentage(score)
		stats.wife = available and percent or nil
		if stats.grade ~= "Grade_Failed" then
			stats.grade = stats.wife and GetGradeFromPercent(stats.wife / 100)
		end
	end
	stats.counts = HV.Score.GetDisplayJudgments(score, stats.judge)
	if stats.counts then stats.clear = getDetailedClearType(score, stats.counts) end
	frame.pbView = stats
	return stats
end

local pbJudgments = {
	{"W1", "MARV"}, {"W2", "PERF"}, {"W3", "GREAT"},
	{"W4", "GOOD"}, {"W5", "BAD"}, {"Miss", "MISS"},
}

local function getHoveredScore(frame)
	local screen = frame.reviewScreen
	if not screen or SCREENMAN:GetTopScreen() ~= screen or screen:IsTransitioning()
		or HV.ChartPreviewActive or (HV.ActiveTab or "") ~= "" then return end
	if not selection.detailsReady or not selection.song or not selection.steps
		or selection.song ~= GAMESTATE:GetCurrentSong() or selection.steps ~= GAMESTATE:GetCurrentSteps()
		or selection.rate ~= getCurRateValue() then return end
	local label = frame:GetChild("PBScore")
	local score = label.displayedScore
	if not score or score ~= selection.pbScore or not isOver(label) then return end
	local wheel = screen:GetMusicWheel()
	if screen:GetSelectionState() == 0 and wheel and wheel:IsSettled() then return score end
end

return Def.ActorFrame {
	Name = "PersonalBestFrame",
	InitCommand = function(self)
		self.isHovering = false
	end,
	BeginCommand = function(self)
		local screen = SCREENMAN:GetTopScreen()
		if self.reviewScreen or not screen or screen:GetName() ~= "ScreenSelectMusic" then return end
		self.reviewScreen = screen
		self.reviewInput = function(event)
			local device = event and event.DeviceInput
			if not device or not IsMouseLeftClick(device.button) or event.type ~= "InputEventType_FirstPress" then
				return false
			end
			local score = getHoveredScore(self)
			if not score then return false end
			HV.Score.OpenLocalEvaluation(screen, score)
			return true
		end
		screen:AddInputCallback(self.reviewInput)
	end,
	OnCommand = function(self)
		self:queuecommand("Tick")
	end,
	OffCommand = function(self)
		if self.reviewScreen then self.reviewScreen:RemoveInputCallback(self.reviewInput) end
		self.reviewScreen, self.reviewInput = nil, nil
		self:stoptweening()
	end,
	InstantChartUpdateMessageCommand = function(self)
		local show = selection.detailsReady == true and selection.song ~= nil
		self:playcommand("SetSongDetailsVisible", {show = show})
	end,
	HV_SelectionDetailsReadyMessageCommand = function(self)
		self.pbView = nil
		self:playcommand("SetSongDetailsVisible", {show = selection.song ~= nil})
	end,
	SetSongDetailsVisibleCommand = function(self, params)
		for _, name in ipairs({"PBHeader", "PBDate", "PBScoringSystem", "PBRate", "PBScore", "PBGrade", "PBClearType", "PBSSR", "PBCC", "PBJudgesFrame"}) do
			local child = self:GetChild(name)
			if child and (not params.show or (name ~= "PBCC" and name ~= "PBJudgesFrame")) then
				child:visible(params.show)
			end
		end
	end,
	TickCommand = function(self)
		local mx, my = INPUTFILTER:GetMouseX(), INPUTFILTER:GetMouseY()
		local isH = mx >= (panelX + 10) and mx <= (panelX + panelW - 22) and my >= (pbY - 4) and my <= (pbY + 110)
		if isH ~= self.isHovering then
			self.isHovering = isH
			self:playcommand("Set")
		end
		local label = self:GetChild("PBScore")
		local canReview = getHoveredScore(self) ~= nil
		if canReview ~= label.reviewHovered then
			label.reviewHovered = canReview
			label:diffuse(canReview and accentColor or (label.displayedScore and brightText or dimText))
		end
		self:sleep(0.05):queuecommand("Tick")
	end,

	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0):y(-4)
				:zoomto(panelW - 32, 1)
				:diffuse(color("0.12,0.12,0.12,1"))
		end
	},

	LoadFont("Common Normal") .. {
		Name = "PBHeader",
		InitCommand = function(self)
			self:halign(0):valign(0):y(2):zoom(0.28):diffuse(accentColor)
		end,
		OnCommand = function(self)
			self:playcommand("Set")
		end,
		SetCommand = function(self)
			local view = getPBView(self:GetParent())
			local title = THEME:GetString("ScreenSelectMusic", "PersonalBest")
			self:settext(view and view.j4 and title .. " (J4)" or title):diffuse(accentColor)
		end,
		HV_SelectionDetailsReadyMessageCommand = function(self) self:playcommand("Set") end,
	},

	LoadFont("Common Normal") .. {
		Name = "PBDate",
		InitCommand = function(self)
			self:halign(1):valign(0):x(panelW - 32):y(2):zoom(0.24):diffuse(subText)
		end,
		SetCommand = function(self)
			local score = selection.pbScore
			if score then
				self:settext(score:GetDate())
			else
				self:settext("")
			end
		end,
		HV_SelectionDetailsReadyMessageCommand = function(self) self:playcommand("Set") end,
	},

	LoadFont("Common Normal") .. {
		Name = "PBScoringSystem",
		InitCommand = function(self)
			self:halign(0):valign(0):y(14):zoom(0.35):diffuse(subText)
		end,
	SetCommand = function(self)
			local view = getPBView(self:GetParent())
			self:settext(view and (view.judge and string.format("Wife3 J%d", view.judge) or "Wife3") or "")
		end,
		HV_SelectionDetailsReadyMessageCommand = function(self) self:playcommand("Set") end,
	},

	LoadFont("Common Normal") .. {
		Name = "PBRate",
		InitCommand = function(self)
			self:halign(1):valign(0):x(panelW - 32):y(14):zoom(0.35):diffuse(mainText)
		end,
		SetCommand = function(self)
			local score = selection.pbScore
			self:settext(score and getRate(score) or "")
		end,
		HV_SelectionDetailsReadyMessageCommand = function(self) self:playcommand("Set") end,
	},

	LoadFont("Common Large") .. {
		Name = "PBScore",
		InitCommand = function(self)
			self:halign(0):valign(0):y(28):zoom(0.5):diffuse(brightText)
		end,
		SetCommand = function(self)
			local view = getPBView(self:GetParent())
			self.displayedScore = view and view.score
			if view then
				self:settext(view.wife and HV.Score.FormatEvaluationWifePercent(view.wife) or "-")
					:diffuse(self.reviewHovered and accentColor or brightText)
			else
				self:settext(THEME:GetString("ScreenSelectMusic", "NoScore")):diffuse(dimText)
			end
		end,
		HV_SelectionDetailsReadyMessageCommand = function(self) self:playcommand("Set") end,
	},

	LoadFont("Common Large") .. {
		Name = "PBGrade",
		InitCommand = function(self)
			self:halign(0):valign(0):x(115):y(28):zoom(0.5)
		end,
		SetCommand = function(self)
			local view = getPBView(self:GetParent())
			local grade = view and view.grade
			self:settext(grade and HV.GetGradeName(grade) or (view and "-" or ""))
				:diffuse(grade and HVColor.GetGradeColor(grade) or dimText)
		end,
		HV_SelectionDetailsReadyMessageCommand = function(self) self:playcommand("Set") end,
	},

	LoadFont("Common Large") .. {
		Name = "PBClearType",
		InitCommand = function(self)
			self:halign(1):valign(0):x(panelW - 32):y(28):zoom(0.4)
		end,
		SetCommand = function(self)
			local view = getPBView(self:GetParent())
			local clear = view and view.clear
			self:settext(clear and THEME:GetString("ClearTypes", clear) or (view and "-" or ""))
				:diffuse(clear and HVColor.GetClearTypeColor(clear) or dimText)
		end,
		HV_SelectionDetailsReadyMessageCommand = function(self) self:playcommand("Set") end,
	},

	LoadFont("Common Normal") .. {
		Name = "PBSSR",
		InitCommand = function(self)
			self:halign(0):valign(0):y(52):zoom(0.40):diffuse(mainText)
		end,
		SetCommand = function(self)
			local ssr = selection.pbSSR
			if ssr and ssr > 0 then
				self:settext(string.format("%.2f", ssr))
				self:diffuse(HVColor.GetMSDRatingColor(ssr))
			else
				self:settext("")
			end
		end,
		HV_SelectionDetailsReadyMessageCommand = function(self) self:playcommand("Set") end,
	},

	LoadFont("Common Normal") .. {
		Name = "PBCC",
		InitCommand = function(self) self:halign(0):valign(0):x(60):y(52):zoom(0.30):diffuse(color("#FF0000")):settext("Chord Cohesion ON"):visible(false) end,
		SetCommand = function(self)
			local score = selection.pbScore
			if score and score:GetChordCohesion() then
				self:settext("Chord Cohesion ON")
				self:visible(true)
			else
				self:settext("")
				self:visible(false)
			end
		end,
		HV_SelectionDetailsReadyMessageCommand = function(self) self:playcommand("Set") end,
	},

	Def.ActorFrame {
		Name = "PBJudgesFrame",
		InitCommand = function(self)
			self:y(68)
		end,
		SetCommand = function(self)
			local view = getPBView(self:GetParent())
			self:visible(view ~= nil)
			if not view then return end

			local blocks = self:GetChild("Blocks")
			for i, entry in ipairs(pbJudgments) do
				local key, label = entry[1], entry[2]
				local block = blocks:GetChild("Block_" .. i)
				local tint = HVColor.GetJudgmentColor(key)
				local count = view.counts and view.counts[key]
				block:GetChild("Bg"):diffuse(tint):diffusealpha(0.2)
				block:GetChild("Lbl"):settext(label):diffuse(tint):zoom(0.2)
				block:GetChild("Val"):settext(count or "-"):diffuse(tint):zoom(0.45)
			end
		end,
		HV_SelectionDetailsReadyMessageCommand = function(self) self:playcommand("Set") end,
		(function()
			local blocks = Def.ActorFrame{ Name = "Blocks" }
			local numBlocks = #pbJudgments
			local gap = 2
			local blockW = (panelW - 32 - (gap * (numBlocks - 1))) / numBlocks

			for i = 1, numBlocks do
				blocks[#blocks + 1] = Def.ActorFrame {
					Name = "Block_" .. i,
					InitCommand = function(self)
						self:x((i - 1) * (blockW + gap))
					end,
					Def.Quad {
						Name = "Bg",
						InitCommand = function(self)
							self:halign(0):valign(0):zoomto(blockW, 22)
						end
					},
					LoadFont("Common Normal") .. {
						Name = "Val",
						InitCommand = function(self)
							self:halign(0.5):valign(0):xy(blockW/2, 2):zoom(0.30)
						end
					},
					LoadFont("Common Normal") .. {
						Name = "Lbl",
						InitCommand = function(self)
							self:halign(0.5):valign(0):xy(blockW/2, 13):zoom(0.20)
						end
					}
				}
			end
			return blocks
		end)()
	},
}
