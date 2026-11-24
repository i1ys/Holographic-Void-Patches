--- Holographic Void: MusicWheelItem Song NormalPart
-- Enhanced song row: MSD for selected difficulty type, local best grade and rate,
-- artist + subtitle display.
-- Uses SetMessageCommand with params.Song for reliable song data access.

local wheelItemW = 280
local pbRight = wheelItemW / 2 - 6
local pbWidth = 42
local favoriteX = pbRight - pbWidth - 8

-- MusicWheel reuses its rows continuously while scrolling.  These values do
-- not change during a Select Music visit, so avoid re-querying score history.
local wheelMSDCache = {}
local wheelPBCache = {}

local function cachedMSD(steps, rate)
	local chartKey = steps:GetChartKey()
	local key = chartKey and (chartKey .. "@" .. tostring(rate))
	local value = key and wheelMSDCache[key]
	if value == nil then
		value = steps:GetMSD(rate, 1) or 0
		if key then wheelMSDCache[key] = value end
	end
	return value
end

local function cachedBestResult(chartKey)
	local cached = wheelPBCache[chartKey]
	if cached ~= nil then return cached end

	local best, bestWife, bestRate = nil, -1, 0
	local scoresByRate = SCOREMAN:GetScoresByKey(chartKey)
	if scoresByRate then
		for _, scoresAtRate in pairs(scoresByRate) do
			local scoreList = scoresAtRate:GetScores()
			if scoreList then
				for _, score in ipairs(scoreList) do
					if not IsScoreInvalid(score) then
						local wife, rate = score:GetWifeScore(), score:GetMusicRate()
						if wife > bestWife or (best and wife == bestWife and rate > bestRate) then
							best, bestWife, bestRate = score, wife, rate
						end
					end
				end
			end
		end
	end

	-- false is a cache entry for charts with no usable score.
	wheelPBCache[chartKey] = best and {grade = best:GetWifeGrade(), rate = getRate(best)} or false
	return wheelPBCache[chartKey]
end

local function isSongFavorited(song)
	if not song then return false end

	local getters = {"IsFavorited", "IsFavorite", "GetFavorited", "GetIsFavorited"}
	for _, fn in ipairs(getters) do
		local method = song[fn]
		if type(method) == "function" then
			local ok, result = pcall(method, song)
			if ok then
				return result and true or false
			end
		end
	end

	return false
end

local t = Def.ActorFrame {}

-- Card background (OLED: true black unfocused, subtle lift on focus)
t[#t + 1] = Def.Quad {
	Name = "BgQuad",
	InitCommand = function(self)
		self:zoomto(wheelItemW, 38):diffuse(color("0.03,0.03,0.03,1"))
	end,
	SetMessageCommand = function(self, params)
		-- Removed focus-based background lift to match fixed highlight
	end
}

-- Left accent bar (difficulty color, OLED glow) - uses GAMESTATE for current selected diff
t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:x(-wheelItemW/2 + 1):zoomto(2, 30)
			:diffuse(color("0.15,0.15,0.15,1"))
	end,
	SetMessageCommand = function(self, params)
		local curSteps = GAMESTATE:GetCurrentSteps()
		if curSteps then
			local diff = ToEnumShortString(curSteps:GetDifficulty())
			local dc = (HVColor and HVColor.GetDifficultyColor and HVColor.GetDifficultyColor(diff))
				or (HVColor and HVColor.Difficulty and HVColor.Difficulty[diff])
			if dc then
				self:diffuse(dc):diffusealpha(0.6) -- Constant alpha for uniform look
				return
			end
		end
		self:diffuse(color("0.15,0.15,0.15,1"))
	end,
	CurrentStepsChangedMessageCommand = function(self)
		self:playcommand("Set")
	end
}

-- Favorite indicator
t[#t + 1] = Def.Sprite {
	Name = "FavoriteStar",
	Texture = THEME:GetPathG("", "round_star"),
	InitCommand = function(self)
		self:x(favoriteX):y(7):zoomto(10, 10)
			:diffuse(HVColor.Accent)
			:visible(false)
	end,
	SetMessageCommand = function(self, params)
		local song = (params and params.Song) or self.hv_lastSong
		self.hv_lastSong = song
		self:visible(isSongFavorited(song))
	end,
	FavoriteSongToggledMessageCommand = function(self, params)
		if not params or not params.Song or params.Song == self.hv_lastSong then
			self:playcommand("Set", {Song = self.hv_lastSong})
		end
	end
}

-- MSD rating text (right side) - shows MSD for the SAME difficulty as selected
t[#t + 1] = LoadFont("Common Normal") .. {
	Name = "MSDDisplay",
	InitCommand = function(self)
		self:halign(1):x(wheelItemW/2 - 6):y(-6)
			:zoom(0.40):diffuse(color("0.65,0.65,0.65,1")) -- Increased from 0.32
	end,
	SetMessageCommand = function(self, params)
		local song = (params and params.Song) or self.hv_lastSong
		self.hv_lastSong = song
		local curSteps = GAMESTATE:GetCurrentSteps()

		if not song or not curSteps then 
			self:settext("") 
			return 
		end

		local targetDiffOption = curSteps:GetDifficulty()
		local allSteps = (song.GetChartsOfCurrentGameType and song:GetChartsOfCurrentGameType()) or (song.GetStepsByStepsType and song:GetStepsByStepsType(GAMESTATE:GetCurrentStyle():GetStepsType()))
		
		local showMSD = HV.ShowMSD()
		
		if allSteps then
			for _, st in ipairs(allSteps) do
				if st:GetDifficulty() == targetDiffOption then
					if showMSD then
						local msd = cachedMSD(st, getCurRateValue())
						if msd and msd > 0 then
							self:settext(string.format("%.2f", msd)) -- Standardized to 2 decimal points
							self:diffuse(HVColor.GetMSDRatingColor(msd))
						else
							self:settext("-")
							self:diffuse(color("0.45,0.45,0.45,1"))
						end
					else
						-- Show chart meter if MSD is disabled
						local meter = st:GetMeter()
						self:settext(tostring(meter))
						self:diffuse(color("0.65,0.65,0.65,1")) -- Neutral text color
					end
					return
				end
			end
		end
		self:settext("")
	end,
	CurrentStepsChangedMessageCommand = function(self)
		self:playcommand("Set", {Song = self.hv_lastSong})
	end,
	CurrentRateChangedMessageCommand = function(self)
		self:playcommand("Set", {Song = self.hv_lastSong})
	end
}

-- Personal best badge (right side, below MSD) for the matching difficulty.
t[#t + 1] = LoadFont("Common Normal") .. {
	Name = "GradeDisplay",
	InitCommand = function(self)
		self:halign(1):x(pbRight):y(7)
			:zoom(0.30):maxwidth(pbWidth / 0.30):diffuse(color("0.45,0.45,0.45,1"))
	end,
	SetMessageCommand = function(self, params)
		local song = (params and params.Song) or self.hv_lastSong
		self.hv_lastSong = song
		local curSteps = GAMESTATE:GetCurrentSteps()

		if not song or not curSteps then 
			self:settext("") 
			return 
		end

		local targetDiffOption = curSteps:GetDifficulty()
		local allSteps = (song.GetChartsOfCurrentGameType and song:GetChartsOfCurrentGameType()) or (song.GetStepsByStepsType and song:GetStepsByStepsType(GAMESTATE:GetCurrentStyle():GetStepsType()))
		if allSteps then
			for _, st in ipairs(allSteps) do
				if st:GetDifficulty() == targetDiffOption then
					local profile = PROFILEMAN:GetProfile(PLAYER_1)
					if profile then
						local chartKey = st:GetChartKey()
						if chartKey then
							local best = cachedBestResult(chartKey)
							if best and best.grade and best.grade ~= "Grade_Failed" then
								self:settextf("%s %s", HV.GetGradeName(best.grade), best.rate)
								self:diffuse(HVColor.GetGradeColor(ToEnumShortString(best.grade)))
								return
							end
						end
					end
				end
			end
		end
		self:settext("")
	end,
	CurrentStepsChangedMessageCommand = function(self)
		self:playcommand("Set", {Song = self.hv_lastSong})
	end
}

-- Artist / Subtitle line - uses params.Song
t[#t + 1] = LoadFont("Common Normal") .. {
	Name = "ArtistSubtitle",
	InitCommand = function(self)
		self:halign(0.5):x(0):y(11)
			:zoom(0.30):diffuse(color("0.5,0.5,0.5,1"))
			:maxwidth(2 * (favoriteX - 8) / 0.30)
	end,
	SetMessageCommand = function(self, params)
		local song = params and params.Song
		if song then
			local artist = song:GetDisplayArtist() or ""
			local subtitle = song:GetDisplaySubTitle() or ""
				self:settext(artist)
		else
			self:settext("")
		end
	end
}

-- Permamirror Indicator
t[#t + 1] = LoadFont("Common Normal") .. {
	Name = "PermamirrorIndicator",
	InitCommand = function(self)
		-- Position left of the MSD value 
		self:halign(1):x(wheelItemW/2 - 35):y(-6)
			:zoom(0.35):diffuse(color("#FF6666")):settext("(MR)")
	end,
	SetMessageCommand = function(self, params)
		local song = (params and params.Song) or self.hv_lastSong
		self.hv_lastSong = song
		local curSteps = GAMESTATE:GetCurrentSteps()
		
		if not song or not curSteps then 
			self:visible(false)
			return 
		end

		local targetDiffOption = curSteps:GetDifficulty()
		local allSteps = (song.GetChartsOfCurrentGameType and song:GetChartsOfCurrentGameType()) or (song.GetStepsByStepsType and song:GetStepsByStepsType(GAMESTATE:GetCurrentStyle():GetStepsType()))
		
		local isPM = false
		if allSteps then
			for _, st in ipairs(allSteps) do
				if st:GetDifficulty() == targetDiffOption then
					if st.IsPermaMirror and st:IsPermaMirror() then
						isPM = true
					end
					break
				end
			end
		end

		self:visible(isPM)
	end,
	CurrentStepsChangedMessageCommand = function(self)
		self:playcommand("Set", {Song = self.hv_lastSong})
	end,
	PermamirrorUpdatedMessageCommand = function(self)
		self:stoptweening():sleep(0.05):queuecommand("Set", {Song = self.hv_lastSong})
	end,
	PermamirrorChangedMessageCommand = function(self)
		self:stoptweening():sleep(0.05):queuecommand("Set", {Song = self.hv_lastSong})
	end
}

-- Bottom separator (OLED: very subtle, barely visible hairline)
t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:y(19):zoomto(wheelItemW, 1)
			:diffuse(color("0.08,0.08,0.08,1"))
	end
}

-- Engine text color override
t[#t + 1] = Def.Actor {
	SetMessageCommand = function(self)
		local normalPart = self:GetParent()
		if not normalPart then return end
		local mwi = normalPart:GetParent()
		if not mwi then return end

		local names = {"SongName", "SubTitle", "Sort", "Roulette", "Random", "Custom", "Portal", "Mode"}
		for _, name in ipairs(names) do
			local textActor = mwi:GetChild(name)
			if textActor and textActor:GetVisible() then
				textActor:diffuse(HVColor.Accent)
				-- Apply maxwidth and centering in Lua to avoid metrics issues
				if textActor.maxwidth then
					textActor:maxwidth(wheelItemW * 0.8 / textActor:GetZoom())
				end
			end
		end
	end,
	ColorThemeChangedMessageCommand = function(self) self:playcommand("Set") end
}

return t
