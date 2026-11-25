local width = math.min(330, SCREEN_CENTER_X - 32)
local accent = HVColor.Accent
local text = color("1,1,1,1")
local muted = color("0.65,0.65,0.65,1")
local owner, inputCallback
local room = {}
local starting = false
local firstPress = "InputEventType_FirstPress"

local function activeRoom()
	if owner and owner == SCREENMAN:GetTopScreen() and not owner:IsTransitioning() and not starting then
		return HV.GetMultiplayerRoomName()
	end
end

local function label(name, x, y, zoom, tint)
	return LoadFont("Common Normal") .. {
		Name = name,
		InitCommand = function(self)
			self:xy(x, y):halign(0):zoom(zoom):diffuse(tint):maxwidth((width - x - 12) / zoom)
		end,
	}
end

local function button(name, x, labelText, action)
	return Def.ActorFrame {
		Name = name,
		InitCommand = function(self) self:xy(x, 154):visible(false) end,
		Def.Quad {
			InitCommand = function(self) self:halign(0):zoomto((width - 28) / 4, 24):diffuse(color("0.14,0.14,0.14,1")) end,
		},
		label("Label", 4, 0, 0.31, text) .. {
			BeginCommand = function(self) self:settext(labelText) end,
		},
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self) self:halign(0):zoomto((width - 28) / 4, 24):diffusealpha(0) end,
			MouseDownCommand = function(self, params)
				if params.event ~= "DeviceButton_left mouse button" then return end
				local name = activeRoom()
				if name then action(name) end
			end,
		},
	}
end

local function refreshChart(self, song, steps)
	local title, details, group = "", "", ""
	if song then
		title = song:GetDisplayMainTitle()
		group = song:GetGroupName()
		details = song:GetDisplayArtist()
	end
	if steps then
		local difficulty = ToEnumShortString(steps:GetDifficulty())
		local description = steps:GetDescription()
		local rate = getCurRateValue()
		local chart = difficulty == "Edit" and description ~= "" and description or difficulty
		details = string.format("%s  ·  %s  ·  %.2fx", details, chart, rate)
	end
	self:GetChild("Song"):settext(title)
	self:GetChild("Chart"):settext(details)
	self:GetChild("Pack"):settext(group)
end

local function refreshRoom(self)
	local name = owner and HV.GetMultiplayerRoomName()
	if not name then
		room = {}
		self:visible(false)
		return
	end
	self:visible(true)
	local users = {}
	local username = NSMAN:GetLoggedInUsername():lower()
	local ready
	for i = 1, owner:GetUserQty() do
		local user = owner:GetUser(i)
		local isReady = owner:GetUserReady(i)
		users[i] = {name = user, ready = isReady, status = owner:GetUserState(i)}
		if user:lower() == username then ready = isReady end
	end
	local readySentAt = room.name == name and room.ready == ready and room.readySentAt or nil
	room = {name = name, ready = ready, readySentAt = readySentAt, users = users}
	self:GetChild("Room"):settext(room.name)
	self:GetChild("Roster"):playcommand("SetUsers", room.users)
	local readyButton = self:GetChild("Ready")
	readyButton:visible(room.ready ~= nil)
	readyButton:GetChild("Label"):settext(THEME:GetString("ScreenSelectMusic", room.ready and "Unready" or "Ready"))
	for _, key in ipairs({"Force", "Options", "Select"}) do self:GetChild(key):visible(true) end
end

local function begin(self)
	if owner then return end
	owner = SCREENMAN:GetTopScreen()
	if not owner then return end
	starting = false
	inputCallback = function(event)
		if event.type ~= firstPress or not event.DeviceInput then return false end
		local device = event.DeviceInput.button
		local direction = device == "DeviceButton_mousewheel up" and -1 or device == "DeviceButton_mousewheel down" and 1
		if not direction or not activeRoom() or INPUTFILTER:GetMouseX() < SCREEN_CENTER_X then return false end
		local wheel = owner:GetMusicWheel()
		wheel:Move(direction)
		wheel:Move(0)
		return true
	end
	owner:AddInputCallback(inputCallback)
	self:queuecommand("RefreshRoom")
	self:queuecommand("RefreshChart")
end

local function finish(self)
	if owner then owner:RemoveInputCallback(inputCallback) end
	owner, inputCallback = nil, nil
	self:visible(false)
end

return Def.ActorFrame {
	Name = "HVMultiplayerRoom",
	InitCommand = function(self) self:xy(16, 36):visible(false) end,
	BeginCommand = begin,
	OnCommand = function(self) self:queuecommand("RefreshRoom") end,
	OffCommand = finish,
	EndCommand = finish,
	RefreshRoomCommand = refreshRoom,
	RefreshChartCommand = function(self)
		refreshChart(self, GAMESTATE:GetCurrentSong(), GAMESTATE:GetCurrentSteps())
	end,
	UsersUpdateMessageCommand = function(self) self:playcommand("RefreshRoom") end,
	CurrentSongChangedMessageCommand = function(self) self:queuecommand("RefreshChart") end,
	CurrentStepsChangedMessageCommand = function(self) self:queuecommand("RefreshChart") end,
	CurrentRateChangedMessageCommand = function(self) self:queuecommand("RefreshChart") end,
	NSMANSelectedSongMessageCommand = function(self, params)
		refreshChart(self, params.song, params.steps)
		if params.start then starting = true end
	end,
	MultiplayerDisconnectionMessageCommand = function(self) self:visible(false) end,

	Def.Quad {
		InitCommand = function(self) self:halign(0):valign(0):zoomto(width, 286):diffuse(color("0.06,0.06,0.06,0.94")) end,
	},
	label("Room", 12, 18, 0.49, accent),
	label("Song", 12, 56, 0.58, text),
	label("Pack", 12, 80, 0.32, muted),
	label("Chart", 12, 108, 0.38, text),
	LoadActor("multiuserlist.lua", width),
	button("Ready", 8, THEME:GetString("ScreenSelectMusic", "Ready"), function(name)
		if room.name ~= name or room.ready == nil then return end
		local now = GetTimeSinceStart()
		if room.readySentAt and now - room.readySentAt < 1 then return end
		room.readySentAt = now
		NSMAN:SendChatMsg("/ready", 1, name)
	end),
	button("Force", 12 + (width - 28) / 4, THEME:GetString("ScreenSelectMusic", "ForceStart"), function(name)
		NSMAN:SendChatMsg("/force", 1, name)
	end),
	button("Options", 16 + (width - 28) / 2, THEME:GetString("NetRoom", "PlayerOptions"), function()
		owner:OpenOptions()
	end),
	button("Select", 20 + (width - 28) * 0.75, THEME:GetString("NetRoom", "SelectSong"), function()
		local wheel = owner:GetMusicWheel()
		if wheel:IsSettled() then owner:SelectCurrent() end
	end),
	LoadActor("../_cursor"),
}
