local wheelItemW = 280
local neutral = color("0.65,0.65,0.65,1")
local dim = color("0.45,0.45,0.45,1")
local accentOff = color("0.15,0.15,0.15,1")

local function matchingChart(song, selected)
	if song == GAMESTATE:GetCurrentSong() then return selected end
	local stepsType, difficulty = selected:GetStepsType(), selected:GetDifficulty()
	local filtered = FILTERMAN:AnyActiveFilter()
	local charts = filtered and song:GetChartsMatchingFilter() or song:GetStepsByStepsType(stepsType)
	local best, bestKey
	for _, chart in ipairs(charts) do
		if chart:GetDifficulty() == difficulty and chart:GetStepsType() == stepsType then
			local key = chart:GetChartKey()
			if not bestKey or key < bestKey then best, bestKey = chart, key end
		end
	end
	return best
end

local function updateRating(self)
	local rating = self:GetChild("MSDDisplay")
	local chart = self.chart
	if not chart then
		rating:settext("")
	elseif HV.ShowMSD() then
		local msd = chart:GetMSD(getCurRateValue(), 1)
		if msd > 0 then
			rating:settextf("%.2f", msd):diffuse(HVColor.GetMSDRatingColor(msd))
		else
			rating:settext("-"):diffuse(dim)
		end
	else
		rating:settext(tostring(chart:GetMeter())):diffuse(neutral)
	end
end

local function updateGrade(self)
	local grade = self.chart and HV.WheelData.GetChartGrade(self:GetParent():GetParent(), self.chart)
	local label = self:GetChild("GradeDisplay")
	label:settext(grade and HV.GetGradeName(grade) or "")
	if grade then label:diffuse(HVColor.GetGradeColor(grade)) end
end

local function updateMirror(self)
	self:GetChild("PermamirrorIndicator"):visible(self.chart ~= nil and self.chart:IsPermaMirror())
end

local function updateFavorite(self)
	self:GetChild("FavoriteStar"):visible(self.song ~= nil and self.song:IsFavorited())
end

local function updateChart(self)
	if not self.song then return end
	local current = GAMESTATE:GetCurrentSteps()
	self.chart = current and matchingChart(self.song, current)
	local accent = current and HVColor.GetDifficultyColor(ToEnumShortString(current:GetDifficulty()))
	self:GetChild("DifficultyAccent"):diffuse(accent or accentOff):diffusealpha(accent and 0.6 or 1)
	updateRating(self)
	updateGrade(self)
	updateMirror(self)
end

local function updateTitleColor(self)
	local name = self.rowType == "Song" and "SongName" or self.rowType
	if not name or name == "SectionExpanded" or name == "SectionCollapsed" then return end
	local title = self:GetParent():GetChild(name)
	if not title then return end
	title:diffuse(HVColor.Accent)
	if title.maxwidth then title:maxwidth(wheelItemW * 0.8 / title:GetZoom()) end
end

return Def.ActorFrame {
	SetMessageCommand = function(self, params)
		local song = params and params.Song
		self.rowType = params and params.Type
		updateTitleColor(self)
		if not song then
			self.song, self.chart = nil, nil
			return
		end
		self.song = song
		self:GetChild("ArtistSubtitle"):settext(song:GetDisplayArtist() or "")
		updateFavorite(self)
		updateChart(self)
	end,
	CurrentStepsChangedMessageCommand = updateChart,
	CurrentRateChangedMessageCommand = function(self)
		if self.song then
			if FILTERMAN:AnyActiveFilter() then updateChart(self) else updateRating(self) end
		end
	end,
	HV_WheelScoresChangedMessageCommand = function(self)
		if self.song then updateGrade(self) end
	end,
	FavoritesUpdatedMessageCommand = updateFavorite,
	FavoriteSongToggledMessageCommand = updateFavorite,
	PermamirrorUpdatedMessageCommand = updateMirror,
	ColorThemeChangedMessageCommand = function(self)
		updateTitleColor(self)
		updateChart(self)
	end,

	Def.Quad {
		Name = "BgQuad",
		InitCommand = function(self)
			self:zoomto(wheelItemW, 38):diffuse(color("0.03,0.03,0.03,1"))
		end,
	},
	Def.Quad {
		Name = "DifficultyAccent",
		InitCommand = function(self)
			self:x(-wheelItemW/2 + 1):zoomto(2, 30):diffuse(accentOff)
		end,
	},
	Def.Sprite {
		Name = "FavoriteStar",
		Texture = THEME:GetPathG("", "round_star"),
		InitCommand = function(self)
			self:x(wheelItemW/2 - 35):y(7):zoomto(10, 10):diffuse(HVColor.Accent):visible(false)
		end,
	},
	LoadFont("Common Normal") .. {
		Name = "MSDDisplay",
		InitCommand = function(self)
			self:halign(1):x(wheelItemW/2 - 6):y(-6):zoom(0.40):diffuse(neutral)
		end,
	},
	LoadFont("Common Normal") .. {
		Name = "GradeDisplay",
		InitCommand = function(self)
			self:halign(1):x(wheelItemW/2 - 6):y(7):zoom(0.30):diffuse(dim)
		end,
	},
	LoadFont("Common Normal") .. {
		Name = "ArtistSubtitle",
		InitCommand = function(self)
			self:halign(0.5):x(0):y(11):zoom(0.30):diffuse(color("0.5,0.5,0.5,1"))
				:maxwidth((wheelItemW - 40) / 0.30)
		end,
	},
	LoadFont("Common Normal") .. {
		Name = "PermamirrorIndicator",
		InitCommand = function(self)
			self:halign(1):x(wheelItemW/2 - 35):y(-6):zoom(0.35):diffuse(color("#FF6666")):settext("(MR)")
				:visible(false)
		end,
	},
	Def.Quad {
		InitCommand = function(self)
			self:y(19):zoomto(wheelItemW, 1):diffuse(color("0.08,0.08,0.08,1"))
		end,
	},
}
