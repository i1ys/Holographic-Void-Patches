local ThemePrefs = HV.LegacyPrefs

-- Global State Initialization
HV.TitleState = HV.TitleState or {}
HV.TitleState.player = HV.TitleState.player or { song = nil, paused = true, offset = 0, lastStart = 0, duration = 0, history = {}, lastToggleAt = 0 }
HV.TitleState.selectedProfile = HV.TitleState.selectedProfile or 0
HV.TitleState.showAlarmPopup = HV.TitleState.showAlarmPopup or false

local accentColor = HVColor.Accent
local dimText = color("0.45,0.45,0.45,1")
local subText = color("0.65,0.65,0.65,1")
local brightText = color("1,1,1,1")

local PREF_DEFS = {
	HV_AlarmActive = { Values = {"false", "true"}, Choices = {"Off", "On"} },
	HV_AlarmType = { Values = {"Time", "Timer"}, Choices = {"Time", "Timer"} },
	HV_AlarmShowInGameplay = { Values = {"false", "true"}, Choices = {"Off", "On"} },
}

local alarmRows = {
	{ Name = "ACTIVE", Pref = "HV_AlarmActive" },
	{ Name = "MODE", Pref = "HV_AlarmType" },
	{ Name = "GAMEPLAY ALERT", Pref = "HV_AlarmShowInGameplay" },
}

local function cyclePref(name)
	local pref = PREF_DEFS[name]
	if not pref then return end
	local current = tostring(ThemePrefs.Get(name))
	local idx = 1
	for i, v in ipairs(pref.Values) do
		if tostring(v) == current then idx = i break end
	end
	idx = (idx % #pref.Values) + 1
	ThemePrefs.Set(name, pref.Values[idx])
	ThemePrefs.Save()
	MESSAGEMAN:Broadcast("ThemePrefChanged", {Name = name})

	-- Special logic for Alarm Timer
	if name == "HV_AlarmActive" then
		local active = ThemePrefs.Get("HV_AlarmActive")
		if (active == "true" or active == true) and ThemePrefs.Get("HV_AlarmType") == "Timer" then
			local duration = tonumber(ThemePrefs.Get("HV_AlarmTimerDuration")) or 5
			HV.AlarmTimerDuration = duration * 60
			HV.AlarmTimerStartTime = GetTimeSinceStart()
			HV.AlarmTimerSeconds = duration * 60
		end
	elseif name == "HV_AlarmType" then
		-- If switching TO Timer while active, start it
		local active = ThemePrefs.Get("HV_AlarmActive")
		if (active == "true" or active == true) and ThemePrefs.Get("HV_AlarmType") == "Timer" then
			local duration = tonumber(ThemePrefs.Get("HV_AlarmTimerDuration")) or 5
			HV.AlarmTimerDuration = duration * 60
			HV.AlarmTimerStartTime = GetTimeSinceStart()
			HV.AlarmTimerSeconds = duration * 60
		end
	end
end

local isGlowEnabled = tostring(ThemePrefs.Get("HV_EnableGlow")) == "true"

local function getSelectedGamemodeLabel()
	local game = GAMESTATE:GetCurrentGame()
	local gameName = (game and game:GetName() or "unknown"):upper()
	local style = GAMESTATE:GetCurrentStyle()
	if style and style.GetName then
		local styleName = tostring(style:GetName() or ""):upper()
		if styleName ~= "" then
			return "Current Gamemode: " .. gameName .. " · " .. styleName
		end
	end
	return "Current Gamemode: " .. gameName
end

-- Hitbox Constants
local pBtnW = 260
local pBtnH = 70
local pBtnCX = (SCREEN_RIGHT - 10) - pBtnW/2
local pBtnCY = 10 + pBtnH/2
local maxCompactProfiles = 4
local compactRowH = 40

-- Media Player Constants
local mpBarH = 40
local mpBarY = SCREEN_BOTTOM - mpBarH/2
local mpBtnSize = 24
local mpPrevX = SCREEN_LEFT + 28
local mpPlayX = SCREEN_LEFT + 60
local mpNextX = SCREEN_LEFT + 92
local mpBtnY = mpBarY
local mpPlayPath = THEME:GetPathG("", "mp_play")
local mpPausePath = THEME:GetPathG("", "mp_pause")
local mpPrevPath = THEME:GetPathG("", "mp_prev")
local mpNextPath = THEME:GetPathG("", "mp_next")
local vizH = 32
local vizY = mpBarY - (mpBarH / 2)

local t = Def.ActorFrame {
	InitCommand = function(self)
		HV.TitleState.keyboardIndex = HV.TitleState.keyboardIndex or 1
		self:SetUpdateFunction(function(af)
			local screen = SCREENMAN:GetTopScreen()
			if screen then
				local sName = screen:GetName()
				local isSelect = sName == "ScreenSelectProfile"
				local prof = af:GetChild("ProfileChip")
				local online = af:GetChild("OnlineProfileChip")
				local mp = af:GetChild("MediaPlayer")
				local viz = af:GetChild("MediaVisualizer")
				local quotes = af:GetChild("QuotesOverlay")
				if prof then prof:visible(not isSelect) end
				if online then online:visible(not isSelect) end
				if mp then mp:visible(not isSelect) end
				if viz then viz:visible(not isSelect) end
				if quotes then quotes:visible(not isSelect) end
			end
			
			local virtualX = INPUTFILTER:GetMouseX()
			local virtualY = INPUTFILTER:GetMouseY()

			-- Profile Chip Hover
			local overProfile = virtualX >= pBtnCX - pBtnW/2 and virtualX <= pBtnCX + pBtnW/2
							and virtualY >= pBtnCY - pBtnH/2 and virtualY <= pBtnCY + pBtnH/2
			
			local prof = af:GetChild("ProfileChip")
			if prof then
				local bg = prof:GetChild("Bg")
				if overProfile and isGlowEnabled then
					bg:glow(accentColor)
				else
					bg:glow(color("0,0,0,0"))
				end
			end

			-- Always derive visual highlight from actual scroller/engine selection.
			local selectedIndex = HV.TitleState.keyboardIndex or 1
			local screen = SCREENMAN:GetTopScreen()
			if screen then
				local scroller = screen:GetChild("Scroller")
				if scroller then
					local destItem = scroller:GetDestinationItem()
					if destItem ~= nil then
						selectedIndex = destItem + 1
					else
						local currItem = scroller:GetCurrentItem()
						if currItem ~= nil then
							selectedIndex = currItem + 1
						end
					end
				end
			end

			HV.TitleState.keyboardIndex = selectedIndex

			-- Update custom label colors based on selection state
			for i = 1, 6 do
				local lbl = af:GetChild("ChoiceLabel" .. i)
				if lbl then
					if i == selectedIndex then
						lbl:stoptweening():decelerate(0.15):zoom(0.7):diffuse(color("1,1,1,1"))
					else
						lbl:stoptweening():decelerate(0.15):zoom(0.6):diffuse(color("0.5,0.5,0.5,1"))
					end
				end
			end
		end)
	end,
	ThemePrefChangedMessageCommand = function(self)
		isGlowEnabled = tostring(ThemePrefs.Get("HV_EnableGlow")) == "true"
		self:playcommand("Refresh")
	end,
	-- ... (rest of the system commands)
	BeginCommand = function(self)
		if not DLMAN:IsLoggedIn() then
			local user = ThemePrefs.Get("HV_Username")
			local token = ThemePrefs.Get("HV_PasswordToken")
			if user and token and user ~= "" and token ~= "" then
				DLMAN:LoginWithToken(user, token)
			end
		end
	end,
	EndCommand = function(self)
		SCREENMAN:set_input_redirected(PLAYER_1, false)
		SCREENMAN:set_input_redirected(PLAYER_2, false)
		-- Clear song history on screen exit
		if HV.TitleState and HV.TitleState.player then
			HV.TitleState.player.history = {}
		end
	end,
	MenuUpCommand = function(self)
		HV.TitleState.keyboardIndex = HV.TitleState.keyboardIndex - 1
		if HV.TitleState.keyboardIndex < 1 then HV.TitleState.keyboardIndex = 6 end
	end,
	MenuDownCommand = function(self)
		HV.TitleState.keyboardIndex = HV.TitleState.keyboardIndex + 1
		if HV.TitleState.keyboardIndex > 6 then HV.TitleState.keyboardIndex = 1 end
	end,
	Player1UpCommand = function(self)
		HV.TitleState.keyboardIndex = HV.TitleState.keyboardIndex - 1
		if HV.TitleState.keyboardIndex < 1 then HV.TitleState.keyboardIndex = 6 end
	end,
	Player1DownCommand = function(self)
		HV.TitleState.keyboardIndex = HV.TitleState.keyboardIndex + 1
		if HV.TitleState.keyboardIndex > 6 then HV.TitleState.keyboardIndex = 1 end
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
		ms.ok(THEME:GetString("ScreenTitleMenu", "LoginFailed"))
	end,
	LogOutMessageCommand = function(self)
		-- Only clear username on manual logout to preserve auto-login token
	end,
	TriggerLoginFlowMessageCommand = function(self)
		Trace("[HV] TriggerLoginFlow received in Title")
		easyInputStringOKCancel(
			THEME:GetString("ScreenTitleMenu", "EmailPrompt"), 255, false,
			function(email)
				if email ~= "" then
					self.tempEmail = email
					self:sleep(0.02):queuecommand("LoginStep2")
				else
					ms.ok(THEME:GetString("ScreenTitleMenu", "LoginCanceled"))
				end
			end,
			function() ms.ok(THEME:GetString("ScreenTitleMenu", "LoginCanceled")) end
		)
	end,
	
	LoginStep2Command = function(self)
		easyInputStringOKCancel(
			THEME:GetString("ScreenTitleMenu", "PasswordPrompt"), 255, true,
			function(password)
				if password ~= "" then
					Trace("[HV] Attempting DLMAN:Login for " .. tostring(self.tempEmail))
					DLMAN:Login(self.tempEmail, password)
				else
					ms.ok(THEME:GetString("ScreenTitleMenu", "LoginCanceled"))
				end
			end,
			function() ms.ok(THEME:GetString("ScreenTitleMenu", "LoginCanceled")) end
		)
	end
}


-- Jukebox Helper Functions
local function jukeboxPlaySong(song)
	local p = HV.TitleState.player
	if not song then return end
	local mp = song:GetMusicPath()
	if not mp then return end
	p.song = song
	p.offset = 0
	p.duration = song:MusicLengthSeconds()
	local start = 0
	SOUND:PlayMusicPart(mp, start, p.duration)
	p.lastStart = GetTimeSinceStart()
	p.paused = false
	MESSAGEMAN:Broadcast("PlayStatusChanged")
	MESSAGEMAN:Broadcast("ResetVisualizer")
end

local function canTogglePlayback()
	local p = HV.TitleState.player
	local now = GetTimeSinceStart()
	if now - (p.lastToggleAt or 0) < 0.08 then return false end
	p.lastToggleAt = now
	return true
end

local function jukeboxPause()
	local p = HV.TitleState.player
	if p.paused or not p.song then return end
	p.offset = p.offset + (GetTimeSinceStart() - p.lastStart)
	SOUND:StopMusic()
	p.paused = true
	MESSAGEMAN:Broadcast("PlayStatusChanged")
end

local function jukeboxResume()
	local p = HV.TitleState.player
	if not p.paused or not p.song then return end
	local mp = p.song:GetMusicPath()
	if not mp then return end
	local start = p.offset
	local len = p.duration - p.offset
	if len <= 0 then len = p.duration; p.offset = 0; start = 0 end
	SOUND:PlayMusicPart(mp, start, len)
	p.lastStart = GetTimeSinceStart()
	p.paused = false
	MESSAGEMAN:Broadcast("PlayStatusChanged")
	MESSAGEMAN:Broadcast("ResetVisualizer")
end

local function jukeboxNext()
	local p = HV.TitleState.player
	-- Push current song to history
	if p.song then
		p.history[#p.history + 1] = p.song
	end

	local allSongs = SONGMAN:GetAllSongs()
	if #allSongs > 0 then
		local newSong = allSongs[math.random(#allSongs)]
		if newSong then jukeboxPlaySong(newSong) end
	end
end

local function jukeboxPrev()
	local p = HV.TitleState.player
	if #p.history == 0 then return end
	local prevSong = table.remove(p.history)
	if prevSong then jukeboxPlaySong(prevSong) end
end

local function getPlayerStateKey(p)
	if not p.song then return "no_track" end
	if p.paused then return "paused" end
	return "playing"
end

local function jukeboxToggle()
	if not canTogglePlayback() then return end
	local p = HV.TitleState.player
	if not p.song then
		jukeboxNext()
	elseif p.paused then
		jukeboxResume()
	else
		jukeboxPause()
	end
end

--- Title Menu Text Labels (Custom rendering to bypass engine scroller text issues)
local choiceLabels = {"START", "MULTI", "COLOR THEME", "PACK DOWNLOADER", "OPTIONS", "EXIT"}
local choiceKeys = {"Start", "Multi", "ColorTheme", "PackDownloader", "Options", "Quit"}
for i, label in ipairs(choiceLabels) do
	local iy = SCREEN_CENTER_Y + 40 * (i - ((#choiceLabels + 1) / 2))
	t[#t + 1] = LoadFont("Common Normal") .. {
		Name = "ChoiceLabel" .. i,
		Text = label,
		InitCommand = function(self)
			self:xy(SCREEN_CENTER_X, iy):zoom(0.6):diffuse(color("0.5,0.5,0.5,1")):uppercase(true)
		end
	}
end

-- Read Author from ThemeInfo.ini
local themeAuthor = "Unknown"
local themeName = THEME:GetCurThemeName()
local paths = {
	"Themes/" .. themeName .. "/ThemeInfo.ini",
	"ThemeInfo.ini"
}

if THEME.GetCurrentThemeDirectory then
	table.insert(paths, 1, THEME:GetCurrentThemeDirectory() .. "ThemeInfo.ini")
end

for _, path in ipairs(paths) do
	local info = IniFile.ReadFile(path)
	if info and info["ThemeInfo"] and info["ThemeInfo"]["Author"] then
		themeAuthor = info["ThemeInfo"]["Author"]
		break
	end
end

t[#t + 1] = Def.ActorFrame {
	Name = "LogoContainer",
	InitCommand=function(self) self:xy(SCREEN_CENTER_X, SCREEN_TOP+50) end,
	-- Selected gamemode
	LoadFont("Common Normal") .. {
		Name = "GamemodeLabel",
		InitCommand = function(self)
			self:y(-24):zoom(0.4):diffuse(subText)
		end,
		OnCommand = function(self)
			self:playcommand("Set")
		end,
		CurrentGameChangedMessageCommand = function(self)
			self:playcommand("Set")
		end,
		CurrentStyleChangedMessageCommand = function(self)
			self:playcommand("Set")
		end,
		SetCommand = function(self)
			self:settext(getSelectedGamemodeLabel())
		end
	},
	-- Main Text
	LoadFont("Common Large") .. {
		Text="HOLOGRAPHIC VOID",
		InitCommand=function(self) self:zoom(0.75):diffuse(brightText) end
	},
	-- Author Text
	LoadFont("Common Normal") .. {
		Text="by " .. themeAuthor,
		InitCommand=function(self) self:y(25):zoom(0.4):diffuse(subText) end
	},
}

-- Load Shared Background Particles
t[#t + 1] = LoadActor("../_particles.lua")

t[#t + 1] = Def.ActorFrame {
	InitCommand = function(self) self:SetUpdateFunction(function(af)
		af:GetChild("D"):settextf("%04d-%02d-%02d", Year(), MonthOfYear()+1, DayOfMonth())
		af:GetChild("T"):settextf("%02d:%02d:%02d", Hour(), Minute(), Second())
		
		local srv = af:GetChild("S")
		if IsNetSMOnline() then
			srv:settext(THEME:GetString("ScreenTitleMenu", "Server") .. " · " .. (GetServerName() or THEME:GetString("ScreenTitleMenu", "Connected"))):diffuse(color("0.65,1,0.72,1"))
		else
			srv:settext(THEME:GetString("ScreenTitleMenu", "Server") .. " · " .. THEME:GetString("ScreenTitleMenu", "Offline")):diffuse(dimText)
		end

		local alrm = af:GetChild("A")
		local active = ThemePrefs.Get("HV_AlarmActive")
		if active == "true" or active == true then
			local type = ThemePrefs.Get("HV_AlarmType")
			if type == "Time" then
				alrm:settext("ALARM · " .. (ThemePrefs.Get("HV_AlarmTime") or "12:00")):diffuse(accentColor)
			else
				local s = HV.AlarmTimerSeconds or 0
				if s > 0 then
					alrm:settext("TIMER · " .. SecondsToMSS(s)):diffuse(accentColor)
				else
					alrm:settext("TIMER · " .. (ThemePrefs.Get("HV_AlarmTimerDuration") or 5) .. "M"):diffuse(accentColor)
				end
			end
		else
			alrm:settext("ALARM · OFF"):diffuse(dimText)
		end
	end) end,
	LoadFont("Common Normal") .. { Name="D", InitCommand=function(self) self:xy(SCREEN_LEFT+16, SCREEN_TOP+14):halign(0):zoom(0.5):diffuse(subText) end },
	LoadFont("Common Normal") .. { Name="T", InitCommand=function(self) self:xy(SCREEN_LEFT+16, SCREEN_TOP+30):halign(0):zoom(0.35):diffuse(subText) end },
	LoadFont("Common Normal") .. { Name="S", InitCommand=function(self) self:xy(SCREEN_LEFT+16, SCREEN_TOP+44):halign(0):zoom(0.3):diffuse(dimText) end },
	LoadFont("Common Normal") .. { Name="A", InitCommand=function(self) self:xy(SCREEN_LEFT+16, SCREEN_TOP+58):halign(0):zoom(0.3):diffuse(dimText) end },
	
	-- Online Profile Display (Under Alarm)
	Def.ActorFrame {
		Name = "OnlineProfileChip",
		InitCommand = function(self)
			self:xy(SCREEN_LEFT + 16, SCREEN_TOP + 100):visible(false)
			self:SetUpdateFunction(function(af)
				local loggedIn = DLMAN:IsLoggedIn()
				af:visible(loggedIn)
				if not loggedIn then return end
				
				local nameTxt = af:GetChild("Name")
				local ratingTxt = af:GetChild("Rating")
				local rankTxt = af:GetChild("Rank")
				
				nameTxt:settext(DLMAN:GetUsername())
				local r = DLMAN:GetSkillsetRating("Overall")
				local showStats = HV.ShowProfileStats()
				ratingTxt:visible(showStats and HV.ShowMSD()):settextf("%.2f", r):diffuse(HVColor.GetMSDRatingColor(r))
				
				if rankTxt then
					local rank = DLMAN:GetSkillsetRank("Overall")
					rankTxt:visible(showStats and HV.ShowMSD() and rank > 0):settextf("#%d", rank):diffuse(HVColor.GetSkillsetRankColor(rank))
				end
			end)
		end,
		
		Def.Quad {
			InitCommand = function(self)
				self:halign(0):zoomto(pBtnW, compactRowH):diffuse(color("0.08,0.22,0.1,0.85")):diffuseleftedge(accentColor)
			end
		},
		LoadFont("Common Normal") .. {
			Name = "Name",
			InitCommand = function(self) self:xy(10, -6):halign(0):zoom(0.4):diffuse(brightText) end
		},
		LoadFont("Common Large") .. {
			Name = "Rating",
			InitCommand = function(self) self:xy(8, 8):halign(0):zoom(0.50):diffuse(dimText) end
		},
		LoadFont("Common Normal") .. {
			Name = "Rank",
			InitCommand = function(self) self:xy(72, 10):halign(0):zoom(0.45):diffuse(dimText) end
		}
	}
}

-- Profile chip (Top right) + Inline Profile List
local compactRowW = pBtnW

t[#t + 1] = Def.ActorFrame {
	Name = "ProfileChip",
	InitCommand = function(self)
		self:xy(SCREEN_RIGHT - 10, 10 + pBtnH/2)
		self:SetUpdateFunction(function(af)
			if not af then return end
			local status = af:GetChild("Status")
			local name = af:GetChild("Name")
			local rating = af:GetChild("Rating")
			local rank = af:GetChild("Rank")
			local avatar = af:GetChild("Avatar")
			local bg = af:GetChild("Bg")

			-- Skip update if essential children are missing
			if not status or not name or not rating or not rank or not avatar then return end

			local numLocal = PROFILEMAN:GetNumLocalProfiles()
			local selIdx = HV.TitleState.selectedProfile or 0
			-- Clamp selection
			if selIdx >= numLocal then selIdx = 0; HV.TitleState.selectedProfile = 0 end

			-- Main Chip: Always show local profile selected via TitleState
			status:settext(THEME:GetString("ScreenTitleMenu", "Local")):diffuse(dimText)
			if numLocal > 0 then
				local profile = PROFILEMAN:GetLocalProfileFromIndex(selIdx)
				local profileID = PROFILEMAN:GetLocalProfileIDFromIndex(selIdx)
				if profile then
					name:settext(profile:GetDisplayName())
					local r = profile:GetPlayerRating()
					local showStats = HV.ShowProfileStats()
					rating:visible(showStats and HV.ShowMSD()):settextf("%.2f", r):diffuse(HVColor.GetMSDRatingColor(r))
					rank:visible(false)

					local path = getAssetPathFromProfileID("avatar", profileID)
					if path and path ~= avatar.lastPath then
						avatar:Load(path)
						avatar:scaletoclipped(50, 50)
						avatar.lastPath = path
					end
					avatar:visible(true)
				else
					name:settext(THEME:GetString("ScreenTitleMenu", "NoProfile"))
					rating:visible(false)
					rank:visible(false)
					avatar:visible(false)
				end
			else
				name:settext(THEME:GetString("ScreenTitleMenu", "GuestPlayer"))
				rating:visible(false)
				rank:visible(false)
				avatar:visible(false)
			end
			if bg then bg:diffuse(color("0.12,0.12,0.12,0.85")) end

			-- Update compact profile rows (other local profiles)
			for ci = 0, maxCompactProfiles - 1 do
				local row = af:GetChild("CompactRow_" .. ci)
				if row then
					if numLocal <= 1 then
						row:visible(false)
					else
						-- Map compact row index to profile index (skip selected)
						local profileIdx = ci
						if profileIdx >= selIdx then profileIdx = profileIdx + 1 end
						if profileIdx < numLocal then
							row:visible(true)
							local p = PROFILEMAN:GetLocalProfileFromIndex(profileIdx)
							local pid = PROFILEMAN:GetLocalProfileIDFromIndex(profileIdx)
							local cName = row:GetChild("CName")
							local cRating = row:GetChild("CRating")
							local cAvatar = row:GetChild("CAvatar")
							local cBg = row:GetChild("CBg")
							if cName and p then cName:settext(p:GetDisplayName()) end -- Compact rows still show local profile name
							if cRating and p then
								local r = p:GetPlayerRating()
								local showStats = HV.ShowProfileStats()
								cRating:visible(showStats and HV.ShowMSD()):settextf("%.2f", r):diffuse(HVColor.GetMSDRatingColor(r))
							end
							if cAvatar and pid then
								local apath = getAssetPathFromProfileID("avatar", pid)
								if apath and apath ~= cAvatar.lastPath then
									cAvatar:Load(apath)
									cAvatar:scaletoclipped(32, 32)
									cAvatar.lastPath = apath
								end
							end
							-- Store the actual profile index for click handling
							row.profileIdx = profileIdx
						else
							row:visible(false)
						end
					end
				end
			end
		end)
	end,
	Def.Quad { Name="Bg", InitCommand=function(self) self:x(-pBtnW/2):zoomto(pBtnW, pBtnH) end },
	LoadFont("Common Normal") .. { Name="Status", InitCommand=function(self) self:xy(-pBtnW + 10, -22):halign(0):zoom(0.3) end },
	LoadFont("Common Normal") .. { Name="Name", InitCommand=function(self) self:xy(-pBtnW + 10, -5):halign(0):zoom(0.45):diffuse(brightText) end },
	LoadFont("Common Large") .. { Name="Rating", InitCommand=function(self) self:xy(-pBtnW + 10, 18):halign(0):zoom(0.5) end },
	LoadFont("Common Normal") .. { Name="Rank", InitCommand=function(self) self:xy(-110, 18):halign(0):zoom(0.4) end },
	Def.Sprite { Name="Avatar", InitCommand=function(self) self:xy(-35, 0):zoomto(50, 50) end },
	-- Click detector for main chip
	UIElements.QuadButton(1) .. {
		InitCommand = function(self) self:x(-pBtnW/2):zoomto(pBtnW, pBtnH):diffusealpha(0) end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" then
				local idx = HV.TitleState.selectedProfile or 0
				HV.DirectLaunchProfileIdx = idx
				SCREENMAN:GetTopScreen():SetNextScreenName("ScreenSelectProfile")
				SCREENMAN:GetTopScreen():StartTransitioningScreen("SM_GoToNextScreen")
				SOUND:PlayOnce(THEME:GetPathS("Common", "start"))
			end
		end
	}
}

-- Add compact profile rows below the main chip
local chipRef = t[#t]  -- reference to ProfileChip
for ci = 0, maxCompactProfiles - 1 do
	local rowY = pBtnH/2 + compactRowH/2 + 4 + ci * (compactRowH + 2)
	chipRef[#chipRef + 1] = Def.ActorFrame {
		Name = "CompactRow_" .. ci,
		InitCommand = function(self) self:y(rowY):visible(false) end,
		-- Row background
		Def.Quad {
			Name = "CBg",
			InitCommand = function(self)
				self:x(-pBtnW/2):zoomto(pBtnW, compactRowH)
					:diffuse(color("0.08,0.08,0.08,0.9"))
			end
		},
		-- Compact avatar
		Def.Sprite {
			Name = "CAvatar",
			InitCommand = function(self) self:xy(-pBtnW + 22, 0):zoomto(32, 32) end
		},
		-- Compact name
		LoadFont("Common Normal") .. {
			Name = "CName",
			InitCommand = function(self)
				self:xy(-pBtnW + 44, -6):halign(0):zoom(0.4):diffuse(subText)
					:maxwidth((pBtnW - 90) / 0.4)
			end
		},
		-- Compact rating
		LoadFont("Common Normal") .. {
			Name = "CRating",
			InitCommand = function(self)
				self:xy(-pBtnW + 44, 10):halign(0):zoom(0.45):diffuse(dimText)
			end
		},
		-- Click detector
		UIElements.QuadButton(1) .. {
			InitCommand = function(self) self:x(-pBtnW/2):zoomto(pBtnW, compactRowH):diffusealpha(0) end,
			MouseDownCommand = function(self, params)
				if params.event == "DeviceButton_left mouse button" then
					local idx = self:GetParent().profileIdx
					if idx then
						HV.DirectLaunchProfileIdx = idx
						SCREENMAN:GetTopScreen():SetNextScreenName("ScreenSelectProfile")
						SCREENMAN:GetTopScreen():StartTransitioningScreen("SM_GoToNextScreen")
						SOUND:PlayOnce(THEME:GetPathS("Common", "start"))
					end
				end
			end
		}
	}
end


-- Custom Message Handlers
t[#t + 1] = Def.Actor {
	TriggerJukeboxPauseMessageCommand = function(self)
		jukeboxToggle()
	end
}

-- Quotes Display (Toggleable)
t[#t + 1] = Def.ActorFrame {
	Name = "QuotesOverlay",
	InitCommand = function(self)
		self:xy(SCREEN_LEFT, mpBarY - mpBarH/2 - 15)
	end,
	BeginCommand = function(self)
		local mode = ThemePrefs.Get("HV_QuotesMode")
		self:visible(mode ~= "Off")
	end,
	LoadActor("quotes.lua")
}

-- Media Visualizer
do
	local visCore = nil
	if audioVisualizer and audioVisualizer.new then
		visCore = audioVisualizer:new {
			x = 0,
			y = 0,
			width = SCREEN_WIDTH,
			maxHeight = vizH,
			freqIntervals = audioVisualizer.multiplyIntervals(audioVisualizer.defaultIntervals, 4),
			color = accentColor,
			onBarUpdate = function(self)
				self:diffuse(accentColor):diffusealpha(0.55)
			end
		}
	end

	t[#t + 1] = Def.ActorFrame {
		Name = "MediaVisualizer",
		InitCommand = function(self)
			self:xy(SCREEN_LEFT, vizY):draworder(-10000)
		end,
		Def.Quad {
			InitCommand = function(self)
				self:xy(SCREEN_WIDTH / 2, -vizH / 2):zoomto(SCREEN_WIDTH, vizH + 2)
				self:diffuse(color("0.05,0.05,0.05,0.35"))
			end
		},
		(visCore and (visCore .. {
			Name = "VisualizerCore",
			InitCommand = function(self)
				self:draworder(-9999)
			end,
			PlayStatusChangedMessageCommand = function(self)
				local p = HV.TitleState.player
				if p.song and p.paused then
					self:RunCommandsOnChildren(function(bar)
						bar:stoptweening():smooth(0.15):zoomtoheight(2):diffuse(subText):diffusealpha(0.18)
					end)
				end
			end
		}) or Def.Actor {})
	}
end

-- Media Player Bar
t[#t + 1] = Def.ActorFrame {
	Name = "MediaPlayer",
	InitCommand = function(self)
		local lastStateKey = nil
		self:SetUpdateFunction(function(af)
			local p = HV.TitleState.player
			-- Update song text
			local songTxt = af:GetChild("SongText")
			if songTxt then
				if p.song then
					local artist = p.song:GetDisplayArtist() or "?"
					local title = p.song:GetDisplayMainTitle() or "?"
					songTxt:settext(artist .. " - " .. title)
					songTxt:diffuse(subText)
				else
					songTxt:settext(THEME:GetString("ScreenTitleMenu", "JukeboxNoTrack"))
					songTxt:diffuse(dimText)
				end
			end
			-- Update elapsed time
			local timeTxt = af:GetChild("ElapsedTime")
			if timeTxt then
				if p.song and not p.paused then
					local elapsed = p.offset + (GetTimeSinceStart() - p.lastStart)
					timeTxt:settext(SecondsToMSS(elapsed))
					timeTxt:diffuse(subText)
				elseif p.song and p.offset then
					timeTxt:settext(SecondsToMSS(p.offset))
					timeTxt:diffuse(dimText)
				else
					timeTxt:settext("-:--")
					timeTxt:diffuse(dimText)
				end
			end
			-- Update progress bar
			local bar = af:GetChild("ProgressBar")
			if bar then
				if p.song and p.duration > 0 then
					local elapsed = p.offset
					if not p.paused then
						elapsed = p.offset + (GetTimeSinceStart() - p.lastStart)
					end
					local percent = math.max(0, math.min(1, elapsed / p.duration))
					bar:zoomto(SCREEN_WIDTH * percent, 2)
				else
					bar:zoomto(0, 2)
				end
			end

			-- Swap play/pause icon only when state changes
			local stateKey = getPlayerStateKey(p)
			if lastStateKey ~= stateKey then
				lastStateKey = stateKey
				local playBtn = af:GetChild("PlayBtn")
				if playBtn then
					if stateKey == "playing" then
						playBtn:Load(mpPausePath)
						playBtn:diffusealpha(0.7)
					elseif stateKey == "paused" then
						playBtn:Load(mpPlayPath)
						playBtn:diffusealpha(0.7)
					else
						playBtn:Load(mpPlayPath)
						playBtn:diffusealpha(0.45)
					end
					playBtn:zoomto(mpBtnSize, mpBtnSize)
				end
			end
		end)
	end,
	-- Bar background
	Def.Quad {
		InitCommand = function(self)
			self:xy(SCREEN_CENTER_X, mpBarY):zoomto(SCREEN_WIDTH, mpBarH)
			self:diffuse(color("0.06,0.06,0.06,0.92"))
		end
	},
	-- Top edge accent line (Progress Bar)
	Def.Quad {
		Name = "ProgressBar",
		InitCommand = function(self)
			self:xy(SCREEN_LEFT, mpBarY - mpBarH/2):halign(0):zoomto(0, 2)
			self:diffuse(accentColor):diffusealpha(0.6)
		end
	},
	-- Prev button
	UIElements.SpriteButton(1, 1, mpPrevPath) .. {
		Name = "PrevBtn",
		InitCommand = function(self)
			self:xy(mpPrevX, mpBtnY):zoomto(mpBtnSize, mpBtnSize):diffusealpha(0.5)
		end,
		MouseOverCommand = function(self) self:stoptweening():linear(0.1):diffusealpha(1) end,
		MouseOutCommand = function(self) self:stoptweening():linear(0.1):diffusealpha(0.5) end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" then
				jukeboxPrev()
			end
		end
	},
	-- Play/Pause button
	UIElements.SpriteButton(1, 1, mpPlayPath) .. {
		Name = "PlayBtn",
		InitCommand = function(self)
			self:xy(mpPlayX, mpBtnY):zoomto(mpBtnSize, mpBtnSize):diffusealpha(0.7)
		end,
		MouseOverCommand = function(self) self:stoptweening():linear(0.1):diffusealpha(1) end,
		MouseOutCommand = function(self) self:stoptweening():linear(0.1):diffusealpha(0.7) end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" then
				jukeboxToggle()
			end
		end
	},
	-- Next button
	UIElements.SpriteButton(1, 1, mpNextPath) .. {
		Name = "NextBtn",
		InitCommand = function(self)
			self:xy(mpNextX, mpBtnY):zoomto(mpBtnSize, mpBtnSize):diffusealpha(0.5)
		end,
		MouseOverCommand = function(self) self:stoptweening():linear(0.1):diffusealpha(1) end,
		MouseOutCommand = function(self) self:stoptweening():linear(0.1):diffusealpha(0.5) end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" then
				jukeboxNext()
			end
		end
	},
	-- Song text
	LoadFont("Common Normal") .. {
		Name = "SongText",
		Text = "NO TRACK",
		InitCommand = function(self)
			self:xy(SCREEN_LEFT + 120, mpBtnY):halign(0):zoom(0.35)
			self:diffuse(dimText):maxwidth((SCREEN_WIDTH - 200) / 0.35)
		end
	},
	-- Elapsed time
	LoadFont("Common Normal") .. {
		Name = "ElapsedTime",
		Text = "-:--",
		InitCommand = function(self)
			self:xy(SCREEN_RIGHT - 16, mpBtnY):halign(1):zoom(0.3)
			self:diffuse(dimText)
		end
	}
}

-- Standalone Alarm Button (Bottom Left)
t[#t + 1] = Def.ActorFrame {
	Name = "AlarmButton",
	InitCommand = function(self) self:xy(SCREEN_LEFT + 20, mpBarY - 60) end,
	
	-- Alarm Settings Panel
	Def.ActorFrame {
		Name = "AlarmPopup",
		InitCommand = function(self) self:y(-50):visible(false):diffusealpha(0) end,
		ShowAlarmPopupMessageCommand = function(self)
			if self:GetVisible() then self:playcommand("Hide")
			else self:visible(true):stoptweening():decelerate(0.2):diffusealpha(1):y(-70) end
		end,
		HideAlarmPopupMessageCommand = function(self) self:playcommand("Hide") end,
		HideCommand = function(self) self:stoptweening():accelerate(0.2):diffusealpha(0):y(-50):sleep(0):queuecommand("Off") end,
		OffCommand = function(self) self:visible(false) end,
		
		Def.Quad {
			InitCommand = function(self) self:halign(0):zoomto(260, 180):diffuse(color("0.05,0.05,0.05,0.98")):diffusebottomedge(color("0,0,0,1")) end
		},
		LoadFont("Common Normal") .. {
			Text = "ALARM SETTINGS",
			InitCommand = function(self) self:xy(130, -75):zoom(0.4):diffuse(accentColor) end
		},
		
		-- Mode Rows
		(function()
			local r = Def.ActorFrame { InitCommand = function(self) self:y(-40) end }
			for i, row in ipairs(alarmRows) do
				local ry = (i - 1) * 30
				r[#r+1] = Def.ActorFrame {
					InitCommand = function(self) self:y(ry) end,
					LoadFont("Common Normal") .. {
						Text = row.Name,
						InitCommand = function(self) self:x(10):halign(0):zoom(0.35):diffuse(subText) end
					},
					LoadFont("Common Normal") .. {
						Name = "Val",
						InitCommand = function(self) self:x(250):halign(1):zoom(0.35) end,
						ThemePrefChangedMessageCommand = function(self, params) if params.Name == row.Pref then self:playcommand("Refresh") end end,
						RefreshCommand = function(self)
							local val = tostring(ThemePrefs.Get(row.Pref))
							local def = PREF_DEFS[row.Pref]
							local display = val
							for j, v in ipairs(def.Values) do if tostring(v) == val then display = def.Choices[j] break end end
							self:settext(display:upper())
						end,
						OnCommand = function(self) self:playcommand("Refresh") end
					},
					UIElements.QuadButton(1) .. {
						InitCommand = function(self) self:x(130):zoomto(250, 24):diffusealpha(0) end,
						MouseDownCommand = function(self, params)
							if params.event == "DeviceButton_left mouse button" then
								cyclePref(row.Pref)
								SOUND:PlayOnce(THEME:GetPathS("Common", "value"))
							end
						end
					}
				}
			end
			return r
		end)(),
		
		-- Value Row (Time or Timer)
		Def.ActorFrame {
			InitCommand = function(self) 
				self:y(50) 
				self:SetUpdateFunction(function(af)
					local type = ThemePrefs.Get("HV_AlarmType")
					local valText = af:GetChild("Val")
					if valText then
						if type == "Time" then valText:settext(ThemePrefs.Get("HV_AlarmTime") or "12:00")
						else
							local s = HV.AlarmTimerSeconds or 0
							if s > 0 then valText:settext(SecondsToMSS(s))
							else valText:settext((ThemePrefs.Get("HV_AlarmTimerDuration") or 5) .. " MINUTES") end
						end
					end
				end)
			end,
			LoadFont("Common Normal") .. {
				Text = "VALUE",
				InitCommand = function(self) self:x(10):halign(0):zoom(0.35):diffuse(subText) end
			},
			LoadFont("Common Normal") .. {
				Name = "Val",
				InitCommand = function(self) self:x(250):halign(1):zoom(0.35):diffuse(brightText) end
			},
			UIElements.QuadButton(1) .. {
				InitCommand = function(self) self:x(130):zoomto(250, 24):diffusealpha(0) end,
				MouseDownCommand = function(self, params)
					if params.event == "DeviceButton_left mouse button" then
						local type = ThemePrefs.Get("HV_AlarmType")
						if type == "Time" then
							easyInputStringOKCancel("Enter Alarm Time (HH:MM):", 5, false, function(s)
								if s:match("%d%d:%d%d") then ThemePrefs.Set("HV_AlarmTime", s); ThemePrefs.Save() end
							end)
						elseif type == "Timer" then
							easyInputStringOKCancel("Enter Timer Duration (Minutes):", 3, false, function(s)
								local m = tonumber(s)
								if m then 
									ThemePrefs.Set("HV_AlarmTimerDuration", m)
									ThemePrefs.Set("HV_AlarmActive", false) -- Reset active so user has to turn it back on to start
									ThemePrefs.Save()
									HV.AlarmTimerSeconds = m * 60
								end
							end)
						end
						 SOUND:PlayOnce(THEME:GetPathS("Common", "value"))
					end
				end
			}
		}
	},
	
	-- Interactive Button
	UIElements.QuadButton(1) .. {
		InitCommand = function(self) self:zoomto(100, 30):halign(0):diffusealpha(0) end,
		MouseDownCommand = function(self, params)
			if params.event == "DeviceButton_left mouse button" then
				MESSAGEMAN:Broadcast("ShowAlarmPopup")
				SOUND:PlayOnce(THEME:GetPathS("Common", "value"))
			end
		end,
		MouseOverCommand = function(self) 
			local txt = self:GetParent():GetChild("BtnText")
			if txt then 
				txt:stoptweening():linear(0.1):diffuse(accentColor)
				if isGlowEnabled then txt:glow(accentColor) end
			end
		end,
		MouseOutCommand = function(self) 
			local txt = self:GetParent():GetChild("BtnText")
			if txt then txt:stoptweening():linear(0.1):diffuse(subText):glow(color("0,0,0,0")) end
		end
	},
	LoadFont("Common Normal") .. {
		Name = "BtnText",
		Text = "ALARM",
		InitCommand = function(self) self:halign(0):zoom(0.4):diffuse(subText) end
	}
}

return t
