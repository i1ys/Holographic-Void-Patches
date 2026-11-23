--- Holographic Void: Playlists Tab

local accentColor = HVColor.Accent
local dimText = color("0.45,0.45,0.45,1")
local subText = color("0.65,0.65,0.65,1")
local mainText = color("0.85,0.85,0.85,1")
local brightText = color("1,1,1,1")
local bgCard = color("0.04,0.04,0.04,0.97")

local overlayW = 680
local overlayH = 400
local rowH = 34
local chartsPerPage = 8
local playlistsPerPage = 8
local rowStartY = -overlayH/2 + 85
local playlistsActor = nil
local whee = nil

-- State
local allplaylists = {}
local singleplaylistactive = false
local currentPlaylistPage = 1
local currentChartPage = 1

-- Active playlist data
local pl = nil
local activePlaylistName
local chartlist = {}
local sortMode
local playlistStats

local function saveProfile()
	if not PROFILEMAN:SaveProfile(PLAYER_1) then
		ms.ok(THEME:GetString("Playlists", "SaveFailed"))
	end
end

local function clampPage(page, count, pageSize)
	return math.max(1, math.min(page, math.ceil(count / pageSize)))
end

local function refreshPlaylistList()
	allplaylists = SONGMAN:GetPlaylists()
	table.sort(allplaylists, function(a, b) return a:GetName() < b:GetName() end)
	currentPlaylistPage = clampPage(currentPlaylistPage, #allplaylists, playlistsPerPage)
end

local function findPlaylist(name)
	for _, playlist in ipairs(SONGMAN:GetPlaylists()) do
		if playlist:GetName() == name then return playlist end
	end
end

local function sortChartList()
	if not sortMode then return end
	table.sort(chartlist, function(a, b)
		local first, second = a[sortMode], b[sortMode]
		if first == second then return a.slot < b.slot end
		if sortMode == "title" then return first < second end
		-- Unavailable MSD sorts below any installed chart.
		return (first or -math.huge) > (second or -math.huge)
	end)
end

local function refreshChartList()
	chartlist = {}
	playlistStats = {available = 0, totalMSD = 0, totalDuration = 0}
	if not pl then return end

	local keys = pl:GetChartkeys()
	for i, chart in ipairs(pl:GetAllSteps()) do
		local entry = {
			slot = i,
			key = keys[i],
			rate = chart:GetRate(),
			title = chart:GetSongTitle() or "???",
			difficulty = chart:GetDifficulty(),
		}
		local steps = SONGMAN:GetStepsByChartKey(entry.key)
		if steps and entry.rate > 0 then
			entry.msd = steps:GetMSD(entry.rate, 1)
			playlistStats.available = playlistStats.available + 1
			playlistStats.totalMSD = playlistStats.totalMSD + entry.msd
			playlistStats.totalDuration = playlistStats.totalDuration
				+ math.max(0, steps:GetLastSecond() - steps:GetFirstSecond()) / entry.rate
		end
		chartlist[#chartlist + 1] = entry
	end
	sortChartList()
	currentChartPage = clampPage(currentChartPage, #chartlist, chartsPerPage)
end

local function currentChart(entry)
	local keys = pl:GetChartkeys()
	if keys[entry.slot] ~= entry.key then return end
	local chart = pl:GetAllSteps()[entry.slot]
	if chart and chart:GetRate() == entry.rate then return chart end
end

local function refreshChartView()
	refreshChartList()
	playlistsActor:playcommand("RefreshUI")
end

local function formatRate(rate)
	return (string.format("%.2f", rate):gsub("0$", "")) .. "x"
end

local function getChartPB(entry)
	local rates = SCOREMAN:GetScoresByKey(entry.key)
	local atRate = rates and rates[formatRate(entry.rate)]
	if not atRate then return "" end
	for _, score in ipairs(atRate:GetScores()) do
		if math.abs(score:GetMusicRate() - entry.rate) < 0.00005 then
			return string.format("%.2f%%", score:GetWifeScore() * 100)
		end
	end
	return ""
end

-- Shared input function reference to allow removal/cleanup
local function SharedInputHandler(event)
	if not playlistsActor or not playlistsActor:GetVisible() then return false end
	if not event or not event.DeviceInput then return false end

	-- Screen state awareness: Only handle input if we are the top screen
	-- This prevents blocking overlays like ScreenTextEntry (naming/login)
	-- Safe extraction matching goals.lua
	local btn = event.DeviceInput.button or ""
	if type(btn) ~= "string" then btn = tostring(btn) end
	local evType = event.type

	-- Sink releases immediately
	if evType == "InputEventType_Release" then return true end

	-- Only respond to first presses for clicks!
	if evType ~= "InputEventType_FirstPress" then return true end

	if btn == "DeviceButton_left mouse button" then
		local mx, my = INPUTFILTER:GetMouseX(), INPUTFILTER:GetMouseY()

		-- Header click for sorting
		local headerY = SCREEN_CENTER_Y - overlayH/2 + 65
		if singleplaylistactive and my >= headerY - 10 and my <= headerY + 10 then
			local hx = mx - (SCREEN_CENTER_X - overlayW/2 + 25)
			if hx >= 60 and hx <= 340 then sortMode = "title" end
			if hx >= overlayW - 260 and hx <= overlayW - 200 then sortMode = "rate" end
			if hx >= overlayW - 195 and hx <= overlayW - 135 then sortMode = "msd" end
			sortChartList()
			playlistsActor:playcommand("RefreshUI")
			return true
		end

		-- Close on outside click
		if not IsMouseOverCentered(SCREEN_CENTER_X, SCREEN_CENTER_Y, overlayW, overlayH) then
			MESSAGEMAN:Broadcast("SelectMusicTabChanged", {Tab = ""})
			return true
		end

		-- Back button
		if singleplaylistactive then
			if IsMouseOverCentered(SCREEN_CENTER_X + overlayW/2 - 50, SCREEN_CENTER_Y - overlayH/2 + 18, 60, 18) then
				singleplaylistactive = false

				currentPlaylistPage = 1
				playlistsActor:playcommand("RefreshUI")
				return true
			end
		end

		-- Add Current button
		if singleplaylistactive then
			if IsMouseOverCentered(SCREEN_CENTER_X + overlayW/2 - 235, SCREEN_CENTER_Y - overlayH/2 + 18, 100, 18) then
				local currentSteps = GAMESTATE:GetCurrentSteps()
				if currentSteps then
					local ck = currentSteps:GetChartKey()
					if pl then
						pl:AddChart(ck)
						ms.ok(string.format(THEME:GetString("Playlists", "ChartAdded"), pl:GetName()))
						refreshChartView()
					end
				end
				return true
			end
			
			-- Play as Course button
			if IsMouseOverCentered(SCREEN_CENTER_X + overlayW/2 - 130, SCREEN_CENTER_Y - overlayH/2 + 18, 90, 18) then
				if pl and #chartlist > 0 then
					SCREENMAN:GetTopScreen():StartPlaylistAsCourse(pl:GetName())
				end
				return true
			end
		end

		-- Advanced Controls
		if not singleplaylistactive then
			local ctrlsY = SCREEN_CENTER_Y + overlayH / 2 - 35
			if IsMouseOverCentered(SCREEN_CENTER_X - 55, ctrlsY, 70, 20) then -- NEW
				local profile = PROFILEMAN:GetProfile(PLAYER_1)
				easyInputStringOKCancel(THEME:GetString("Playlists", "PromptNewName"), 32, false, function(name)
					if not name or name == "" then return end
					if profile ~= PROFILEMAN:GetProfile(PLAYER_1) or not SONGMAN:NewPlaylistNoDialog(name) then
						ms.ok(THEME:GetString("Playlists", "CreateFailed"))
						return
					end
					ms.ok(string.format(THEME:GetString("Playlists", "PlaylistCreated"), name))
					saveProfile()
				end)
				return true
			end
			if DLMAN:IsLoggedIn() and IsMouseOverCentered(SCREEN_CENTER_X + 55, ctrlsY, 100, 20) then -- GET EO
				ms.ok(THEME:GetString("Playlists", "DownloadingPlaylists"))
				DLMAN:DownloadMissingPlaylists()
				return true
			end
		end

		-- Row clicks
		local perPage = singleplaylistactive and chartsPerPage or playlistsPerPage
		for ri = 1, perPage do
			local rowTop = SCREEN_CENTER_Y + rowStartY + (ri - 1) * rowH
			local rowLeft = SCREEN_CENTER_X - overlayW/2 + 25
			if mx >= rowLeft and mx <= rowLeft + overlayW - 50 and my >= rowTop and my <= rowTop + rowH then
				if singleplaylistactive then
					local idx = (currentChartPage - 1) * chartsPerPage + ri
					if idx <= #chartlist then
						local entry = chartlist[idx]
						local hx = mx - rowLeft
						
						-- View order and the native playlist slot are independent.
						if hx >= overlayW - 260 and hx <= overlayW - 200 then
							local chart = currentChart(entry)
							if chart then
								chart:ChangeRate(hx <= overlayW - 230 and -0.1 or 0.1)
								if chart:GetRate() ~= entry.rate then saveProfile() end
							end
							refreshChartView()
							return true
						elseif hx >= overlayW - 80 then
							if currentChart(entry) then pl:DeleteChart(entry.slot) end
							refreshChartView()
							return true

						-- Song selection
						else
							local ck = entry.key
							if ck then
								local song = SONGMAN:GetSongByChartKey(ck)
								if song and whee then
									whee:SelectSong(song)
								end
							end
							MESSAGEMAN:Broadcast("SelectMusicTabChanged", {Tab = ""})
							return true
						end
					end
				else
					local idx = (currentPlaylistPage - 1) * playlistsPerPage + ri
					if idx <= #allplaylists then
						local playlist = allplaylists[idx]
						local name = playlist:GetName()
						local hx = mx - rowLeft

						if hx >= overlayW - 75 then
							SONGMAN:DeletePlaylist(name)
							ms.ok(string.format(THEME:GetString("Playlists", "PlaylistDeleted"), name))
							refreshPlaylistList()
							playlistsActor:playcommand("RefreshUI")
						elseif hx >= overlayW - 105 then
							local profile = PROFILEMAN:GetProfile(PLAYER_1)
							easyInputStringOKCancel(THEME:GetString("Playlists", "PromptRename"), 32, false, function(newName)
								if not newName or newName == "" or newName == name then return end
								if type(SONGMAN.RenamePlaylistNoDialog) ~= "function" then
									ms.ok(THEME:GetString("Playlists", "RenameUnavailable"))
									return
								end
								if profile ~= PROFILEMAN:GetProfile(PLAYER_1) or findPlaylist(name) ~= playlist
									or not SONGMAN:RenamePlaylistNoDialog(name, newName) then
									ms.ok(THEME:GetString("Playlists", "RenameFailed"))
									return
								end
								SONGMAN:SetActivePlaylist(newName)
								ms.ok(string.format(THEME:GetString("Playlists", "PlaylistRenamed"), name, newName))
								playlistsActor:playcommand("RefreshUI")
							end, nil, name)
						else
							pl = playlist
							activePlaylistName = name
							SONGMAN:SetActivePlaylist(name)
							singleplaylistactive = true
							currentChartPage, sortMode = 1, nil
							refreshChartView()
						end
					end
					return true
				end
			end
		end
		
		return true -- Sink all other clicks inside the overlay
	end

	if event.button == "Back" or btn == "DeviceButton_escape" then
		if singleplaylistactive then
			singleplaylistactive = false

			playlistsActor:playcommand("RefreshUI")
		else
			MESSAGEMAN:Broadcast("SelectMusicTabChanged", {Tab = ""})
		end
		return true
	end

	-- Sink all input when overlay is visible
	return true
end

local t = Def.ActorFrame {
	Name = "PlaylistsOverlay",
	InitCommand = function(self)
		playlistsActor = self
		self:xy(SCREEN_CENTER_X, SCREEN_CENTER_Y):visible(false)
	end,
	BeginCommand = function(self)
		local screen = SCREENMAN:GetTopScreen()
		if screen and screen.GetMusicWheel then whee = screen:GetMusicWheel() end
	end,
	SelectMusicTabChangedMessageCommand = function(self, params)
		if params.Tab == "PLAYLISTS" then
			-- Use explicit visibility to avoid toggle double-triggering
			self:visible(true)
			self:stoptweening():diffusealpha(0):linear(0.2):diffusealpha(1)
			HV.ActiveTab = "PLAYLISTS"
			singleplaylistactive = false
			pl, activePlaylistName = nil, nil
			currentPlaylistPage = 1
			currentChartPage = 1
			refreshPlaylistList()
			self:playcommand("RefreshUI")
		else
			self:visible(false)
			if HV.ActiveTab == "PLAYLISTS" then HV.ActiveTab = "" end
		end
	end,
	DisplayAllPlaylistsMessageCommand = function(self)
		if not self:GetVisible() then return end
		refreshPlaylistList()
		if singleplaylistactive then
			pl = findPlaylist(activePlaylistName)
			singleplaylistactive = pl ~= nil
			refreshChartList()
		end
		self:playcommand("RefreshUI")
	end,
	NextPlaylistPageMessageCommand = function(self)
		if singleplaylistactive then
			local totalPages = math.max(1, math.ceil(#chartlist / chartsPerPage))
			currentChartPage = math.max(1, math.min(totalPages, currentChartPage + 1))
		else
			local totalPages = math.max(1, math.ceil(#allplaylists / playlistsPerPage))
			currentPlaylistPage = math.max(1, math.min(totalPages, currentPlaylistPage + 1))
		end
		self:playcommand("RefreshUI")
	end,
	PrevPlaylistPageMessageCommand = function(self)
		if singleplaylistactive then
			local totalPages = math.max(1, math.ceil(#chartlist / chartsPerPage))
			currentChartPage = math.max(1, math.min(totalPages, currentChartPage - 1))
		else
			local totalPages = math.max(1, math.ceil(#allplaylists / playlistsPerPage))
			currentPlaylistPage = math.max(1, math.min(totalPages, currentPlaylistPage - 1))
		end
		self:playcommand("RefreshUI")
	end,

	-- Background
	Def.Quad { InitCommand = function(self) self:zoomto(overlayW, overlayH):diffuse(bgCard) end },
	Def.Quad { InitCommand = function(self) self:valign(0):y(-overlayH/2):zoomto(overlayW, 2):diffuse(accentColor):diffusealpha(0.7) end },

	-- Title & Stats
	Def.ActorFrame {
		Name = "HeaderInfo",
		InitCommand = function(self) self:xy(-overlayW/2 + 25, -overlayH/2 + 15) end,
		
		LoadFont("Common Normal") .. {
			Name = "Title",
			InitCommand = function(self) self:halign(0):zoom(0.5):diffuse(accentColor) end,
			RefreshUICommand = function(self)
				if singleplaylistactive and pl then
					self:settextf(THEME:GetString("Playlists", "SingleTitle"), pl:GetName())
				else
					self:settextf(THEME:GetString("Playlists", "Title"), #allplaylists)
				end
			end,
		},
		
		LoadFont("Common Normal") .. {
			Name = "Stats",
			InitCommand = function(self) self:halign(0):y(20):zoom(0.24):diffuse(subText) end,
			RefreshUICommand = function(self)
				if singleplaylistactive and pl then
					local stats = playlistStats
					local average = stats.available > 0 and string.format("%.2f", stats.totalMSD / stats.available) or "—"
					local duration = stats.available > 0 and SecondsToMSS(stats.totalDuration) or "—"
					local missing = #chartlist - stats.available
					local charts = tostring(#chartlist)
					if missing > 0 then
						charts = charts .. " " .. string.format(THEME:GetString("Playlists", "MissingCharts"), missing)
					end
					self:settextf("%s: %s  ·  %s: %s  ·  %s: %s",
						THEME:GetString("Playlists", "AvgMSD"), average,
						THEME:GetString("Playlists", "Duration"), duration,
						THEME:GetString("Playlists", "Charts"), charts)
				else
					self:settext("")
				end
			end,
		},
	},

	-- Back button
	Def.ActorFrame {
		Name = "BackBtn",
		InitCommand = function(self) self:xy(overlayW/2 - 50, -overlayH/2 + 18):visible(false) end,
		RefreshUICommand = function(self)
			self:visible(singleplaylistactive)
		end,
		Def.Quad {
			InitCommand = function(self) self:zoomto(60, 18):diffuse(accentColor):diffusealpha(0.4) end,
		},
		LoadFont("Common Normal") .. {
			InitCommand = function(self) self:zoom(0.24):diffuse(brightText):settext("<- " .. THEME:GetString("Common", "Back")) end,
		},
	},

	-- Play as Course button
	Def.ActorFrame {
		Name = "PlayAsCourseBtn",
		InitCommand = function(self) self:xy(overlayW/2 - 130, -overlayH/2 + 18):visible(false) end,
		RefreshUICommand = function(self)
			self:visible(singleplaylistactive and pl ~= nil and #chartlist > 0)
		end,
		Def.Quad {
			InitCommand = function(self) self:zoomto(90, 18):diffuse(accentColor):diffusealpha(0.4) end,
		},
		LoadFont("Common Normal") .. {
			InitCommand = function(self) self:zoom(0.24):diffuse(brightText):settext(THEME:GetString("Playlists", "PlayAsCourse")) end,
		},
	},

	-- Page info
	LoadFont("Common Normal") .. {
		Name = "PageInfo",
		InitCommand = function(self)
			self:halign(1):valign(0):xy(overlayW/2 - 16, -overlayH/2 + 30):zoom(0.24):diffuse(dimText)
		end,
		RefreshUICommand = function(self)
			local total, perPage, curPage
			if singleplaylistactive then
				total = #chartlist
				perPage = chartsPerPage
				curPage = currentChartPage
			else
				total = #allplaylists
				perPage = playlistsPerPage
				curPage = currentPlaylistPage
			end
			local totalPages = math.max(1, math.ceil(total / perPage))
			self:settextf(THEME:GetString("Common", "PageInfo"), curPage, totalPages)
		end,
	},
	Def.ActorFrame {
		Name = "AddCurrentBtn",
		InitCommand = function(self)
			self:xy(overlayW/2 - 235, -overlayH/2 + 18)
		end,
		RefreshUICommand = function(self)
			self:visible(singleplaylistactive)
		end,
		Def.Quad {
			Name = "Bg",
			InitCommand = function(self)
				self:zoomto(100, 18):diffuse(accentColor):diffusealpha(0.15)
			end
		},
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:zoom(0.24):diffuse(brightText):settext(THEME:GetString("Playlists", "AddCurrent"))
			end
		}
	},

	-- Advanced Controls Row (Bottom)
	Def.ActorFrame {
		Name = "AdvancedControls",
		InitCommand = function(self) self:xy(0, overlayH / 2 - 35) end,
		RefreshUICommand = function(self)
			self:visible(not singleplaylistactive)
		end,

		-- NEW
		Def.ActorFrame {
			Name = "NewBtn",
			InitCommand = function(self) self:x(-55) end,
			Def.Quad { InitCommand = function(self) self:zoomto(70, 20):diffuse(accentColor):diffusealpha(0.2) end },
			LoadFont("Common Normal") .. { InitCommand = function(self) self:zoom(0.32):diffuse(brightText):settext(THEME:GetString("Playlists", "New")) end },
		},
		-- GET EO PLAYLISTS
		Def.ActorFrame {
			Name = "GetEOBtn",
			InitCommand = function(self) self:x(55) end,
			RefreshUICommand = function(self)
				self:visible(DLMAN:IsLoggedIn())
			end,
			Def.Quad { InitCommand = function(self) self:zoomto(100, 20):diffuse(accentColor):diffusealpha(0.2) end },
			LoadFont("Common Normal") .. { InitCommand = function(self) self:zoom(0.32):diffuse(brightText):settext(THEME:GetString("Playlists", "GetEO")) end },
		},
	},
}

-- Single Playlist EO Controls (Top Right)
t[#t+1] = Def.ActorFrame {
	Name = "SingleEOControls",
	InitCommand = function(self) self:xy(overlayW/2 - 365, -overlayH/2 + 18) end,
	RefreshUICommand = function(self)
		self:visible(singleplaylistactive and DLMAN:IsLoggedIn() and pl and pl:GetName() ~= "Favorites")
	end,
	-- UPLOAD
	Def.ActorFrame {
		Name = "UploadBtn",
		InitCommand = function(self) self:x(-45) end,
		Def.Quad { InitCommand = function(self) self:zoomto(70, 18):diffuse(accentColor):diffusealpha(0.15) end },
		LoadFont("Common Normal") .. { InitCommand = function(self) self:zoom(0.24):diffuse(brightText):settext("UPLOAD EO") end },
	},
	-- SYNC (DL)
	Def.ActorFrame {
		Name = "SyncBtn",
		InitCommand = function(self) self:x(35) end,
		Def.Quad { InitCommand = function(self) self:zoomto(70, 18):diffuse(accentColor):diffusealpha(0.15) end },
		LoadFont("Common Normal") .. { InitCommand = function(self) self:zoom(0.24):diffuse(brightText):settext("SYNC EO") end },
	},
}


-- Column Headers (Sortable)
t[#t+1] = Def.ActorFrame {
	Name = "ColumnHeaders",
	InitCommand = function(self) self:xy(-overlayW/2 + 25, -overlayH/2 + 65):visible(false) end,
	RefreshUICommand = function(self) self:visible(singleplaylistactive) end,
	
	LoadFont("Common Normal") .. { InitCommand = function(self) self:halign(0):x(60):zoom(0.32):diffuse(accentColor):settext(THEME:GetString("Common", "SongTitle")) end },
	LoadFont("Common Normal") .. { InitCommand = function(self) self:halign(0.5):x(overlayW - 230):zoom(0.32):diffuse(accentColor):settext(THEME:GetString("Playlists", "Rate")) end },
	LoadFont("Common Normal") .. { InitCommand = function(self) self:halign(0.5):x(overlayW - 165):zoom(0.32):diffuse(accentColor):settext(THEME:GetString("Playlists", "MSD")) end },
	LoadFont("Common Normal") .. { InitCommand = function(self) self:halign(0.5):x(overlayW - 115):zoom(0.32):diffuse(accentColor):settext(THEME:GetString("Playlists", "PB")) end },
}

-- Rows for playlist list and chart entries
for i = 1, math.max(chartsPerPage, playlistsPerPage) do
	t[#t + 1] = Def.ActorFrame {
		Name = "Row_" .. i,
		InitCommand = function(self)
			self:xy(-overlayW/2 + 25, rowStartY + (i - 1) * rowH)
		end,

		Def.Quad {
			Name = "Bg",
			InitCommand = function(self)
				self:halign(0):valign(0):zoomto(overlayW - 50, rowH - 4):diffuse(color("0,0,0,0.2"))
			end,
		},

		-- Difficulty text
		LoadFont("Common Normal") .. {
			Name = "DiffText",
			InitCommand = function(self)
				self:halign(0):valign(0.5):xy(40, rowH / 2):zoom(0.32):visible(false)
			end,
		},

		-- Main text line
		LoadFont("Common Normal") .. {
			Name = "MainText",
			InitCommand = function(self)
				self:halign(0):valign(0.5):xy(90, rowH / 2):zoom(0.42):diffuse(brightText):maxwidth((overlayW - 350) / 0.42)
			end,
		},

		-- Rate Controls
		Def.ActorFrame {
			Name = "RateControls",
			InitCommand = function(self) self:x(overlayW - 230):y(rowH/2):visible(false) end,
			RefreshUICommand = function(self) self:visible(singleplaylistactive) end,
			Def.Sprite {
				Name = "L",
				Texture = THEME:GetPathG("", "left"),
				InitCommand = function(self) self:x(-25):zoomto(12, 12):diffuse(accentColor) end
			},
			LoadFont("Common Normal") .. { Name = "Val", InitCommand = function(self) self:zoom(0.35):diffuse(brightText) end },
			Def.Sprite {
				Name = "R",
				Texture = THEME:GetPathG("", "right"),
				InitCommand = function(self) self:x(25):zoomto(12, 12):diffuse(accentColor) end
			},
		},

		-- Sub text (PB display)
		LoadFont("Common Normal") .. {
			Name = "SubText",
			InitCommand = function(self)
				self:halign(1):valign(0.5):x(overlayW - 115):y(rowH / 2):zoom(0.32):diffuse(subText)
			end,
		},

		-- MSD display
		LoadFont("Common Normal") .. {
			Name = "RateText",
			InitCommand = function(self)
				self:halign(1):valign(0.5):x(overlayW - 165):y(rowH / 2):zoom(0.32):diffuse(dimText)
			end,
		},

		-- Rename button (only for playlist list view)
		Def.Sprite {
			Name = "RenameBtn",
			Texture = THEME:GetPathG("", "rename"),
			InitCommand = function(self)
				self:halign(0.5):valign(0.5):xy(overlayW - 90, rowH / 2):zoomto(18, 18)
			end,
		},

		-- Delete button (visible in both chart view and playlist list view)
		Def.Sprite {
			Name = "DelBtn",
			Texture = THEME:GetPathG("", "delete"),
			InitCommand = function(self)
				self:halign(0.5):valign(0.5):xy(overlayW - 65, rowH / 2):zoomto(18, 18)
			end,
		},

		RefreshUICommand = function(self)
			if singleplaylistactive then
				-- Chart entries
				local idx = (currentChartPage - 1) * chartsPerPage + i
				if idx <= #chartlist then
					self:visible(true)
					local entry = chartlist[idx]
					self:GetChild("MainText"):settext(entry.title)
						:diffuse(entry.msd and brightText or color("1,0.3,0.3,1"))
					local diff = entry.difficulty
					self:GetChild("DiffText"):settext(getShortDifficulty(diff))
						:diffuse(HVColor.GetDifficultyColor(diff)):visible(true)
					self:GetChild("RateControls"):GetChild("Val"):settext(formatRate(entry.rate))
					self:GetChild("RateText"):settext(entry.msd and string.format("%.2f", entry.msd) or "—"):visible(true)
					self:GetChild("SubText"):settext(getChartPB(entry)):visible(true)
					self:GetChild("DelBtn"):visible(true)
					self:GetChild("DelBtn"):diffusealpha(0.6)
					if self:GetChild("RenameBtn") then self:GetChild("RenameBtn"):visible(false) end
					self:GetChild("RateControls"):playcommand("RefreshUI")
				else
					self:visible(false)
				end
			else
				-- Playlist list
				local idx = (currentPlaylistPage - 1) * playlistsPerPage + i
				if idx <= #allplaylists then
					self:visible(true)
					local playlist = allplaylists[idx]
					local name = playlist:GetName()
					self:GetChild("MainText"):settext(name)
					-- Highlight active playlist
					local activePl = SONGMAN:GetActivePlaylist()
					if activePl and activePl:GetName() == name then
						self:GetChild("MainText"):diffuse(accentColor)
					else
						self:GetChild("MainText"):diffuse(brightText)
					end
					self:GetChild("DiffText"):settext(""):visible(false)
					self:GetChild("RateControls"):visible(false)
					self:GetChild("SubText"):settextf("%d %s", playlist:GetNumCharts(), THEME:GetString("Playlists", "Charts"):lower()):visible(true)
					self:GetChild("RateText"):settext(""):visible(false)
					self:GetChild("DelBtn"):visible(true)
					self:GetChild("DelBtn"):diffusealpha(1.0)
					if self:GetChild("RenameBtn") then self:GetChild("RenameBtn"):visible(true) end
				else
					self:visible(false)
				end
			end
		end,
	}
end

-- Input handler
t[#t + 1] = Def.ActorFrame {
	BeginCommand = function(self)
		local screen = SCREENMAN:GetTopScreen()
		if not screen then return end
		-- Always cleanup any existing callback from a previous load
		if HV.PlaylistsInputCallback then
			pcall(function() screen:RemoveInputCallback(HV.PlaylistsInputCallback) end)
		end
		-- Only the primary instance (1) or the latest reloaded one should handle input.
		-- We assign a fresh function here to ensure it uses the latest local state.
		HV.PlaylistsInputCallback = function(event) return SharedInputHandler(event) end
		screen:AddInputCallback(HV.PlaylistsInputCallback)
	end,
}

return t
