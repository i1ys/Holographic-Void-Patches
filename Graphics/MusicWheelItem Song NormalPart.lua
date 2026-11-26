local wheelItemW = 280
local neutral = color("0.65,0.65,0.65,1")
local dim = color("0.45,0.45,0.45,1")
local accentOff = color("0.15,0.15,0.15,1")

local function matchingChart(song, stepsType, difficulty, filtered)
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

local function updateRating(self, rate, showMSD)
	local rating = self:GetChild("MSDDisplay")
	local chart = self.chart
	if not chart then
		rating:settext("")
	elseif showMSD then
		local msd = chart:GetMSD(rate, 1)
		if msd > 0 then
			rating:settextf("%.2f", msd):diffuse(HVColor.GetMSDRatingColor(msd))
		else
			rating:settext("-"):diffuse(dim)
		end
	else
		rating:settext(tostring(chart:GetMeter())):diffuse(neutral)
	end
end

local function updateGrade(self, cachedOnly)
	local grade, ready
	if self.chart then
		local wheel = self:GetParent():GetParent()
		grade, ready = HV.WheelData.GetChartGrade(wheel, self.chart, cachedOnly)
		if ready then
			HV.WheelData.CancelRow(self)
		else
			HV.WheelData.QueueRow(wheel, self, "RefreshGrade", self.focused)
		end
	else
		HV.WheelData.CancelRow(self)
	end
	if self.shownGrade ~= grade then
		self.shownGrade = grade
		local label = self:GetChild("GradeDisplay")
		label:settext(grade and HV.GetGradeName(grade) or "")
		if grade then label:diffuse(HVColor.GetGradeColor(grade)) end
	end
end

local function updateMirror(self)
	self:GetChild("PermamirrorIndicator"):visible(self.chart ~= nil and self.chart:IsPermaMirror())
end

local function updateFavorite(self)
	self:GetChild("FavoriteStar"):visible(self.song ~= nil and self.song:IsFavorited())
end

local function updateChart(self)
	if not self.song then return end
	local selected = GAMESTATE:GetCurrentSteps()
	local chart, difficulty
	if selected then
		difficulty = selected:GetDifficulty()
		local stepsType = selected:GetStepsType()
		local focused = self.song == GAMESTATE:GetCurrentSong()
		local filtered = FILTERMAN:AnyActiveFilter()
		if focused then
			chart = selected
		elseif not filtered and self.matchSong == self.song and self.matchType == stepsType
			and self.matchDifficulty == difficulty and not self.matchFiltered and not self.matchFocused then
			chart = self.chart
		else
			chart = matchingChart(self.song, stepsType, difficulty, filtered)
		end
		self.matchSong, self.matchType, self.matchDifficulty = self.song, stepsType, difficulty
		self.matchFiltered, self.matchFocused = filtered, focused
	else
		self.matchSong = nil
	end
	local chartChanged = self.chart ~= chart
	self.chart = chart
	if self.shownDifficulty ~= difficulty then
		local accent = difficulty and HVColor.GetDifficultyColor(ToEnumShortString(difficulty))
		self:GetChild("DifficultyAccent"):diffuse(accent or accentOff):diffusealpha(accent and 0.6 or 1)
		self.shownDifficulty = difficulty
	end
	local rate = getCurRateValue()
	local showMSD = HV.ShowMSD()
	if chartChanged or self.ratingRate ~= rate or self.ratingShowsMSD ~= showMSD then
		updateRating(self, rate, showMSD)
		self.ratingRate, self.ratingShowsMSD = rate, showMSD
	end
	updateGrade(self, true)
	if chartChanged then updateMirror(self) end
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
		local rowType = params and params.Type
		local active = rowType ~= nil and self:GetName() == rowType .. "NormalPart"
		self.rowType = active and rowType or nil
		updateTitleColor(self)
		local song = active and rowType == "Song" and params.Song or nil
		self.focused = params and params.HasFocus
		if song == nil and self.song == nil then return end
		if song ~= self.song then
			self.song, self.matchSong = song, nil
			self:GetChild("ArtistSubtitle"):settext(song and song:GetDisplayArtist() or "")
			updateFavorite(self)
		end
		if not song then
			HV.WheelData.CancelRow(self)
			self.chart, self.ratingRate, self.shownGrade = nil, nil, nil
			self:GetChild("MSDDisplay"):settext("")
			self:GetChild("GradeDisplay"):settext("")
			self:GetChild("PermamirrorIndicator"):visible(false)
			self:GetChild("DifficultyAccent"):diffuse(accentOff):diffusealpha(1)
			self.shownDifficulty = nil
			return
		end
		updateChart(self)
	end,
	RefreshGradeCommand = function(self) updateGrade(self, false) end,
	CurrentStepsChangedMessageCommand = updateChart,
	CurrentRateChangedMessageCommand = updateChart,
	HV_WheelScoresChangedMessageCommand = function(self) if self.song then updateGrade(self, true) end end,
	FavoritesUpdatedMessageCommand = updateFavorite,
	FavoriteSongToggledMessageCommand = updateFavorite,
	PermamirrorUpdatedMessageCommand = updateMirror,
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
