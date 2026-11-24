local getReplayPlotVectors = LoadActor("ReplayPlotVectors.lua")

local plotX = 24
local plotWidth = SCREEN_WIDTH - 2 * plotX
local plotHeight = math.min(SCREEN_HEIGHT * 0.32, SCREEN_WIDTH * 0.3)
local plotY = SCREEN_CENTER_Y - plotHeight / 2
local defaultJudge, plotData

local function displayJudge(score)
	if PREFSMAN:GetPreference("SortBySSRNormPercent") then return 4 end
	return math.max(4, HV.Score.GetPlayedJudge(score) or 4)
end

local function loadPlotData(score)
	if not score then return nil, "No score selected" end
	local chartKey = score:GetChartKey()
	local steps = SONGMAN:GetStepsByChartKey(chartKey)
	local song = SONGMAN:GetSongByChartKey(chartKey)
	if not steps or not song then return nil, "Chart unavailable" end

	local data = getReplayPlotVectors(score)
	local hasHits = data and data.nrv and #data.nrv > 0 and data.dvt and #data.dvt > 0
	local hasMisses = data and data.misses and #data.misses > 0
	if not hasHits and not hasMisses then return nil, "Replay has no timing data" end

	data.width, data.height = plotWidth, plotHeight
	data.steps, data.song = steps, song
	data.lastSecond = steps:GetLastSecond()
	data.scoreKey = score:GetScoreKey()
	data.rate = score:GetMusicRate()
	data.columns = steps:GetNumColumns()
	data.chordCohesion = score:GetChordCohesion()
	data.customWindows = false
	data.judge = displayJudge(score)
	return data
end

local t = Def.ActorFrame {
	BeginCommand = function(self)
		local score = HV.PendingScoreOffsetPlot
		HV.PendingScoreOffsetPlot = nil
		local status
		plotData, status = loadPlotData(score)
		defaultJudge = plotData and plotData.judge
		self:GetChild("Status"):settext(status or ""):visible(status ~= nil)
		self:GetChild("Graph"):visible(plotData ~= nil)
		self:GetChild("PlotJudge"):visible(plotData ~= nil)
		self:GetChild("Summary"):playcommand("ShowScore", {score = score})
		if plotData then self:playcommand("RefreshPlot") end

		local screen = SCREENMAN:GetTopScreen()
		screen:AddInputCallback(function(event)
			if not event or SCREENMAN:GetTopScreen() ~= screen then return false end
			if event.DeviceInput and event.DeviceInput.button == "DeviceButton_right mouse button"
				and event.type == "InputEventType_Release" then
				screen:Cancel()
				return true
			end
			return false
		end)
	end,
	RefreshPlotCommand = function(self)
		self:GetChild("PlotJudge"):settextf("Plot judge J%d", plotData.judge)
		self:GetChild("Graph"):RunCommandsOnChildren(function(child)
			child:playcommand("Update", plotData)
		end)
	end,
	CodeMessageCommand = function(self, params)
		if params.Name == "PlotExit" then
			SCREENMAN:GetTopScreen():Cancel()
		elseif plotData then
			local judge = plotData.judge
			if params.Name == "PrevJudge" then judge = math.max(4, judge - 1)
			elseif params.Name == "NextJudge" then judge = math.min(9, judge + 1)
			elseif params.Name == "ResetJudge" then judge = defaultJudge
			elseif params.Name == "ToggleHands" then
				MESSAGEMAN:Broadcast("OffsetPlotModification", {Name = "ToggleHands"})
			end
			if judge ~= plotData.judge then
				plotData.judge = judge
				self:playcommand("RefreshPlot")
			end
		end
	end,

	Def.Quad {
		InitCommand = function(self)
			self:xy(SCREEN_CENTER_X, SCREEN_CENTER_Y):zoomto(SCREEN_WIDTH, SCREEN_HEIGHT):diffuse(color("0,0,0,0.78"))
		end,
	},
	LoadActor(THEME:GetPathG("", "OffsetGraph"), "ScoreTab") .. {
		Name = "Graph",
		InitCommand = function(self) self:xy(plotX, plotY):visible(false) end,
	},
	LoadFont("Common Normal") .. {
		Name = "Status",
		InitCommand = function(self) self:xy(SCREEN_CENTER_X, SCREEN_CENTER_Y):zoom(0.5):visible(false) end,
	},
	LoadFont("Common Normal") .. {
		Name = "PlotJudge",
		InitCommand = function(self) self:halign(0):xy(plotX, plotY - 22):zoom(0.45):visible(false) end,
	},
	LoadFont("Common Normal") .. {
		Name = "Summary",
		InitCommand = function(self) self:halign(0):xy(plotX, plotY - 72):zoom(0.46):visible(false) end,
		ShowScoreCommand = function(self, params)
			local score = params.score
			self:visible(score ~= nil)
			if not score then return end
			local percent, grade = score:GetWifeScore() * 100, score:GetWifeGrade()
			local normalized = PREFSMAN:GetPreference("SortBySSRNormPercent")
			local playedJudge = HV.Score.GetPlayedJudge(score) or 4
			local rescoreToJ4 = not normalized and playedJudge < 4
			if rescoreToJ4 then
				local rescored, available = getJ4NormalizedPercentage(score)
				percent = available and rescored or nil
				if percent and grade ~= "Grade_Failed" then grade = GetGradeFromPercent(percent / 100) end
			end
			local wifeText = percent and HV.Score.FormatEvaluationWifePercent(percent) or "-"
			local gradeText = percent and HV.GetGradeName(ToEnumShortString(grade)) or "-"
			local counts = HV.Score.GetDisplayJudgments(score, (normalized or rescoreToJ4) and 4 or nil)
			local tally = "-"
			if counts then
				tally = string.format("Marv %d   Perf %d   Great %d   Good %d   Bad %d   Miss %d",
					counts.W1, counts.W2, counts.W3, counts.W4, counts.W5, counts.Miss)
			end
			self:settextf("Score %s   %s   %.2f SSR   %.2fx\n%s",
				wifeText, gradeText, score:GetSkillsetSSR("Overall"), score:GetMusicRate(), tally)
		end,
	},
}
return t
