-- Holographic Void: Avatar / Profile Display (adapted from Fatigue)
-- Shows player avatar, name, MSD, difficulty, mods, judge and life bar.

local pn = GAMESTATE:GetEnabledPlayers()[1] or PLAYER_1

local avatarSize = 56
local panelX = 10
local panelY = SCREEN_HEIGHT - 66
local panelW = 240
local panelH = 60

-- HV accent color
local accentColor = HVColor.Accent or color("#00CFFF")
local dimText = color("0.5,0.5,0.5,1")
local fontZoom = 0.55
local fontZoomSmall = 0.45

local function animateAvatarVisibility(self, visible)
	self:stoptweening()
	if visible then
		self:visible(true):diffusealpha(0):decelerate(0.18):diffusealpha(1)
	else
		self:accelerate(0.14):diffusealpha(0)
	end
end

-- Life helper
local function PLife()
	-- Priority 1: Direct LifeMeter actor polling (Smoothest, most reliable)
	local screen = SCREENMAN:GetTopScreen()
	if screen and screen:GetLifeMeter(pn) then
		return screen:GetLifeMeter(pn):GetLife()
	end
	
	-- Priority 2: PlayerStageStats (Fallback)
	local stats = STATSMAN:GetCurStageStats():GetPlayerStageStats()
	local life = stats:GetCurrentLife() or 0
	return math.max(0, life)
end

local t = Def.ActorFrame {
	Name = "AvatarDisplay",
	InitCommand = function(self)
		self:xy(panelX, panelY)
		-- Check if player info should be shown
		local showPlayerInfo = HV.ShowPlayerInfo() and not HV.MinimalisticMode()
		self:visible(showPlayerInfo)
		self:diffusealpha(showPlayerInfo and 1 or 0)
	end,
	HV_MinimalisticModeChangedMessageCommand = function(self, params)
		animateAvatarVisibility(self, HV.ShowPlayerInfo() and not (params and params.Enabled))
	end,

	-- Panel background
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0)
			self:zoomto(panelW, panelH)
			self:diffuse(0.03, 0.03, 0.03, 0.8)
		end,
	},

	-- Avatar border accent
	Def.Quad {
		InitCommand = function(self)
			self:halign(0):valign(0)
			self:xy(-2, -2)
			self:zoomto(avatarSize + 4, avatarSize + 4)
			self:diffuse(accentColor)
			self:diffusealpha(0.5)
		end,
	},

	-- Avatar sprite
	Def.Sprite {
		InitCommand = function(self)
			self:halign(0):valign(0)
		end,
		BeginCommand = function(self)
			self:finishtweening()
			local avatar = HV.OnlineReplayActive and getDefaultAssetByType("avatar") or getAvatarPath(PLAYER_1)
			self:Load(avatar)
			self:zoomto(avatarSize, avatarSize)
		end
	},

	-- Profile name
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:xy(avatarSize + 6, 5):zoom(fontZoom):halign(0):maxwidth(130 / fontZoom)
			self:diffuse(color("1,1,1,1"))
			self.cycleState = 0
			self:playcommand("CycleName")
		end,
		CycleNameCommand = function(self)
			self:stoptweening()
			local replayName = HV.GetOnlineReplayPlayerName()
			if replayName then
				self:diffusealpha(1):settext(replayName)
				return
			end
			local pn = PLAYER_1
			local onlineName = DLMAN:IsLoggedIn() and DLMAN:GetUsername() or ""
			local localName = ""
			local profile = PROFILEMAN:GetProfile(pn)
			if profile then localName = profile:GetDisplayName() end
			if localName == "" then localName = "Player 1" end
			
			if onlineName ~= "" and onlineName ~= localName then
				if self.cycleState == 0 then
					self:settext(onlineName)
				else
					self:settext(localName)
				end
				self.cycleState = 1 - self.cycleState
				
				self:diffusealpha(0):linear(0.25):diffusealpha(1)
				self:sleep(2.5):linear(0.25):diffusealpha(0):queuecommand("CycleName")
			else
				self:diffusealpha(1)
				self:settext(onlineName ~= "" and onlineName or localName)
				self:sleep(3):queuecommand("CycleName")
			end
		end
	},
	
	-- Judge Display
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:xy(panelW - 6, 22):zoom(fontZoomSmall):halign(1)
		end,

		BeginCommand = function(self) self:queuecommand("Set") end,
		SetCommand = function(self)
			self:settextf("J%d", GetTimingDifficulty())
			self:diffuse(accentColor)
		end

	},


	-- MSD value
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:xy(avatarSize + 8, 22):zoom(fontZoom * 1.65):halign(0):maxwidth(100 / fontZoom)
		end,
		BeginCommand = function(self) self:queuecommand("Set") end,
		SetCommand = function(self)
			local steps = GAMESTATE:GetCurrentSteps()
			local meter = steps:GetMSD(getCurRateValue(), 1)
			local showMSD = HV.ShowMSD() and meter > 0
			self:visible(showMSD)
			if showMSD then
				self:settextf("%5.2f", meter)
				self:diffuse(HVColor.GetMSDRatingColor(meter))
			end
		end,
		CurrentRateChangedMessageCommand = function(self) self:queuecommand("Set") end,
	},

	-- Difficulty name
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:xy(avatarSize + 72, 22):zoom(fontZoomSmall):halign(0):maxwidth(150 / fontZoomSmall)
		end,
		BeginCommand = function(self) self:queuecommand("Set") end,
		SetCommand = function(self)
			local steps = GAMESTATE:GetCurrentSteps()
			local diff = ToEnumShortString(steps:GetDifficulty())
			self:settext(getDifficulty(steps:GetDifficulty()))
			self:diffuse(HVColor.GetDifficultyColor(diff))
		end,
	},

	-- Mods string
	LoadFont("Common Normal") .. {
		InitCommand = function(self)
			self:xy(avatarSize + 8, 38):halign(0):zoom(fontZoomSmall * 0.9):maxwidth(panelW * 0.75 / (fontZoomSmall * 0.9))
			self:diffuse(dimText)
		end,
		BeginCommand = function(self)
			self:settext(getModifierTranslations(GAMESTATE:GetPlayerState():GetPlayerOptionsString("ModsLevel_Current")))
		end
	},

	-- Life % counter
	-- it took me 30 hours to make sure it properly works.
	LoadFont("Common Normal") .. {
		Name = "LifePct",
		InitCommand = function(self)
			self:xy(avatarSize + 6, 52):halign(0):zoom(fontZoomSmall * 1.1):diffuse(accentColor)
		end,
		BeginCommand = function(self)
			self:playcommand("UpdateLife")
		end,
		JudgmentMessageCommand = function(self)
			self:playcommand("UpdateLife")
		end,
		PlayingUpdateMessageCommand = function(self)
			self:playcommand("UpdateLife")
		end,
		UpdateLifeCommand = function(self)
			self:settextf("%.1f%%", PLife() * 100)
		end
	},

	-- Life bar background
	Def.Quad {
		InitCommand = function(self)
			self:halign(0)
			self:xy(avatarSize + 40, 52)
			self:zoomto(panelW - avatarSize - 44, 6)
			self:diffuse(0.15, 0.15, 0.15, 1)
		end
	},

	-- Life bar fill
	Def.Quad {
		InitCommand = function(self)
			self:halign(0)
			self:xy(avatarSize + 40, 52)
			self:zoomto(0, 6)
			self:diffuse(accentColor)
			self:queuecommand("Set")
		end,
		JudgmentMessageCommand = function(self, params)
			self:playcommand("Set", params)
		end,
		PlayingUpdateMessageCommand = function(self)
			self:playcommand("Set")
		end,
		SetCommand = function(self, params)
			if params ~= nil and params.TapNoteScore == "TapNoteScore_AvoidMine" then
				return
			end
			self:finishtweening()
			self:smooth(0.1)
			local barMaxW = panelW - avatarSize - 44
			self:zoomx(PLife() * barMaxW)
		end
	},
}

return t
