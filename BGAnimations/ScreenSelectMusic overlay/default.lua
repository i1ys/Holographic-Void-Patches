local ThemePrefs = HV.LegacyPrefs

--- Holographic Void: ScreenSelectMusic Overlay
-- Restore sequential Til Death-style login flow.

local accentColor = HVColor.Accent
local brightText = color("1,1,1,1")

-- Initialize session grade counters and the profile grade refresh.
LoadActor("../gradecounter.lua")

-- Compact Profile Login Button Bounds
local panelX = 20
local panelW = SCREEN_WIDTH * 0.36
local compactProfileX = panelX + panelW + 16
local compactProfileY = SCREEN_HEIGHT - 40 - 75

local btnCX = compactProfileX + 40
local btnCY = compactProfileY - 22
local btnW, btnH = 80, 24

-- Profile Overlay Constants
local overlayW, overlayH = SCREEN_WIDTH * 0.94, SCREEN_HEIGHT * 0.75
local colW, scorePageSize = overlayW / 3, 10
local skillsets = {"Overall", "Stream", "Jumpstream", "Handstream", "Stamina", "JackSpeed", "Chordjack", "Technical"}

-- New Column Constants
local gradeSidebarW = 70
local profileSidebarW = 160
local mainPartW = overlayW - gradeSidebarW - profileSidebarW
local sidebarW = gradeSidebarW + profileSidebarW
local skillsetTabH = 26
local rowH = 28
local rowsYStart = 60

local subText = color("0.65,0.65,0.65,1")
local mainText = color("0.85,0.85,0.85,1")
local dimText = color("0.45,0.45,0.45,1")
local bgCard = color("0.06,0.06,0.06,0.9")

local profileOverlayActor = nil
local globalTooltipActor = nil
local focus = LoadActor("input_focus.lua")
local filterInput
local searchRefreshPending = false
local searchString = ""
local requestedSearch = ""
local searchResult = {query = "", hasMatches = true}
local searchRefreshActor

-- Online top-score entries are not guaranteed to be native HighScore objects;
-- some Etterna versions return plain tables.  Keep the validation indicator
-- useful for both shapes without making online entries toggleable locally.
local function isProfileScoreInvalid(score)
	if not score then return false end
	if type(score.GetEtternaValid) == "function" then
		local ok, valid = pcall(score.GetEtternaValid, score)
		if ok and valid == false then return true end
	end
	if type(score) == "table" then
		return score.etternaValid == false or score.etterna_valid == false
			or score.valid == false or score.invalid == true or score.invalidated == true
	end
	return IsScoreInvalid(score)
end

local searchFields = {
	title = "GetDisplayMainTitle",
	subtitle = "GetDisplaySubTitle",
	artist = "GetDisplayArtist",
	author = "GetOrTryAtLeastToGetSimfileAuthor",
	pack = "GetGroupName",
}

local function wheelSearchQuery(query)
	query = query:match("^%s*(.-)%s*$")
	if query == "" then return "" end
	local field, value = query:match("^(%a+)=(.*)$")
	field = field and field:lower()
	if field == "p" or field == "group" then
		field = "pack"
	elseif field == "charter" or field == "stepper" then
		field = "author"
	elseif not searchFields[field] and field ~= "ck" then
		field, value = "title", query
	end
	value = value:match("^%s*(.-)%s*$")
	if value == "" then return "" end
	local nativeQuery = field .. "=" .. value
	if value:find(";%s*%a+=") then return nativeQuery end
	local term = value:lower()
	if field == "ck" then
		return nativeQuery, function(song)
			for _, steps in ipairs(song:GetAllSteps()) do
				if steps:GetChartKey():lower():find(term, 1, true) then return true end
			end
			return false
		end
	end
	local getter = searchFields[field]
	return nativeQuery, function(song)
		local getField = song[getter]
		return getField and (getField(song) or ""):lower():find(term, 1, true) ~= nil
	end
end

local function refreshMusicSearch()
	searchRefreshPending = not focus.isCurrent()
	if searchRefreshPending then return false end
	local screen = SCREENMAN:GetTopScreen()
	local wheel = screen and screen.GetMusicWheel and screen:GetMusicWheel()
	if not wheel then return false end
	local query = requestedSearch
	local nativeQuery, matches = wheelSearchQuery(query)
	wheel:SongSearch(nativeQuery)
	local hasMatches = true
	if matches and wheel.GetSongs then
		-- The native wheel keeps the previous results when its search finds none.
		hasMatches = false
		for _, song in ipairs(wheel:GetSongs()) do
			if matches(song) then
				hasMatches = true
				break
			end
		end
	end
	searchResult = {query = query, hasMatches = hasMatches, matches = matches}
	return true
end

local function setSearchText(query, apply, debounce)
	searchString = query
	if apply then
		if searchRefreshActor then searchRefreshActor:stoptweening() end
		requestedSearch = query
		if debounce and searchRefreshActor then
			searchRefreshActor:sleep(0.12):queuecommand("ApplySearch")
			apply = false
		else
			apply = refreshMusicSearch()
		end
	end
	MESSAGEMAN:Broadcast("SearchQueryUpdated", {query = searchString, applied = apply})
end

HV.SetMusicSearchQuery = function(query)
	setSearchText(tostring(query or ""), true)
end
HV.GetMusicSearchQuery = function() return searchString end
HV.RefreshMusicSearch = function(onlyIfActive)
	if onlyIfActive and requestedSearch == "" then return end
	if searchRefreshActor then searchRefreshActor:stoptweening() end
	local applied = refreshMusicSearch()
	MESSAGEMAN:Broadcast("SearchQueryUpdated", {query = searchString, applied = applied})
end

-- Mouse wheel locking to prevent double-moves
local lastWheelMove = 0
local wheelLockTime = 0.05

-- Bottom Footer Config (Top-level for scope)
local tabs = {"PROFILE", "SCORES", "PLAYLISTS", "FILTERS", "TAGS", "GOALS", "RANDOM"}
local tabW = 80
local footerH = 40
local footerOverlayTabs = {
	PROFILE = true,
	SCORES = true,
	PLAYLISTS = true,
	FILTERS = true,
	TAGS = true,
	GOALS = true,
}

-- nowplaying.txt
updateNowPlaying()

local function PlayWhooshOverlayOpen()
	SOUND:PlayOnce(THEME:GetPathS("", "whoosh"))
end

local function IsSelectMusicBackgroundClickArea()
	local mx = INPUTFILTER:GetMouseX() or SCREEN_CENTER_X
	local my = INPUTFILTER:GetMouseY() or SCREEN_CENTER_Y
	if HV.ActiveTab and HV.ActiveTab ~= "" then return false end
	if my <= 40 or my >= SCREEN_HEIGHT - 40 then return false end
	-- The login/logout button is part of the profile card just outside the
	-- panel.  Keep clicking it from also starting the background peek hold.
	local loginX = panelX + panelW + 16
	local loginY = SCREEN_HEIGHT - 40 - 75 - 22
	if mx >= loginX and mx <= loginX + 80 and my >= loginY - 12 and my <= loginY + 12 then
		return false
	end
	-- The background peek should cover the open space immediately beside the
	-- left panel.  The old 110px buffer left a large, unusable dead strip.
	if mx <= panelX + panelW + 16 then return false end
	if mx >= SCREEN_WIDTH - 340 and mx <= SCREEN_WIDTH - 10 and my >= 84 and my <= SCREEN_HEIGHT - 64 then return false end
	return true
end

local function searchBlocksWheelSelection(screen, wheel)
	-- The native wheel can still point at a song from the previous query after a miss.
	if searchResult.hasMatches or screen:GetSelectionState() ~= 0 then return false end
	wheel = wheel or screen:GetMusicWheel()
	if not wheel then return false end
	local row = wheel:GetSelectedType()
	return row == "WheelItemDataType_Song" or row == "WheelItemDataType_Random"
		or row == "WheelItemDataType_Roulette" or row == "WheelItemDataType_Portal"
end

local function selectRandomSong(screen)
	local result = searchResult
	if not result.hasMatches or GAMESTATE:GetSortOrder() == "SortOrder_ModeMenu" then return end
	local wheel = screen:GetMusicWheel()
	if not wheel then return end
	local songs = wheel:GetSongs()
	while #songs > 0 do
		local index = math.random(#songs)
		local song = songs[index]
		if (not result.matches or result.matches(song)) and wheel:SelectSong(song) then return end
		songs[index] = songs[#songs]
		songs[#songs] = nil
	end
end

local function ApplyNativeMusicWheelHoldTransform(p)
	local screen = SCREENMAN:GetTopScreen()
	local wheel = screen and screen.GetMusicWheel and screen:GetMusicWheel()
	if wheel then
		wheel:x((SCREEN_WIDTH - 180) + (SCREEN_WIDTH * 0.32) * p)
	end
end

local main_af = Def.ActorFrame {
	Def.Actor {
		InitCommand = function(self) searchRefreshActor = self end,
		ApplySearchCommand = function() HV.RefreshMusicSearch() end,
		OffCommand = function(self) self:stoptweening() end,
	},
	BeginCommand = function(self)
		Branch.CloseMultiplayerConnection()
		focus.attach()
		self:SetUpdateFunction(function()
			focus.update()
			if searchRefreshPending and focus.isCurrent() then HV.RefreshMusicSearch() end
		end)
		HV.GameplaySessionValid = false
		HV.OnlineReplayActive = false
		HV.OnlineReplayName = nil
		HV.ChartPreviewActive = false
		HV.LeftMousePeekHold = false
		HV.LeftMousePeekHoldAllowed = false
		ApplyNativeMusicWheelHoldTransform(0)
		if INPUTFILTER and INPUTFILTER.SetMouseVisible then
			INPUTFILTER:SetMouseVisible(true)
		end
		
		-- If returning from a gameplay session, reset the preview position to 0
		-- to avoid trying to "resume" from the end of the song.
		HV.LastPlayedSecond = 0
		
		-- Always default Practice Mode to Off when entering song select
		GAMESTATE:SetPracticeMode(false)
		
		-- Refresh EtternaOnline user data upon entering Select Music (e.g. after finishing a song)
		if DLMAN:IsLoggedIn() and DLMAN.RefreshUserData then
			DLMAN:RefreshUserData()
		end

		self:sleep(0.01):queuecommand("CheckFirstLaunchSSM")
	end,
	SelectMusicTabChangedMessageCommand = function(self, params)
		focus.setTab(params and params.Tab)
	end,
	OffCommand = function(self)
		focus.dispose()
		searchRefreshPending = false
		self:SetUpdateFunction(nil)
	end,
	CheckFirstLaunchSSMCommand = function(self)
		if PROFILEMAN:GetNumLocalProfiles() == 0 then
			easyInputStringOKCancel(
				THEME:GetString("ScreenTitleMenu", "CreateProfilePrompt"), 255, false,
				function(name)
					if name ~= "" then
						local newProfile = PROFILEMAN:CreateDefaultProfile()
						if newProfile then
							newProfile:RenameProfile(name)
							if PROFILEMAN:GetNumLocalProfiles() > 0 then
								HV.TitleState = HV.TitleState or {}
								HV.TitleState.selectedProfile = 0
								ms.ok("Profile '" .. name .. "' created successfully!")
								MESSAGEMAN:Broadcast("ThemePrefChanged", {Name = "HV_BGAnimIntensity"})
							else
								ms.ok("Failed to create profile. Please try again.")
								self:sleep(0.5):queuecommand("CheckFirstLaunchSSM")
							end
						else
							ms.ok("Failed to create default profile.")
							self:sleep(0.5):queuecommand("CheckFirstLaunchSSM")
						end
					else
						ms.ok("A local profile is required to save scores.")
						self:sleep(0.5):queuecommand("CheckFirstLaunchSSM")
					end
				end,
				function()
					ms.ok("A local profile is required to save scores.")
					self:sleep(0.5):queuecommand("CheckFirstLaunchSSM")
				end
			)
		end
	end,
	EndCommand = function(self)
		focus.dispose()
		if HV.LeftMousePeekHold then
			HV.LeftMousePeekHold = false
			HV.LeftMousePeekHoldAllowed = false
			MESSAGEMAN:Broadcast("HVLeftMousePeekHoldChanged", {Held = false, Allowed = false})
		end
		ApplyNativeMusicWheelHoldTransform(0)
	end,
	LoginMessageCommand = function(self)
		local user = DLMAN:GetUsername()
		local token = DLMAN:GetToken()
		if user and token and user ~= "" and token ~= "" then
			ThemePrefs.Set("HV_Username", user)
			ThemePrefs.Set("HV_PasswordToken", token)
			ThemePrefs.Save()
		end
	end,
	LoginFailedMessageCommand = function(self)
		ms.ok("Login Failed. Please check your credentials.")
	end,
	LogOutMessageCommand = function(self)
		-- Only clear username on manual logout to preserve auto-login token
	end,
	TriggerLoginFlowMessageCommand = function(self)
		-- Sequential Til Death flow with frame delay to avoid overlaps
		local tempEmail = ""
		easyInputStringOKCancel(
			"Email:", 255, true,
			function(email)
				if email ~= "" then
					self.tempEmail = email
					self:sleep(0.02):queuecommand("LoginStep2")
				else
					ms.ok("Login Canceled")
				end
			end,
			function() ms.ok("Login Canceled") end
		)
	end,
	
	LoginStep2Command = function(self)
		easyInputStringOKCancel(
			"Password:", 255, true,
			function(password)
				if password ~= "" then
					Trace("[HV] Attempting DLMAN:Login for " .. tostring(self.tempEmail))
					DLMAN:Login(self.tempEmail, password)
				else
					ms.ok("Login Canceled")
				end
			end,
			function() ms.ok("Login Canceled") end
		)
	end,
	
	CodeMessageCommand = function(self, params)
		if params.Name == "Permamirror" then
			-- The engine has already toggled the flag because the code was matched.
			-- We just need to trigger the UI update.
			MESSAGEMAN:Broadcast("PermamirrorChanged")
		end
	end
}


-- LoginButtonUI was moved to decorations/default.lua to nest visually within the profile card.


local tabShortcuts = {
	DeviceButton_1 = "PROFILE",
	DeviceButton_2 = "SCORES",
	DeviceButton_3 = "PLAYLISTS",
	DeviceButton_4 = "SEARCH",
	DeviceButton_5 = "TAGS",
	DeviceButton_6 = "GOALS",
}

local function handleHeaderAndFooter(event, screen, x, y)
	if x >= 0 and x <= 80 and y >= 0 and y <= 40 then
		if HV.ActiveTab == "" then
			screen:Cancel()
		else
			focus.hold(event)
			MESSAGEMAN:Broadcast("SelectMusicTabChanged", {Tab = ""})
		end
		return true
	end
	local searchX = SCREEN_CENTER_X - 150
	if x >= searchX and x <= searchX + 300 and y >= 6 and y <= 34 then
		MESSAGEMAN:Broadcast("SelectMusicTabChanged", {Tab = "SEARCH"})
		return true
	end
	if y < SCREEN_HEIGHT - footerH or y > SCREEN_HEIGHT then return false end
	local tab = tabs[math.floor((x - 10) / tabW) + 1]
	if not tab then return false end
	if tab == "RANDOM" then
		selectRandomSong(screen)
	else
		local nextTab = tab == HV.ActiveTab and "" or tab
		if nextTab ~= "" and footerOverlayTabs[nextTab] then PlayWhooshOverlayOpen() end
		if nextTab == "" then focus.hold(event) end
		MESSAGEMAN:Broadcast("SelectMusicTabChanged", {Tab = nextTab})
	end
	return true
end

-- Rate adjustment via CodeMessage (EffectUp/EffectDown mapped in metrics.ini)
local lastRatePresses = {0, 0}

local function adjustRate(delta)
	local curRate = getCurRateValue() or 1.0
	local nr = math.floor((curRate + delta) * 100 + 0.5) / 100
	nr = math.max(0.05, math.min(3.0, nr))
	local songOpts = GAMESTATE:GetSongOptionsObject("ModsLevel_Preferred")
	if songOpts then
		songOpts:MusicRate(nr)
		GAMESTATE:GetSongOptionsObject("ModsLevel_Song"):MusicRate(nr)
		GAMESTATE:GetSongOptionsObject("ModsLevel_Current"):MusicRate(nr)
		MESSAGEMAN:Broadcast("CurrentRateChanged", {rate = nr, oldRate = curRate})
	end
end

local function resetRate()
	local songOpts = GAMESTATE:GetSongOptionsObject("ModsLevel_Preferred")
	if songOpts then
		songOpts:MusicRate(1.0)
		GAMESTATE:GetSongOptionsObject("ModsLevel_Song"):MusicRate(1.0)
		GAMESTATE:GetSongOptionsObject("ModsLevel_Current"):MusicRate(1.0)
		MESSAGEMAN:Broadcast("CurrentRateChanged")
	end
end

local function getSongFavoriteState(song)
	if not song then return nil end

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

	return nil
end

local function toggleCurrentSongFavorite()
	local song = GAMESTATE:GetCurrentSong()
	if not song then return false end

	local profile = PROFILEMAN and PROFILEMAN:GetProfile(PLAYER_1)
	local currentState = getSongFavoriteState(song)

	local songToggles = {
		"ToggleFavorited",
		"ToggleFavorite",
	}
	for _, fn in ipairs(songToggles) do
		local method = song[fn]
		if type(method) == "function" then
			local ok = pcall(method, song)
			if ok then
				MESSAGEMAN:Broadcast("FavoriteSongToggled", {Song = song})
				return true
			end
		end
	end

	local songSetters = {"SetFavorited", "SetFavorite"}
	if currentState ~= nil then
		for _, fn in ipairs(songSetters) do
			local method = song[fn]
			if type(method) == "function" then
				local ok = pcall(method, song, not currentState)
				if ok then
					MESSAGEMAN:Broadcast("FavoriteSongToggled", {Song = song})
					return true
				end
			end
		end
	end

	if profile then
		local profileToggles = {
			"ToggleSongFavorite",
			"ToggleFavorite",
		}
		for _, fn in ipairs(profileToggles) do
			local method = profile[fn]
			if type(method) == "function" then
				local ok = pcall(method, profile, song)
				if ok then
					MESSAGEMAN:Broadcast("FavoriteSongToggled", {Song = song})
					return true
				end
			end
		end

		if currentState ~= nil then
			local method = currentState and profile.RemoveFromFavorites or profile.AddToFavorites
			if type(method) == "function" then
				local ok = pcall(method, profile, song)
				if ok then
					MESSAGEMAN:Broadcast("FavoriteSongToggled", {Song = song})
					return true
				end
			end
		end
	end

	return false
end

-- Centralized Input Callback (Handles Click, Scroll, and both-EffectUp/Down reset)
main_af[#main_af + 1] = Def.ActorFrame {
	-- Handle rate changes via CodeMessageCommand (fired by metrics.ini CodeNames)
	CodeMessageCommand = function(self, params)
		if not params or not params.Name then return end
		if params.Name == "NextRate" then
			lastRatePresses[2] = GetTimeSinceStart and GetTimeSinceStart() or os.clock()
			-- Check for simultaneous press (both within 50ms)
			if math.abs(lastRatePresses[1] - lastRatePresses[2]) < 0.05 and lastRatePresses[1] ~= 0 and lastRatePresses[2] ~= 0 then
				resetRate()
			else
				adjustRate(0.05)
			end
		elseif params.Name == "PrevRate" then
			lastRatePresses[1] = GetTimeSinceStart and GetTimeSinceStart() or os.clock()
			if math.abs(lastRatePresses[1] - lastRatePresses[2]) < 0.05 and lastRatePresses[1] ~= 0 and lastRatePresses[2] ~= 0 then
				resetRate()
			else
				adjustRate(-0.05)
			end
		elseif params.Name == "FavoriteToggle" then
			toggleCurrentSongFavorite()
		end
	end,
	BeginCommand = function(self)
		focus.bind(function(event, screen)
			
			-- Banish inputs processing if chart preview is active so clicks don't leak through
			if HV.ChartPreviewActive then return false end
			
			local deviceInput = event.DeviceInput
			local btn = deviceInput.button or ""
			local evType = event.type or ""
			if btn == "DeviceButton_left mouse button" then
				local nextHeld = nil
				local allowed = false
				if evType == "InputEventType_FirstPress" then
					allowed = IsSelectMusicBackgroundClickArea()
					nextHeld = allowed
				elseif evType == "InputEventType_Release" then
					nextHeld = false
				end
				if nextHeld ~= nil and HV.LeftMousePeekHold ~= nextHeld then
					HV.LeftMousePeekHold = nextHeld
					HV.LeftMousePeekHoldAllowed = allowed
					MESSAGEMAN:Broadcast("HVLeftMousePeekHoldChanged", {Held = nextHeld, Allowed = allowed})
				end
			end
			local logicalBtn = event.GameButton or event.button or ""
			local isEnter = logicalBtn == "Start" or btn == "DeviceButton_enter" or btn == "DeviceButton_kp enter"
			local ctrl = INPUTFILTER:IsBeingPressed("left ctrl") or INPUTFILTER:IsBeingPressed("right ctrl")
			if ctrl and evType == "InputEventType_FirstPress" then
				local tab = tabShortcuts[btn]
				if tab then
					if tab ~= "SEARCH" and HV.ActiveTab ~= tab then PlayWhooshOverlayOpen() end
					MESSAGEMAN:Broadcast("SelectMusicTabChanged", {Tab = tab})
					return true
				elseif btn == "DeviceButton_7" then
					selectRandomSong(screen)
					return true
				end
			end

			-- 2. Mouse Click
			if btn == "DeviceButton_right mouse button" and evType == "InputEventType_FirstPress" then
				-- A. Handle Score Validation if over a row
				if HV.ActiveTab == "PROFILE" then
					local profileSidebarX = (SCREEN_CENTER_X - overlayW/2) + gradeSidebarW
					local scoreAreaX = profileSidebarX + profileSidebarW
					local absRowsYStart = SCREEN_CENTER_Y - overlayH/2 + rowsYStart
					for i = 1, scorePageSize do
						if IsMouseOver(scoreAreaX + 10, absRowsYStart + (i-1)*rowH - rowH/2, mainPartW - 20, rowH) then
							MESSAGEMAN:Broadcast("OverlayRowRightClicked", {index = i})
							return true
						end
					end
				end

				-- B. Fallback: Pause sample music (ONLY if no tab is open)
				if HV.ActiveTab == "" then
					local screen = SCREENMAN:GetTopScreen()
					if screen and screen.PauseSampleMusic then
						screen:PauseSampleMusic()
						MESSAGEMAN:Broadcast("MusicPauseToggled")
					end
					return true
				end

				-- Skip general overlay buttons and fallback traps if a decoration tab is busy
				if HV.ActiveTab ~= "" and HV.ActiveTab ~= "PROFILE" then return false end
			end
			if btn == "DeviceButton_left mouse button" and evType == "InputEventType_FirstPress" then
				local virtualX = INPUTFILTER:GetMouseX()
				local virtualY = INPUTFILTER:GetMouseY()

				if handleHeaderAndFooter(event, screen, virtualX, virtualY) then return true end

				-- If PROFILE tab is open, handle click-outside to close
				if HV.ActiveTab == "PROFILE" then
					if not IsMouseOverCentered(SCREEN_CENTER_X, SCREEN_CENTER_Y, overlayW, overlayH) then
						focus.hold(event)
						MESSAGEMAN:Broadcast("SelectMusicTabChanged", {Tab = ""})
						return true
					end
				end

				if HV.ActiveTab == "FILTERS" then return filterInput(event) end
				-- Other decoration tabs handle their own input.
				if HV.ActiveTab ~= "" and HV.ActiveTab ~= "PROFILE" then return false end

				-- Check Login Button logic (btnCX/btnCY defined above)
				local loginOver = virtualX >= btnCX - btnW/2 and virtualX <= btnCX + btnW/2
						 and virtualY >= btnCY - btnH/2 and virtualY <= btnCY + btnH/2
				if HV.ActiveTab == "" and loginOver then
					if DLMAN:IsLoggedIn() then
						ThemePrefs.Set("HV_Username", "")
						ThemePrefs.Set("HV_PasswordToken", "")
						ThemePrefs.Save()
						DLMAN:Logout()
						ms.ok("Logged Out")
					else
						MESSAGEMAN:Broadcast("TriggerLoginFlow")
					end
					return true
				end

				-- Check Avatar Button
				if virtualX >= compactProfileX - 8 and virtualX <= compactProfileX + 50
				   and virtualY >= compactProfileY - 8 and virtualY <= compactProfileY + 50 then
					SCREENMAN:SetNewScreen("ScreenAssetSettings")
					return true
				end

				-- --- PROFILE TAB SPECIFIC CLICKS ---
				if HV.ActiveTab == "PROFILE" then
					local profileSidebarX = (SCREEN_CENTER_X - overlayW/2) + gradeSidebarW
					local scoreAreaX = profileSidebarX + profileSidebarW
					local headerY = SCREEN_CENTER_Y - overlayH/2 + 35

					-- 2. Mode Toggle (TOP / RECENT)
					if IsMouseOverCentered(scoreAreaX + mainPartW - 250, headerY, 100, 24) then
						profileOverlayActor.isRecentMode = not profileOverlayActor.isRecentMode
						profileOverlayActor.topPage = 1; profileOverlayActor.recentPage = 1
						MESSAGEMAN:Broadcast("UpdateOverlayUI"); return true
					end
					-- 3. Source Toggle (ONLINE / LOCAL)
					if IsMouseOverCentered(scoreAreaX + mainPartW - 140, headerY, 100, 24) then
						if not profileOverlayActor.isRecentMode then
							profileOverlayActor.isOnlineMode = not profileOverlayActor.isOnlineMode
							profileOverlayActor.topPage = 1
							MESSAGEMAN:Broadcast("UpdateOverlayUI")
						end
						return true
					end
					-- 4. Upload Button
					if IsMouseOverCentered(scoreAreaX + mainPartW - 40, headerY, 80, 24) then
						if DLMAN:IsLoggedIn() then DLMAN:UploadAllScores() else ms.ok("Log in to upload scores.") end
						return true
					end
					-- 5. Avatar
					if IsMouseOverCentered(profileSidebarX + profileSidebarW/2, SCREEN_CENTER_Y - overlayH/2 + 50, 60, 60) then
						SCREENMAN:SetNewScreen("ScreenAssetSettings"); return true
					end
					-- 6. Skillset Tabs
					local tabsYStart = SCREEN_CENTER_Y - overlayH/2 + 140
					for i, ss in ipairs(skillsets) do
						if IsMouseOver(profileSidebarX + 10, tabsYStart + (i-1)*skillsetTabH - skillsetTabH/2, profileSidebarW - 20, skillsetTabH) then
							-- ms.ok("Skillset Click: " .. ss)
							profileOverlayActor.currentSkillset = ss; profileOverlayActor.isRecentMode = false; profileOverlayActor.topPage = 1
							if not profileOverlayActor.isOnlineMode then SCOREMAN:SortSSRsForGame(ss) end
							MESSAGEMAN:Broadcast("UpdateOverlayUI"); return true
						end
					end
					-- 7. Score Rows
					local absRowsYStart = SCREEN_CENTER_Y - overlayH/2 + rowsYStart
					for i = 1, scorePageSize do
						if IsMouseOver(scoreAreaX + 10, absRowsYStart + (i-1)*rowH - rowH/2, mainPartW - 20, rowH) then
							-- ms.ok("Row Click: " .. i)
							MESSAGEMAN:Broadcast("OverlayRowClicked", {index = i}); return true
						end
					end
				end

				-- If an overlay is active, and we haven't handled the click yet, 
				-- we return true to sink it so it doesn't click the music wheel under the overlay.
				-- EXCEPT if it's a decoration tab (GOALS, TAGS, etc.) which handle their own sinking.
				if HV.ActiveTab == "PROFILE" then
					return true
				end

				-- --- MUSIC WHEEL SELECTION ---
				-- If no tab is active, handle clicking on music wheel items
				if HV.ActiveTab == "" then
					local wheel = screen:GetMusicWheel()
					if wheel and math.abs(virtualX - wheel:GetTrueX()) <= 140 then
						local y = virtualY - wheel:GetTrueY()
						local offset = math.floor(y / 40 + 0.5)
						if math.abs(offset) <= 5 and math.abs(y - offset * 40) <= 19 then
							if offset == 0 and (wheel:IsSettled() or wheel:IsRouletting()) then
								if not screen:IsTransitioning() and not searchBlocksWheelSelection(screen, wheel) then
									screen:SelectCurrent()
								end
							elseif wheel:IsSettled() then
								local direction = offset > 0 and 1 or -1
								for _ = 1, math.abs(offset) do
									wheel:Move(direction)
									wheel:Move(0)
								end
							end
							return true
						end
					end
				end
			end
			
			if HV.ActiveTab == "FILTERS" and filterInput(event) then return true end

			-- 2.6 Mouse Wheel & Keyboard Navigation
			-- BLOCKED if an overlay tab is open
			local navigationBtns = {
				["DeviceButton_mousewheel up"] = -1,
				["DeviceButton_mousewheel down"] = 1,
				["DeviceButton_left"] = -1,
				["DeviceButton_right"] = 1,
				["DeviceButton_up"] = -1,
				["DeviceButton_down"] = 1,
			}
			local gameBtnDirs = {
				["MenuLeft"] = -1,
				["MenuRight"] = 1,
				["MenuUp"] = -1,
				["MenuDown"] = 1,
				["Left"] = -1,
				["Right"] = 1,
			}
			
			local dir = navigationBtns[btn] or gameBtnDirs[logicalBtn]
			
			if dir then
				if HV.ActiveTab ~= "" and HV.ActiveTab ~= "SEARCH" then
					if evType == "InputEventType_FirstPress" or evType == "InputEventType_Repeat" then
						if HV.ActiveTab == "PROFILE" then
							if dir < 0 then MESSAGEMAN:Broadcast("PrevScorePage")
							else MESSAGEMAN:Broadcast("NextScorePage") end
						elseif HV.ActiveTab == "PLAYLISTS" then
							if dir < 0 then MESSAGEMAN:Broadcast("PrevPlaylistPage")
							else MESSAGEMAN:Broadcast("NextPlaylistPage") end
						elseif HV.ActiveTab == "GOALS" then
							if dir < 0 then MESSAGEMAN:Broadcast("PrevGoalPage")
							else MESSAGEMAN:Broadcast("NextGoalPage") end
						else
							MESSAGEMAN:Broadcast("TabNavigation", {dir = dir})
						end
					end
					return true 
				end
				
				if HV.ActiveTab ~= "SEARCH" and (evType == "InputEventType_FirstPress" or evType == "InputEventType_Repeat") then
					if btn == "DeviceButton_mousewheel up" or btn == "DeviceButton_mousewheel down" then
						if HV.CapturesDifficultyScroll and HV.CapturesDifficultyScroll(btn) then return false end
						local now = (GetTimeSinceStart and GetTimeSinceStart()) or os.clock()
						if now - lastWheelMove < wheelLockTime then return true end
						
						local mw = screen:GetMusicWheel()
						if mw then
							mw:Move(dir)
							mw:Move(0)
							lastWheelMove = now
						end
						return true
					end
					-- Let other nav keys (left/right/up/down) fall through to the engine if no tab is open
				end
			end

			

			if HV.ActiveTab == "SEARCH" then
				local button = btn:lower()
				local editing = evType == "InputEventType_FirstPress" or evType == "InputEventType_Repeat"
				local instant = HV.InstantSearch()

				if button == "devicebutton_backspace" then
					if editing then
						if searchString == "" then
							focus.hold(event)
							MESSAGEMAN:Broadcast("SelectMusicTabChanged", {Tab = ""})
						else
							setSearchText(searchString:gsub("[^\128-\191][\128-\191]*$", ""), instant, true)
						end
					end
					return true
				end
				if button == "devicebutton_delete" then
					if editing then setSearchText("", instant, true) end
					return true
				end

				if isEnter then
					if evType == "InputEventType_FirstPress" then
						setSearchText(searchString, true)
						focus.hold(event)
						MESSAGEMAN:Broadcast("SelectMusicTabChanged", {Tab = ""})
					end
					return true
				end
				if logicalBtn == "Back" or button == "devicebutton_escape" then
					if evType == "InputEventType_FirstPress" then
						focus.hold(event)
						setSearchText("", true)
						MESSAGEMAN:Broadcast("SelectMusicTabChanged", {Tab = ""})
					end
					return true
				end

				if ctrl then
					if editing and evType == "InputEventType_FirstPress" and button == "devicebutton_v"
						and Arch and Arch.getClipboard then
						local clip = Arch.getClipboard()
						if clip then setSearchText(searchString .. clip:gsub("%c", " "), instant, true) end
					end
					return true
				end

				if editing and button:match("^devicebutton_") and not button:find("mouse", 1, true) then
					local shifted = INPUTFILTER:IsBeingPressed("left shift") or INPUTFILTER:IsBeingPressed("right shift")
					local character = event.char
					if not character or character == "" then character = DeviceBtnToChar(btn, shifted) end
					if character and character ~= "" and not character:find("%c") then
						setSearchText(searchString .. character, instant, true)
					end
					return true
				end
				return not button:find("mouse", 1, true)
			end

			-- 3. Key Presses (Global Shortcuts)
			if evType == "InputEventType_FirstPress" then
				if isEnter and HV.ActiveTab == "" and searchBlocksWheelSelection(screen) then return true end

				-- Close any active tab on Escape or Back
				if btn == "DeviceButton_escape" or logicalBtn == "Back" then
					if HV.ActiveTab ~= "" then
						focus.hold(event)
						MESSAGEMAN:Broadcast("SelectMusicTabChanged", {Tab = ""})
						return true
					end
				end

				-- Global Del to clear search
				if btn:lower() == "devicebutton_delete" then
					if searchString ~= "" or requestedSearch ~= "" then
						setSearchText("", true)
						return true
					end
				end
			end
			
			-- FALLBACK TRAPPING: PROFILE sinks everything internally.
			-- Other tabs handle their own sinking in their callbacks.
			if HV.ActiveTab == "PROFILE" then
				if IsMouseOverCentered(SCREEN_CENTER_X, SCREEN_CENTER_Y, overlayW, overlayH) then
					return true
				end
			end
			
			return false
		end)
	end
}


-- ============================================================
-- MUSIC WHEEL FIXED HIGHLIGHT
-- ============================================================
main_af[#main_af + 1] = Def.ActorFrame {
	Name = "MusicWheelHighlight",
	InitCommand = function(self)
		self:xy(SCREEN_WIDTH - 180, SCREEN_CENTER_Y)
		self.hv_holdLerp = 0
		self.hv_holdTarget = 0
	end,
	OnCommand = function(self)
		self:SetUpdateFunction(function(actor)
			actor.hv_holdLerp = actor.hv_holdLerp + (actor.hv_holdTarget - actor.hv_holdLerp) * 0.16
			actor:x(SCREEN_WIDTH - 180 + SCREEN_WIDTH * 0.32 * actor.hv_holdLerp)
		end)
	end,
	HVLeftMousePeekHoldChangedMessageCommand = function(self, params)
		local held = params and params.Held and params.Allowed
		self.hv_holdTarget = held and 1 or 0
	end,
	
	-- The main highlight box - fixed in center
	Def.Quad {
		InitCommand = function(self)
			self:zoomto(280, 40)
				:diffuse(accentColor):diffusealpha(0.12)
		end,
		OnCommand = function(self)
			self:playcommand("Pulse")
		end,
		PulseCommand = function(self)
			self:stoptweening()
				:linear(0.8):diffusealpha(0.2)
				:linear(0.8):diffusealpha(0.12)
				:queuecommand("Pulse")
		end
	},
	

}


-- ============================================================
-- MUSIC WHEEL HOLD TRANSFORM
-- ============================================================
main_af[#main_af + 1] = Def.ActorFrame {
	Name = "MusicWheelHoldTransformDriver",
	InitCommand = function(self)
		self.hv_holdLerp = 0
		self.hv_holdTarget = 0
	end,
	OnCommand = function(self)
		self:SetUpdateFunction(function(actor)
			actor.hv_holdLerp = actor.hv_holdLerp + (actor.hv_holdTarget - actor.hv_holdLerp) * 0.16
			ApplyNativeMusicWheelHoldTransform(actor.hv_holdLerp)
		end)
	end,
	HVLeftMousePeekHoldChangedMessageCommand = function(self, params)
		local held = params and params.Held and params.Allowed
		self.hv_holdTarget = held and 1 or 0
	end
}


-- ============================================================
-- PROFILE OVERLAY
-- ============================================================

-- ============================================================
-- PROFILE OVERLAY REDESIGN (Sidebar + Main)
-- ============================================================

-- ============================================================
-- PROFILE OVERLAY REDESIGN (Sidebar + Main)
-- ============================================================

local profileOverlay = Def.ActorFrame {
	Name = "ProfileOverlay",
	InitCommand = function(self)
		profileOverlayActor = self
		self.topPage = 1
		self.recentPage = 1
		self.currentSkillset = "Overall"
		self.isRecentMode = false
		self.isOnlineMode = true
		self:xy(SCREEN_CENTER_X, SCREEN_CENTER_Y):visible(false)
	end,
	
	-- Dark Background (Dim the rest of the screen)
	Def.Quad {
		InitCommand = function(self) self:zoomto(SCREEN_WIDTH, SCREEN_HEIGHT):diffuse(color("0,0,0,0.85")) end,
	},
	-- Main Panel BG
	Def.Quad { InitCommand = function(self) self:zoomto(overlayW, overlayH):diffuse(bgCard):diffusealpha(0.98) end },
	
	-- 1. Grade Sidebar (Far Left)
	Def.ActorFrame {
		Name = "GradeSidebar",
		InitCommand = function(self) self:x(-overlayW/2 + gradeSidebarW/2) end,
		Def.Quad { InitCommand = function(self) self:zoomto(gradeSidebarW, overlayH):diffuse(color("0.05,0.05,0.05,1")) end },
		
		-- Vertical Line Separator
		Def.Quad {
			InitCommand = function(self) 
				self:halign(1):x(gradeSidebarW/2):zoomto(1, overlayH):diffuse(accentColor):diffusealpha(0.3)
			end
		},

		LoadFont("Common Normal") .. {
			Text = THEME:GetString("ScreenSelectMusic", "Plays"),
			InitCommand = function(self) self:y(-overlayH/2 + 25):zoom(0.28):diffuse(brightText) end,
		},
		(function()
			local bands = GRADECOUNTERSTORAGE.profileGradeBands
			local rowSpacing = math.min(32, (overlayH - 80) / (#bands - 1))
			local rows = Def.ActorFrame {
				InitCommand = function(self) self:y(-overlayH/2 + 60) end,
			}
			for i, band in ipairs(bands) do
				local grade = band.grades[1]
				local y = (i - 1) * rowSpacing
				local function updateCount(self)
					self:settext(GRADECOUNTERSTORAGE[band.name] or 0)
				end
				rows[#rows + 1] = Def.ActorFrame {
					InitCommand = function(self) self:y(y) end,
					LoadFont("Common Normal") .. {
						Text = HV.GetGradeName(grade),
						InitCommand = function(self) self:y(-6):zoom(0.35):diffuse(HVColor.GetGradeColor(grade)) end,
					},
					LoadFont("Common Normal") .. {
						InitCommand = function(self) self:y(8):zoom(0.35):diffuse(mainText) end,
						BeginCommand = updateCount,
						UpdatePlayCountsCommand = updateCount,
					},
				}
			end
			return rows
		end)()
	},

	-- 2. Profile Sidebar (Middle)
	Def.ActorFrame {
		Name = "Sidebar",
		InitCommand = function(self) self:x(-overlayW/2 + gradeSidebarW + profileSidebarW/2) end,
		Def.Quad { InitCommand = function(self) self:zoomto(profileSidebarW, overlayH):diffuse(color("0.07,0.07,0.07,1")) end },
		
		-- Sidebar Separator with Glow
		Def.Quad {
			InitCommand = function(self) 
				self:halign(1):x(profileSidebarW/2):zoomto(1, overlayH):diffuse(accentColor):diffusealpha(0.3)
			end
		},
		Def.Quad {
			InitCommand = function(self) 
				self:halign(1):x(profileSidebarW/2):zoomto(4, overlayH):diffuse(accentColor):diffusealpha(0.1)
			end
		},
		
		-- Avatar / Info
		Def.ActorFrame {
			Name = "PlayerInfo",
			InitCommand = function(self) self:y(-overlayH/2 + 50) end,
			Def.Quad { Name = "Bg", InitCommand = function(self) self:zoomto(54, 54):diffuse(color("0,0,0,0.5")) end },
			Def.Sprite {
				Name = "Avatar",
				InitCommand = function(self) self:zoomto(54, 54):playcommand("UpdateAvatar") end,
				UpdateOverlaySkillsetsMessageCommand = function(self) self:playcommand("UpdateAvatar") end,
				AvatarChangedMessageCommand = function(self) self:playcommand("UpdateAvatar") end,
				UpdateAvatarCommand = function(self)
					local path = getAvatarPath()
					if path and path ~= "" and FILEMAN:DoesFileExist(path) then
						self:Load(path):visible(true)
					else
						self:visible(false)
					end
					self:scaletoclipped(54, 54)
				end
			},

			LoadFont("Common Normal") .. {
				InitCommand = function(self) self:y(40):zoom(0.4):diffuse(brightText) end,
				UpdateOverlaySkillsetsMessageCommand = function(self)
					local p = profileOverlayActor
					if p and not p.isOnlineMode then
						local prof = PROFILEMAN:GetProfile(PLAYER_1)
						if prof then
							self:settext(prof:GetDisplayName())
							return
						end
					end
					self:settext(HV.GetPlayerName())
				end
			},
			LoadFont("Common Normal") .. {
				Name = "Rating",
				InitCommand = function(self) self:y(54):zoom(0.55):diffuse(accentColor) end,
				UpdateOverlaySkillsetsMessageCommand = function(self)
					if not HV.ShowMSD() then self:visible(false); return end
					local val = 0
					local prof = PROFILEMAN:GetProfile(PLAYER_1)
					if DLMAN:IsLoggedIn() and profileOverlayActor.isOnlineMode then 
						val = DLMAN:GetSkillsetRating("Overall")
					elseif prof then
						val = prof:GetPlayerRating()
					end
					self:visible(true):settext(string.format("%.2f", val)):diffuse(HVColor.GetMSDRatingColor(val))
				end
			}
		},

		-- Vertical Skillset Tabs
		(function()
			local tabs = Def.ActorFrame {
				Name = "SkillsetTabs",
				InitCommand = function(self) self:y(-overlayH/2 + 140) end
			}
			for i, ss in ipairs(skillsets) do
				tabs[#tabs+1] = Def.ActorFrame {
					Name = "Tab_" .. ss,
					InitCommand = function(self) self:y((i-1) * skillsetTabH) end,
					Def.Quad {
						Name = "Bg",
						InitCommand = function(self) self:zoomto(profileSidebarW - 12, skillsetTabH - 4):halign(0):x(-profileSidebarW/2 + 6):diffuse(bgCard):diffusealpha(0.4) end
					},
					-- Active bar
					Def.Quad {
						Name = "ActiveBar",
						InitCommand = function(self) self:halign(0):x(-profileSidebarW/2 + 6):zoomto(3, skillsetTabH - 4):diffuse(accentColor):visible(false) end,
						UpdateOverlayUIActionCommand = function(self)
							local parent = profileOverlayActor
							if not parent then return end
							self:visible(parent.currentSkillset == ss and not parent.isRecentMode)
						end,
						UpdateOverlayUIMessageCommand = function(self) self:playcommand("UpdateOverlayUIAction") end
					},
					LoadFont("Common Normal") .. {
						Name = "Label",
						InitCommand = function(self) self:halign(0):x(-profileSidebarW/2 + 16):zoom(0.30):diffuse(subText):settext(ss:upper()) end
					},
					LoadFont("Common Normal") .. {
						Name = "Rank",
						InitCommand = function(self) self:halign(1):x(profileSidebarW/2 - 20):y(-6):zoom(0.3):diffuse(subText):visible(false) end,
						UpdateOverlaySkillsetsMessageCommand = function(self)
							if not HV.ShowMSD() or not DLMAN:IsLoggedIn() or not profileOverlayActor.isOnlineMode then
								self:visible(false)
								return
							end
							local rank = DLMAN:GetSkillsetRank(ss)
							if rank and rank > 0 then
								self:visible(true):settextf("#%d", rank):diffuse(HVColor.GetSkillsetRankColor(rank))
							else
								self:visible(false)
							end
						end
					},
					LoadFont("Common Normal") .. {
						Name = "Val",
						InitCommand = function(self) self:halign(1):x(profileSidebarW/2 - 20):y(0):zoom(0.4):diffuse(mainText) end,
						UpdateOverlaySkillsetsMessageCommand = function(self)
							if not HV.ShowMSD() then self:visible(false); return end
							self:y(profileOverlayActor.isOnlineMode and 6 or 0)
							local val = 0
							local prof = PROFILEMAN:GetProfile(PLAYER_1)
							if DLMAN:IsLoggedIn() and profileOverlayActor.isOnlineMode then 
								val = DLMAN:GetSkillsetRating(ss)
							elseif prof then
								if ss == "Overall" then val = prof:GetPlayerRating()
								else val = prof:GetPlayerSkillsetRating(i-2) or 0 end
							end
							self:visible(true):settext(string.format("%.2f", val)):diffuse(HVColor.GetMSDRatingColor(val))
						end
					},
					SetUpdateFunction = function(af)
						local mouseX = INPUTFILTER:GetMouseX()
						local mouseY = INPUTFILTER:GetMouseY()
						local parent = profileOverlayActor
						if not parent or not parent:GetVisible() then return end
						
						local sidebarX = SCREEN_CENTER_X - overlayW/2
						local profileSidebarX = sidebarX + gradeSidebarW
						
						local rx = mouseX - profileSidebarX
						local ry = mouseY - (SCREEN_CENTER_Y - overlayH/2)
						
						local over = rx >= 10 and rx <= profileSidebarW - 10 
						         and ry >= (140 + (i-1)*skillsetTabH - skillsetTabH/2) 
								 and ry <= (140 + (i-1)*skillsetTabH + skillsetTabH/2)
						
						local active = (parent.currentSkillset == ss) and not parent.isRecentMode
						if active then
							bg:diffuse(accentColor):diffusealpha(0.25)
						elseif over then
							bg:diffuse(color("0.3,0.3,0.3,0.3"))
						else
							bg:diffuse(bgCard):diffusealpha(0.4)
						end
					end
				}
			end
			return tabs
		end)(),
	},

	-- 3. Main Area (Scores - Far Right)
	Def.ActorFrame {
		Name = "MainArea",
		InitCommand = function(self) self:x(-overlayW/2 + gradeSidebarW + profileSidebarW + mainPartW/2) end,
		-- Area Header
		Def.ActorFrame {
			Name = "MainHeader",
			InitCommand = function(self) self:y(-overlayH/2 + 35) end,
			LoadFont("Common Normal") .. {
				InitCommand = function(self) self:halign(0):x(-mainPartW/2 + 30):zoom(0.5):diffuse(brightText) end,
				UpdateOverlayUIMessageCommand = function(self)
					local p = profileOverlayActor
					if not p then return end
					local modeText
					if p.isRecentMode then
						modeText = "RECENT SCORES (LOCAL)"
					else
						local src = (p.isOnlineMode and DLMAN:IsLoggedIn()) and "ONLINE" or "LOCAL"
						modeText = "TOP SCORES (" .. p.currentSkillset:upper() .. " · " .. src .. ")"
					end
					self:settext(modeText)
				end
			},
			-- Toggle Top/Recent Button
			Def.ActorFrame {
				Name = "ModeToggle",
				InitCommand = function(self) self:x(mainPartW/2 - 250) end,
				Def.Quad {
					Name = "Bg",
					InitCommand = function(self) 
						self:zoomto(100, 24):diffuse(accentColor):diffusealpha(0.15)
					end
				},
				LoadFont("Common Normal") .. {
					Name = "Txt",
					InitCommand = function(self) self:zoom(0.32):diffuse(brightText):settext("TOP / RECENT") end
				},
				SetUpdateFunction = function(af)
					local mouseX = INPUTFILTER:GetMouseX()
					local mouseY = INPUTFILTER:GetMouseY()
					local parent = profileOverlayActor
					if not parent or not parent:GetVisible() then return end
					local rx = mouseX - (SCREEN_CENTER_X - overlayW/2)
					local ry = mouseY - (SCREEN_CENTER_Y - overlayH/2)
					local over = rx >= sidebarW + mainPartW - 300 and rx <= sidebarW + mainPartW - 200
					         and ry >= 23 and ry <= 47
					local bg = af:GetChild("Bg")
					if parent.isRecentMode then
						bg:diffusealpha(0.4)
					elseif over then
						bg:diffusealpha(0.3)
					else
						bg:diffusealpha(0.15)
					end
				end
			},
			-- Toggle Online/Local Button
			Def.ActorFrame {
				Name = "SourceToggle",
				InitCommand = function(self) self:x(mainPartW/2 - 140) end,
				Def.Quad {
					Name = "Bg",
					InitCommand = function(self) 
						self:zoomto(100, 24):diffuse(accentColor):diffusealpha(0.15)
					end
				},
				LoadFont("Common Normal") .. {
					Name = "Txt",
					InitCommand = function(self) self:zoom(0.32) end,
					UpdateOverlayUIMessageCommand = function(self)
						local p = profileOverlayActor
						if p.isRecentMode then
							self:settext("ONLINE/LOCAL"):diffuse(dimText)
						else
							local active = p.isOnlineMode and DLMAN:IsLoggedIn()
							self:settext(active and "ONLINE" or "LOCAL"):diffuse(brightText)
						end
					end
				},
				SetUpdateFunction = function(af)
					local mouseX = INPUTFILTER:GetMouseX()
					local mouseY = INPUTFILTER:GetMouseY()
					local parent = profileOverlayActor
					if not parent or not parent:GetVisible() then return end
					local rx = mouseX - (SCREEN_CENTER_X - overlayW/2)
					local ry = mouseY - (SCREEN_CENTER_Y - overlayH/2)
					local over = rx >= sidebarW + mainPartW - 190 and rx <= sidebarW + mainPartW - 90
					         and ry >= 23 and ry <= 47
					local bg = af:GetChild("Bg")
					if parent.isRecentMode then
						bg:diffuse(dimText):diffusealpha(0.1)
					elseif (parent.isOnlineMode and DLMAN:IsLoggedIn()) or over then
						bg:diffuse(accentColor):diffusealpha(0.4)
					else
						bg:diffuse(accentColor):diffusealpha(0.15)
					end
				end
			},
			-- Upload All Button
			Def.ActorFrame {
				Name = "UploadBtn",
				InitCommand = function(self) self:x(mainPartW/2 - 40) end,
				Def.Quad {
					Name = "Bg",
					InitCommand = function(self) self:zoomto(80, 24):diffuse(color("0.1,0.4,0.1,0.5")) end
				},
				LoadFont("Common Normal") .. {
					InitCommand = function(self) self:zoom(0.32):diffuse(brightText):settext("UPLOAD ALL") end
				},
				SetUpdateFunction = function(af)
					local mouseX = INPUTFILTER:GetMouseX()
					local mouseY = INPUTFILTER:GetMouseY()
					local parent = profileOverlayActor
					if not parent or not parent:GetVisible() then return end
					local rx = mouseX - (SCREEN_CENTER_X - overlayW/2)
					local ry = mouseY - (SCREEN_CENTER_Y - overlayH/2)
					local over = rx >= sidebarW + mainPartW - 80 and rx <= sidebarW + mainPartW and ry >= 23 and ry <= 47
					local bg = af:GetChild("Bg")
					if over then
						bg:diffusealpha(0.8)
					else
						bg:diffusealpha(0.5)
					end
				end
			}
		},
		
		-- Score List Rows
		(function()
			local rows = Def.ActorFrame {
				Name = "ScoreListRows",
				InitCommand = function(self) self:y(-overlayH/2 + rowsYStart) end,
			}
			for i = 1, scorePageSize do
				rows[#rows+1] = Def.ActorFrame {
					Name = "Row_" .. i,
					InitCommand = function(self) self:y((i-1) * rowH) end,
					Def.Quad {
						Name = "Bg",
						InitCommand = function(self) 
							self:zoomto(mainPartW - 30, rowH - 4)
								:diffuse(color("0,0,0,0.4"))
								:fadeleft(0.1):faderight(0.1)
						end
					},
					-- Row border accent
					Def.Quad {
						Name = "Border",
						InitCommand = function(self)
							self:zoomto(mainPartW - 30, 1):valign(1):y(rowH/2 - 2)
								:diffuse(accentColor):diffusealpha(0.05)
						end
					},
					LoadFont("Common Normal") .. {
						Name = "SSR",
						InitCommand = function(self) self:halign(0):x(-mainPartW/2 + 30):zoom(0.4) end
					},
					LoadFont("Zpix normal") .. {
						Name = "Title",
						InitCommand = function(self) self:halign(0):x(-mainPartW/2 + 90):y(-5):zoom(0.35):diffuse(brightText):maxwidth(400 * 1.5) end
					},
					LoadFont("Common Normal") .. {
						Name = "Details",
						InitCommand = function(self) self:halign(0):x(-mainPartW/2 + 90):y(7):zoom(0.25):diffuse(dimText) end
					},
					LoadFont("Common Normal") .. {
						Name = "Percent",
						InitCommand = function(self) self:halign(1):x(mainPartW/2 - 220):zoom(0.42):diffuse(accentColor) end
					},
					LoadFont("Common Normal") .. {
						Name = "Validation",
						InitCommand = function(self) self:halign(1):x(mainPartW/2 - 30):zoom(0.28):diffuse(subText) end
					},
					-- Invalid Indicator
					LoadFont("Common Normal") .. {
						Name = "InvalidIndicator",
						InitCommand = function(self) self:halign(0):x(-mainPartW/2 + 30):y(-8):zoom(0.25):diffuse(color("1,0,0,1")):settext("[INVALID]"):visible(false) end
					},
					SetUpdateFunction = function(af)
						local parent = profileOverlayActor
						if not parent or not parent:GetVisible() then return end
						local mouseX = INPUTFILTER:GetMouseX()
						local mouseY = INPUTFILTER:GetMouseY()
						local rx = mouseX - (SCREEN_CENTER_X - overlayW/2)
						local ry = mouseY - (SCREEN_CENTER_Y - overlayH/2)
						local rowTop = rowsYStart + (i-1)*rowH - rowH/2
						local rowBottom = rowTop + rowH
						local scoreAreaX = gradeSidebarW + profileSidebarW
						local over = rx >= scoreAreaX + 10 and rx <= overlayW - 10 and ry >= rowTop and ry <= rowBottom
						local bg = af:GetChild("Bg")
						local score = af.currentScore
						
						if score and type(score) ~= "table" and not score:GetEtternaValid() then
							bg:diffuse(color("0.5,0.2,0.2,0.3"))
						else
							bg:diffuse(color("0,0,0,0.3"))
						end
						
						if over then
							bg:diffusealpha(0.6)
						end
					end,
					OverlayRowClickedMessageCommand = function(self, params)
						if params.index ~= i then return end
						local score = self.currentScore
						if not score then return end
						local ck = (type(score)=="table") and score.chartkey or score:GetChartKey()
						if not ck then return end
						local song = SONGMAN:GetSongByChartKey(ck)
						if song then
							local screen = SCREENMAN:GetTopScreen()
							if screen and screen.GetMusicWheel then
								screen:GetMusicWheel():SelectSong(song)
							end
						end
						MESSAGEMAN:Broadcast("SelectMusicTabChanged", {Tab = ""}) -- Close on select
					end,
					OverlayRowRightClickedMessageCommand = function(self, params)
						if params.index ~= i then return end
						local score = self.currentScore
						if not score or type(score) == "table" then return end
						score:ToggleEtternaValidation()
						HV.WheelData.Reset()
						MESSAGEMAN:Broadcast("HV_WheelScoresChanged")
						if score:GetEtternaValid() then
							ms.ok("Score validated")
						else
							ms.ok("Score invalidated")
						end
						MESSAGEMAN:Broadcast("UpdateOverlayUI")
					end
				}
			end
			return rows
		end)(),
		-- Footer Pagination
		LoadFont("Common Normal") .. {
			InitCommand = function(self) self:y(overlayH/2 - 25):zoom(0.35):diffuse(dimText) end,
			UpdateOverlayUIMessageCommand = function(self)
				local p = profileOverlayActor
				if not p then return end
				local cur = p.isRecentMode and p.recentPage or p.topPage
				self:settext("PAGE " .. cur .. " · CLICK TO FIND SONG · RIGHT-CLICK TO VALIDATE (LOCAL)")
			end
		}
	},

	UpdateAllScoresCommand = function(self)
		local rows = self:GetChild("MainArea"):GetChild("ScoreListRows")
		local pageField = self.isRecentMode and "recentPage" or "topPage"
		local start = (self[pageField] - 1) * scorePageSize
		local useOnlineScores = not self.isRecentMode and self.isOnlineMode and DLMAN:IsLoggedIn()

		if self.isRecentMode then
			SCOREMAN:SortRecentScoresForGame()
		elseif not useOnlineScores then
			SCOREMAN:SortSSRsForGame(self.currentSkillset)
		end

		local foundAnyOnPage = false
		for i = 1, scorePageSize do
			local row = rows:GetChild("Row_" .. i)
			local rank = start + i
			local score

			if self.isRecentMode then
				score = SCOREMAN:GetRecentScoreForGame(rank)
			elseif useOnlineScores then
				local ok, result = pcall(DLMAN.GetTopSkillsetScore, DLMAN, rank, self.currentSkillset)
				if ok then score = result end
			else
				score = SCOREMAN:GetTopSSRHighScoreForGame(rank, self.currentSkillset)
			end

			row.currentScore = score
			if score then
				foundAnyOnPage = true
				row:visible(true)
				local title, diff, rate, date, wife, ssr, metadata
				if type(score) == "table" then
					title = score.songName or "???"
					diff = ToEnumShortString(score.difficulty or "Beginner")
					rate = score.rate or 1.0
					date = score.date or "N/A"
					wife = score.wife or 0
					ssr = score.ssr or 0
					
					local ct = "Clear"
					
					-- If judgments are available in the table, show them
					if score.w1 then
						metadata = string.format("%s  |  %d/%d/%d/%d/%d/%d", THEME:GetString("ClearTypes", ct), score.w1, score.w2, score.w3, score.w4, score.w5, score.miss or 0)
					else
						metadata = string.format("%s  |  ONLINE", THEME:GetString("ClearTypes", ct))
					end
					if isProfileScoreInvalid(score) then
						metadata = "INVALID  |  " .. metadata
					end
				else
					local ck = score:GetChartKey()
					local thssong = SONGMAN:GetSongByChartKey(ck)
					local thssteps = SONGMAN:GetStepsByChartKey(ck)
					title = thssong and thssong:GetDisplayMainTitle() or "???"
					diff = thssteps and ToEnumShortString(thssteps:GetDifficulty()) or "?"
					rate = score:GetMusicRate()
					date = score:GetDate()
					wife = score:GetWifeScore()
					ssr = score:GetSkillsetSSR(self.isRecentMode and "Overall" or self.currentSkillset)
					
					local normalized = PREFSMAN:GetPreference("SortBySSRNormPercent")
					local judge = normalized and 4 or HV.Score.GetPlayedJudge(score)
					local counts = HV.Score.GetDisplayJudgments(score, normalized and 4 or nil)
					local ct = counts and THEME:GetString("ClearTypes", getDetailedClearType(score, counts)) or "-"
					local tally = counts and table.concat({counts.W1, counts.W2, counts.W3, counts.W4, counts.W5, counts.Miss}, "/") or "-"
					metadata = string.format("%s  |  %s  |  %s", judge and "J" .. judge or "-", ct, tally)
					if isProfileScoreInvalid(score) then
						metadata = "INVALID  |  " .. metadata
					end
				end
				
				local ssrLabel = row:GetChild("SSR")
				ssrLabel:settext(string.format("%.2f", ssr)):diffuse(HVColor.GetMSDRatingColor(ssr)):visible(HV.ShowMSD())
				row:GetChild("Title"):settext(title)
				row:GetChild("Details"):settext(string.format("%s · %.2fx · %s", diff, rate, date))
				
				local pLabel = row:GetChild("Percent")
				if wife >= 0.997 then
					pLabel:settext(string.format("%.4f%%", wife * 100))
				else
					pLabel:settext(string.format("%.2f%%", wife * 100))
				end
				
				-- Use centralized grade colors
				local grade = getWifeGradeTier(wife * 100)
				pLabel:diffuse(HVColor.GetGradeColor(grade))
				
				row:GetChild("Validation"):settext(metadata)
				
				local isInvalid = isProfileScoreInvalid(score)
				row:GetChild("InvalidIndicator"):visible(isInvalid)
				if isInvalid then
					row:GetChild("Bg"):diffuse(color("0.5,0.05,0.05,0.4"))
					row:GetChild("SSR"):diffuse(color("0.6,0.6,0.6,1"))
					row:GetChild("Title"):diffuse(color("0.6,0.6,0.6,1"))
				else
					row:GetChild("Bg"):diffuse(color("0,0,0,0.3"))
					-- SSR color is set by HVColor.GetMSDRatingColor in line above
					row:GetChild("Title"):diffuse(brightText)
				end
			else
				row:visible(false)
			end
		end

		-- Dynamic Clamping: If page is empty and not page 1, go back
		if not foundAnyOnPage and self[pageField] > 1 then
			self[pageField] = self[pageField] - 1
			self:playcommand("UpdateAllScores")
			return
		end
		
		self:playcommand("UpdateOverlaySkillsets")
		self:GetChild("MainArea"):playcommand("UpdateOverlayUI")
		self:GetChild("Sidebar"):playcommand("UpdateOverlayUI")
	end,

	OnlineUpdateMessageCommand = function(self)
		if HV.ActiveTab == "PROFILE" and self.isOnlineMode and not self.isRecentMode then
			self:playcommand("UpdateAllScores")
		end
	end,

	-- Core Logic Signals
	UpdateOverlayUIMessageCommand = function(self) self:playcommand("UpdateAllScores") end,
	SelectMusicTabChangedMessageCommand = function(self, params)
		local targetTab = params and params.Tab or ""
		if targetTab == "PROFILE" then
			self:visible(true):stoptweening()
				:diffusealpha(0):linear(0.15):diffusealpha(1)
			GRADECOUNTERSTORAGE:refreshProfile()
			self:GetChild("GradeSidebar"):playcommand("UpdatePlayCounts")
			self:playcommand("UpdateAllScores")
		else
			self:stoptweening():linear(0.1):diffusealpha(0):queuecommand("Hide")
		end
	end,
	HideCommand = function(self) self:visible(false) end,

	NextScorePageMessageCommand = function(self)
		if self.isRecentMode then self.recentPage = self.recentPage + 1
		else self.topPage = self.topPage + 1 end
		self:playcommand("UpdateAllScores")
	end,
	PrevScorePageMessageCommand = function(self)
		if self.isRecentMode then self.recentPage = math.max(1, self.recentPage - 1)
		else self.topPage = math.max(1, self.topPage - 1) end
		self:playcommand("UpdateAllScores")
	end
}

main_af[#main_af + 1] = profileOverlay

-- ============================================================
-- TOP HEADER (Search & Back)
-- ============================================================
local headerH = 40
main_af[#main_af + 1] = Def.ActorFrame {
	Name = "HeaderBar",
	InitCommand = function(self)
		self:xy(0, 0)
		self.hv_holdLerp = 0
		self.hv_holdTarget = 0
	end,
	OnCommand = function(self)
		self:SetUpdateFunction(function(actor)
			actor.hv_holdLerp = actor.hv_holdLerp + (actor.hv_holdTarget - actor.hv_holdLerp) * 0.16
			actor:y(-(headerH + 16) * actor.hv_holdLerp)
		end)
	end,
	HVLeftMousePeekHoldChangedMessageCommand = function(self, params)
		local held = params and params.Held and params.Allowed
		self.hv_holdTarget = held and 1 or 0
	end,
	
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0)
				:zoomto(SCREEN_WIDTH, headerH)
				:diffuse(color("0.04,0.04,0.04,1"))
		end
	},
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(1)
				:xy(0, headerH)
				:zoomto(SCREEN_WIDTH, 2)
				:diffuse(accentColor):diffusealpha(0.5)
		end
	},
	
	-- Back Button
	Def.ActorFrame {
		Name = "BtnBack",
		InitCommand = function(self) self:xy(0, 0) end,
		Def.Quad {
			Name = "Bg",
			InitCommand = function(self)
				self:halign(0):valign(0):zoomto(80, headerH):diffuse(color("0,0,0,0"))
			end
		},
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:halign(0.5):valign(0.5):xy(40, headerH / 2):zoom(0.4):diffuse(mainText):settext("< BACK")
			end
		}
	},
	
	-- Search Bar Frame
	Def.ActorFrame {
		Name = "SearchBar",
		InitCommand = function(self) self:xy(SCREEN_WIDTH / 2 - 150, 6) end,
		Def.Quad {
			Name = "Bg",
			InitCommand = function(self)
				self:halign(0):valign(0):zoomto(300, 28)
					:diffuse(color("0.1,0.1,0.1,1"))
			end,
			SelectMusicTabChangedMessageCommand = function(self, params)
				if params.Tab == "SEARCH" then
					self:diffuse(color("0.12,0.12,0.12,1"))
				else
					self:diffuse(color("0.1,0.1,0.1,1"))
				end
			end
		},
		-- Left accent line (glows when search is active)
		Def.Quad {
			Name = "AccentBorder",
			InitCommand = function(self)
				self:halign(0):valign(0):zoomto(2, 28)
					:diffuse(accentColor):diffusealpha(0)
			end,
			SelectMusicTabChangedMessageCommand = function(self, params)
				if params.Tab == "SEARCH" then
					self:diffusealpha(0.8)
				else
					self:diffusealpha(0)
				end
			end
		},
		Def.Sprite {
			Texture = THEME:GetPathG("", "search.png"),
			InitCommand = function(self)
				self:halign(0):valign(0.5):xy(8, 14):zoom(0.45):diffusealpha(0.7)
			end
		},
		LoadFont("Common Normal") .. {
			Name = "SearchPlaceholder",
			InitCommand = function(self)
				self:halign(0):valign(0.5):xy(32, 14):zoom(0.35):maxwidth(255 / 0.35)
					:diffuse(subText):settext("Click here to Search (or Ctrl + 4)")
			end,
			DrawSearchCommand = function(self, params)
				local focused = params.focused
				local query = focused and searchString or requestedSearch
				local failed = query ~= "" and query == searchResult.query and not searchResult.hasMatches
				local label = focused and query or ("Search: " .. query)
				if query == "" then
					label = focused and "Search songs" or "Click here to Search (or Ctrl + 4)"
				end
				self:settext(label):diffuse(query == "" and subText or brightText)
				local x = query == "" and 28 or 34 + self:GetZoomedWidth()
				local parent = self:GetParent()
				parent:GetChild("Cursor"):x(x):visible(focused)
				parent:GetChild("SearchStatus"):visible(failed)
			end,
			SelectMusicTabChangedMessageCommand = function(self, params)
				self:playcommand("DrawSearch", {focused = params.Tab == "SEARCH"})
			end,
			SearchQueryUpdatedMessageCommand = function(self)
				self:playcommand("DrawSearch", {focused = HV.ActiveTab == "SEARCH"})
			end,
		},
		LoadFont("Common Normal") .. {
			Name = "Cursor",
			InitCommand = function(self)
				self:halign(0):valign(0.5):xy(28, 14):zoom(0.35):diffuse(accentColor):settext("|"):visible(false)
			end,
		},
		LoadFont("Common Normal") .. {
			Name = "SearchStatus",
			InitCommand = function(self)
				self:halign(1):valign(0.5):xy(293, 23):zoom(0.25):diffuse(subText):settext("No matches"):visible(false)
			end,
		},
	},

	-- Nth Stage Display (Top Right)
	Def.ActorFrame {
		Name = "StageDisplayFrame",
		InitCommand = function(self)
			self:xy(SCREEN_WIDTH - 20, headerH / 2)
		end,
		OnCommand = function(self)
			self:playcommand("UpdateStageDisplay")
		end,
		UpdateStageDisplayCommand = function(self)
			local stageLabel = self:GetChild("StageDisplay")
			local sessionLabel = self:GetChild("SessionGradeDisplay")
			if not stageLabel or not sessionLabel then 
				return 
			end

			-- Update Stage Number
			local stageIdx = GAMESTATE:GetCurrentStageIndex() + 1
			local text = "STAGE " .. stageIdx
			if GAMESTATE.GetCurrentStage then
				local stage = GAMESTATE:GetCurrentStage()
				if stage == "Stage_Extra1" then text = "EXTRA STAGE"
				elseif stage == "Stage_Extra2" then text = "ENCORE EXTRA"
				end
			end
			stageLabel:settext(text)

			-- Update Session Grades
			local gradeParts = {}
			if GRADECOUNTERSTORAGE then
				local grades = {"session_AAAAA", "session_AAAA", "session_AAA", "session_AA", "session_A", "session_UnderA"}
				local labels = {"AAAAA", "AAAA", "AAA", "AA", "A", "<A"}
				for i, g in ipairs(grades) do
					local count = GRADECOUNTERSTORAGE[g] or 0
					if count > 0 then
						table.insert(gradeParts, labels[i] .. ": " .. count)
					end
				end
			end
			local gradeStr = #gradeParts > 0 and table.concat(gradeParts, "  |  ") or ""
			sessionLabel:settext(gradeStr)
		end,

		LoadFont("Common Normal") .. {
			Name = "StageDisplay",
			InitCommand = function(self)
				self:halign(1):valign(1):zoom(0.4):diffuse(accentColor)
			end,
		},
		LoadFont("Common Normal") .. {
			Name = "SessionGradeDisplay",
			InitCommand = function(self)
				self:halign(1):valign(0):y(2):zoom(0.3):diffuse(accentColor)
			end,
		}
	}
}

-- ============================================================
-- BOTTOM FOOTER & TAB BUTTONS
-- ============================================================
local tabs = {"PROFILE", "SCORES", "PLAYLISTS", "FILTERS", "TAGS", "GOALS", "RANDOM"}
local tabW = 80
local footerH = 40

main_af[#main_af + 1] = Def.ActorFrame {
	Name = "FooterBar",
	InitCommand = function(self)
		self:xy(0, SCREEN_HEIGHT - footerH)
		self.hv_holdLerp = 0
		self.hv_holdTarget = 0
	end,
	OnCommand = function(self)
		self:SetUpdateFunction(function(actor)
			actor.hv_holdLerp = actor.hv_holdLerp + (actor.hv_holdTarget - actor.hv_holdLerp) * 0.16
			actor:y(SCREEN_HEIGHT - footerH + (footerH + 16) * actor.hv_holdLerp)
		end)
	end,
	HVLeftMousePeekHoldChangedMessageCommand = function(self, params)
		local held = params and params.Held and params.Allowed
		self.hv_holdTarget = held and 1 or 0
	end,
	
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0)
				:zoomto(SCREEN_WIDTH, footerH)
				:diffuse(color("0.04,0.04,0.04,1"))
		end
	},
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0)
				:zoomto(SCREEN_WIDTH, 2)
				:diffuse(accentColor):diffusealpha(0.5)
		end
	},
	
	-- Time Display (Right aligned)
	Def.ActorFrame {
		Name = "TimeFrame",
		InitCommand = function(self) self:xy(SCREEN_WIDTH - 20, footerH / 2) end,

		-- Session Time (Wasted human cycles)
		LoadFont("Common Normal") .. {
			Name = "SessionTime",
			InitCommand = function(self)
				self:halign(1):y(10):zoom(0.32):diffuse(dimText)
			end,
			OnCommand = function(self) self:queuecommand("Tick") end,
			TickCommand = function(self)
				local secs = GetTimeSinceStart()
				local h = math.floor(secs / 3600)
				local m = math.floor((secs % 3600) / 60)
				local s = math.floor(secs % 60)
				self:settextf("Wasted Human Cycles: %02d:%02d:%02d", h, m, s)
				self:sleep(1):queuecommand("Tick")
			end
		},

		-- Real Time Clock
		LoadFont("Common Normal") .. {
			Name = "Clock",
			InitCommand = function(self)
				self:halign(1):y(-6):zoom(0.5):diffuse(mainText)
			end,
			OnCommand = function(self) self:queuecommand("Tick") end,
			TickCommand = function(self)
				self:settext(os.date("%H:%M:%S"))
				self:sleep(1):queuecommand("Tick")
			end
		}
	}
}

-- Create Tab Buttons on Footer
for i, tabName in ipairs(tabs) do
	main_af[#main_af + 1] = Def.ActorFrame {
		Name = "FooterTab_" .. tabName,
		InitCommand = function(self)
			self:xy(10 + (i - 1) * tabW, SCREEN_HEIGHT - footerH)
			self.hv_holdLerp = 0
			self.hv_holdTarget = 0
		end,
		OnCommand = function(self)
			self:SetUpdateFunction(function(actor)
				actor.hv_holdLerp = actor.hv_holdLerp + (actor.hv_holdTarget - actor.hv_holdLerp) * 0.16
				actor:y(SCREEN_HEIGHT - footerH + (footerH + 16) * actor.hv_holdLerp)
			end)
		end,
		HVLeftMousePeekHoldChangedMessageCommand = function(self, params)
			local held = params and params.Held and params.Allowed
			self.hv_holdTarget = held and 1 or 0
		end,
		
		Def.Quad {
			Name = "Bg",
			InitCommand = function(self)
				self:halign(0):valign(0)
					:zoomto(tabW, footerH)
					:diffuse(accentColor):diffusealpha(0)
			end,
			SelectMusicTabChangedMessageCommand = function(self, params)
				if params.Tab == tabName:upper() then
					self:stoptweening():linear(0.15):diffusealpha(0.25)
				else
					self:stoptweening():linear(0.15):diffusealpha(0)
				end
			end
		},
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:halign(0.5):valign(0.5)
					:xy(tabW / 2, footerH / 2)
					:zoom(0.35):diffuse(mainText)
					:settext(tabName)
			end,
			SelectMusicTabChangedMessageCommand = function(self, params)
				if params.Tab == tabName:upper() then
					self:stoptweening():smooth(0.15):zoom(0.4):diffuse(brightText)
				else
					self:stoptweening():smooth(0.15):zoom(0.35):diffuse(mainText)
				end
			end
		}
	}
end

-- ============================================================
-- MASTER INPUT SINK & TAB MANAGEMENT
-- ============================================================
-- (Relocated to bottom to ensure decoration callbacks are prioritized)

-- 4. Song Preview Logic (Ported from spawncamping-wallhack)
-- Loaded before other layers to ensure its message listeners clear state first.
main_af[#main_af + 1] = LoadActor("bgm.lua")

main_af[#main_af + 1] = LoadActor("../ScreenChartPreview overlay/default.lua")

-- Load Decoration Overlays (Initially hidden, using standard Toggle[NAME]Overlay messages)
local decorOverlays = {"scores", "filters", "playlists", "tags", "goals"}
for _, name in ipairs(decorOverlays) do
	local panel, onInput = LoadActor("../ScreenSelectMusic decorations/" .. name .. ".lua", focus)
	main_af[#main_af + 1] = panel
	if name == "filters" then filterInput = onInput end
end

main_af[#main_af + 1] = LoadActor("../_cursor")


main_af[#main_af + 1] = Def.ActorFrame {
	Name = "MasterInputSink",
	BeginCommand = function(self)
		local preview = self:GetParent():GetChild("ChartPreviewRoot")
		if not preview then return end

		focus.bind(function(event)
			local btn = event.DeviceInput.button or ""
			local button = event.GameButton or event.button
			local firstPress = event.type == "InputEventType_FirstPress"
			local activeTab = HV.ActiveTab or ""

			if btn == "DeviceButton_space" and activeTab == "" then
				if firstPress then preview:playcommand("ToggleChartPreview") end
				return true
			end
			if HV.ChartPreviewActive then
				if firstPress and (button == "Back" or button == "Start" or btn == "DeviceButton_escape") then
					preview:playcommand("CloseChartPreview")
				else
					preview:playcommand("PreviewInput", event)
				end
				return true
			end
			return activeTab ~= "" and not btn:match("mouse")
		end)
	end
}

return main_af
