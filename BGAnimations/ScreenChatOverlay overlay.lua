local chatScreens = {
	ScreenNetRoom = 0,
	ScreenNetSelectMusic = 1,
	ScreenNetEvaluation = 1,
}
local histories = {[0] = {}, [1] = {}}
local roomName = ""
local owner
local recovering
local inputScreen, inputCallback
local open = false
local draft = ""
local captured = {}
local y = SCREEN_BOTTOM - 138
local width = math.min(380, SCREEN_WIDTH * 0.45)
local height = 112
local toggleWidth = 134
local firstPress = "InputEventType_FirstPress"
local release = "InputEventType_Release"

local function recoverNavigation(screen, name, room)
	if recovering ~= screen then recovering = nil end
	local invalid = (name == "ScreenSMOnlineLogin" or name == "ScreenNetSelectProfile") and not IsNetConnected()
		or name == "ScreenNetRoom" and not (IsNetConnected() and IsSMOnlineLoggedIn())
		or name == "ScreenNetSelectMusic" and room == ""
	if not invalid then return false end
	-- Let a modal pop and any native exit transition finish first.
	if recovering ~= screen and not screen:IsTransitioning() then
		recovering = screen
		screen:Cancel()
	end
	return true
end

local function syncContext(screen, name, tab)
	local channel = chatScreens[name]
	if channel == nil or screen:IsTransitioning() or not (IsNetConnected() and IsSMOnlineLoggedIn())
		or (channel == 1 and tab == "") then screen = nil end
	if screen == owner and tab == roomName then return false end

	owner = screen
	open, draft = false, ""
	if tab ~= roomName then
		roomName = tab
		histories[1] = {}
	end
	return true
end

local function leftEdge()
	return owner and owner:GetName() == "ScreenNetRoom" and SCREEN_WIDTH - width - 16 or 16
end

local function render(self)
	self:x(leftEdge()):visible(owner ~= nil)
	self:GetChild("Panel"):visible(open)
	local title = THEME:GetString("MultiPlayer", "ChatTitle")
	self:GetChild("Toggle"):settext(title .. " [Insert]")
	local panel = self:GetChild("Panel")
	local history = histories[chatScreens[owner and owner:GetName()] or 0]
	panel:GetChild("History"):settext(table.concat(history, "\n", math.max(1, #history - 4)))
	panel:GetChild("Input"):settext("> " .. draft)
end

local function refreshContext(self, screen, name)
	local room = HV.GetMultiplayerRoomName() or ""
	if syncContext(screen, name, room) then render(self) end
	return room
end

local function input(self, event)
	local button = event.DeviceInput.button
	local held = captured[button]
	if event.type == release and held then captured[button] = nil end
	local screen = SCREENMAN:GetTopScreen()
	local name = screen and screen:GetName()
	if chatScreens[name] == nil and name ~= "ScreenSMOnlineLogin" and name ~= "ScreenNetSelectProfile" then
		return held == true
	end
	if recoverNavigation(screen, name, refreshContext(self, screen, name)) then return true end
	if not owner then return held == true end
	if event.type == release then return held == true end
	if name == "ScreenNetSelectMusic" and event.type == "InputEventType_Repeat"
		and (event.GameButton == "Start" or event.button == "Start" or button == "DeviceButton_enter") then
		return true
	end
	if event.type ~= firstPress and not open then return held == true end

	if button == "DeviceButton_left mouse button" then
		if event.type ~= firstPress then return held == true end
		local mx, my = INPUTFILTER:GetMouseX(), INPUTFILTER:GetMouseY()
		local x = leftEdge()
		local overToggle = mx >= x and mx <= x + toggleWidth and my >= y + height and my <= y + height + 20
		local overPanel = open and mx >= x and mx <= x + width and my >= y and my < y + height
		if overToggle then
			open, draft = not open, ""
		elseif not overPanel then
			return false
		end
	elseif event.type == firstPress and button == "DeviceButton_insert" then
		open, draft = not open, ""
	elseif event.type == firstPress and button == "DeviceButton_/" and not open then
		open, draft = true, "/"
	elseif event.type == firstPress and button == "DeviceButton_enter" and not open
		and (INPUTFILTER:IsBeingPressed("left ctrl") or INPUTFILTER:IsBeingPressed("right ctrl")) then
		open, draft = true, ""
	elseif not open or event.DeviceInput.is_mouse then
		return held == true
	elseif event.GameButton == "Back" or event.button == "Back" or button == "DeviceButton_escape" then
		open, draft = false, ""
	elseif event.GameButton == "Start" or event.button == "Start" or button == "DeviceButton_enter"
		or button == "DeviceButton_kp enter" then
		if event.type == firstPress then
			local message = draft:match("^%s*(.-)%s*$")
			if message ~= "" then
				local channel = chatScreens[owner:GetName()]
				NSMAN:SendChatMsg(message, channel, channel == 0 and "" or roomName)
			else
				open = false
			end
			draft = ""
		end
	elseif button == "DeviceButton_backspace" then
		draft = draft:sub(1, -2)
	elseif type(event.char) == "string" and event.char:match("^[ -~]$") and #draft < 500 then
		draft = draft .. event.char
	end

	captured[button] = true
	render(self)
	return true
end

return Def.ActorFrame {
	InitCommand = function(self)
		self:y(y):visible(false)
	end,
	BeginCommand = function(self)
		self:queuecommand("BindInput")
	end,
	BindInputCommand = function(self)
		if inputScreen then return end
		-- Overlay callbacks run before the foreground screen's native input.
		for _, screen in ipairs(SCREENMAN:GetOverlayScreens()) do
			if screen:GetName() == "ScreenChatOverlay" then
				inputScreen = screen
				inputCallback = function(event) return input(self, event) end
				inputScreen:AddInputCallback(inputCallback)
				break
			end
		end
		self:SetUpdateFunction(function()
			local screen = SCREENMAN:GetTopScreen()
			local name = screen and screen:GetName()
			recoverNavigation(screen, name, refreshContext(self, screen, name))
		end)
		self:SetUpdateFunctionInterval(0.1)
	end,
	EndCommand = function(self)
		self:SetUpdateFunction(nil)
		if inputScreen then inputScreen:RemoveInputCallback(inputCallback) end
		inputScreen, inputCallback, recovering = nil, nil, nil
		owner, open, draft = nil, false, ""
		captured = {}
	end,
	ChatMessageCommand = function(self, params)
		local screen = SCREENMAN:GetTopScreen()
		refreshContext(self, screen, screen and screen:GetName())
		if not IsNetConnected() or not IsSMOnlineLoggedIn() or not params or type(params.msg) ~= "string" then return end
		local isLobby = params.type == 0 and params.tab == ""
		local isCurrentRoom = params.type == 1 and roomName ~= "" and params.tab == roomName
		if not isLobby and not isCurrentRoom then
			return
		end
		local history = histories[params.type]
		history[#history + 1] = params.msg
		if #history > 50 then table.remove(history, 1) end
		if open then render(self) end
	end,
	MultiplayerDisconnectionMessageCommand = function(self)
		histories = {[0] = {}, [1] = {}}
		roomName, owner, open, draft = "", nil, false, ""
		render(self)
	end,
	Def.ActorFrame {
		Name = "Panel",
		Def.Quad {
			InitCommand = function(self)
				self:halign(0):valign(0):zoomto(width, height):diffuse(color("0.06,0.06,0.06,0.96"))
			end,
		},
		LoadFont("Common Normal") .. {
			Name = "History",
			InitCommand = function(self)
				self:xy(8, 8):halign(0):valign(0):zoom(0.32):wrapwidthpixels((width - 16) / 0.32):maxheight(80 / 0.32)
			end,
		},
		LoadFont("Common Normal") .. {
			Name = "Input",
			InitCommand = function(self)
				self:xy(8, height - 14):halign(0):zoom(0.36):maxwidth((width - 16) / 0.36)
			end,
		},
	},
	Def.Quad {
		InitCommand = function(self)
			self:y(height):halign(0):valign(0):zoomto(toggleWidth, 20):diffuse(color("0.06,0.06,0.06,0.92"))
		end,
	},
	LoadFont("Common Normal") .. {
		Name = "Toggle",
		InitCommand = function(self)
			self:xy(8, height + 10):halign(0):zoom(0.4):diffuse(HVColor.Accent):maxwidth((toggleWidth - 16) / 0.4)
		end,
	},
}
