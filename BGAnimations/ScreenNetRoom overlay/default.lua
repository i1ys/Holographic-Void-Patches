local t = Def.ActorFrame {}
local accentColor = HVColor.Accent
local brightText = color("1,1,1,1")
local subText = color("0.65,0.65,0.65,1")
local dimText = color("0.45,0.45,0.45,1")
local bgCard = color("0.06,0.06,0.06,0.92")
local roomWidth = SCREEN_WIDTH - 40
local roomHeight = 52
local roomGap = 10
local topOffset = 56
local footerH = 32
local maxVisibleRooms = math.max(1, math.floor((SCREEN_HEIGHT - topOffset - footerH - 24) / (roomHeight + roomGap)))

local function roomText(room, key, fallback)
	local value = room[key]
	if value == nil or value == "" then
		return fallback
	end
	return tostring(value)
end

local function getRoomScreen()
	if not IsNetConnected() or not IsSMOnlineLoggedIn() then return end
	local screen = SCREENMAN:GetTopScreen()
	if screen and screen:GetName() == "ScreenNetRoom" then
		return screen
	end
end

local function roomList()
	local rooms = {}
	local selectedIndex = 1
	local creatingRoom = false
	local scrollOffset = 0
	local owner, inputCallback, previousRedirection

	local function isCreateSelected()
		return creatingRoom or #rooms == 0
	end

	local function releaseInput(self)
		if not owner then return end
		owner:RemoveInputCallback(inputCallback)
		SCREENMAN:set_input_redirected(PLAYER_1, previousRedirection)
		owner, inputCallback = nil, nil
		self:SetUpdateFunction(nil)
	end

	return Def.ActorFrame {
		Name = "HVNetRoomList",
		OnCommand = function(self)
			local screen = getRoomScreen()
			if not screen or owner then return end
			owner = screen
			previousRedirection = SCREENMAN:get_input_redirected(PLAYER_1)
			SCREENMAN:set_input_redirected(PLAYER_1, true)
			inputCallback = function(event)
				if getRoomScreen() ~= owner or owner:IsTransitioning() then return false end
				if event.type ~= "InputEventType_FirstPress" and event.type ~= "InputEventType_Repeat" then
					return false
				end
				local button = event.GameButton or event.button
				local firstPress = event.type == "InputEventType_FirstPress"
				if button == "Back" then
					if firstPress then screen:Cancel() end
					return true
				end
				if button == "MenuLeft" or button == "Left" or button == "MenuRight" or button == "Right" then
					if firstPress and #rooms > 0 then
						creatingRoom = not creatingRoom
						self:playcommand("RenderRooms")
					end
					return true
				end
				local up = button == "MenuUp" or button == "Up"
				local down = button == "MenuDown" or button == "Down"
				if up or down then
					local count = #rooms
					if count > 0 then
						if creatingRoom then
							creatingRoom = false
							selectedIndex = up and count or 1
						else
							local direction = up and -1 or 1
							selectedIndex = (selectedIndex - 1 + direction) % count + 1
						end
						self:playcommand("RenderRooms")
					end
					return true
				end
				if button == "Start" then
					if not firstPress then return true end
					if isCreateSelected() then
						screen:GetRoomWheel():MakeNewRoom()
					else
						screen:SelectRoom(rooms[selectedIndex].name)
					end
					return true
				end
				return false
			end
			screen:AddInputCallback(inputCallback)
			self:playcommand("RefreshRooms")
		end,
		EndCommand = releaseInput,
		RefreshRoomsCommand = function(self)
			local screen = getRoomScreen()
			if not screen then return end
			local selectedRoom = rooms[selectedIndex]
			rooms = screen:GetRoomWheel():GetRooms()
			selectedIndex = math.max(1, math.min(selectedIndex, #rooms))
			if selectedRoom then
				for i, room in ipairs(rooms) do
					if room.name == selectedRoom.name then
						selectedIndex = i
						break
					end
				end
			end
			self:playcommand("RenderRooms")
		end,
		RoomListUpdatedMessageCommand = function(self)
			self:playcommand("RefreshRooms")
		end,
		BeginTextEntryMessageCommand = function(self)
			-- Etterna sends room changes to the top screen, which can be the text entry prompt.
			self:SetUpdateFunction(function()
				if getRoomScreen() then
					self:SetUpdateFunction(nil)
					self:playcommand("RefreshRooms")
				end
			end)
		end,
		RenderRoomsCommand = function(self)
			scrollOffset = math.min(scrollOffset, math.max(0, #rooms - maxVisibleRooms))
			scrollOffset = math.min(scrollOffset, selectedIndex - 1)
			scrollOffset = math.max(scrollOffset, selectedIndex - maxVisibleRooms)
			local createSelected = isCreateSelected()
			for i = 1, maxVisibleRooms do
				local roomIndex = i + scrollOffset
				self:GetChild("Room" .. i):playcommand("SetRoom", {
					room = rooms[roomIndex],
					selected = not createSelected and roomIndex == selectedIndex
				})
			end
			self:GetChild("NoRooms"):visible(#rooms == 0)
			self:GetChild("CreateRoom"):playcommand("SetSelected", {selected = createSelected})
		end,
		LoadFont("Common Normal") .. {
			Name = "NoRooms",
			InitCommand = function(self)
				self:xy(20, topOffset + 12):zoom(0.4):halign(0):diffuse(dimText)
				self:settext(THEME:GetString("NetRoom", "NoRooms"))
				self:visible(false)
			end
		},
		Def.ActorFrame {
			Name = "CreateRoom",
			InitCommand = function(self)
				self:xy(20, SCREEN_HEIGHT - footerH - 8)
			end,
			SetSelectedCommand = function(self, params)
				local selected = params and params.selected
				self:GetChild("Bg"):diffuse(selected and accentColor or color("0.1,0.1,0.1,0.95"))
				self:GetChild("Label"):diffuse(selected and color("0,0,0,1") or brightText)
			end,
			Def.Quad {
				Name = "Bg",
				InitCommand = function(self)
					self:halign(0):valign(0):zoomto(160, footerH):diffuse(color("0.1,0.1,0.1,0.95"))
				end
			},
			LoadFont("Common Normal") .. {
				Name = "Label",
				InitCommand = function(self)
					self:halign(0):valign(0):xy(10, 7):zoom(0.4):diffuse(brightText)
					self:settext(THEME:GetString("NetRoom", "CreateRoom"))
				end
			},
			UIElements.QuadButton(1, 1) .. {
				InitCommand = function(self)
					self:halign(0):valign(0):zoomto(160, footerH):diffusealpha(0)
				end,
				MouseDownCommand = function(self, params)
					if params.event == "DeviceButton_left mouse button" then
						local screen = getRoomScreen()
						if screen and not screen:IsTransitioning() then
							screen:GetRoomWheel():MakeNewRoom()
						end
					end
				end
			}
		}
	}
end

local function roomEntry(i)
	local roomName
	return Def.ActorFrame {
		Name = "Room" .. i,
		InitCommand = function(self)
			self:xy(20, topOffset + ((i - 1) * (roomHeight + roomGap)))
		end,
		SetRoomCommand = function(self, params)
			local room = params.room
			roomName = room and room.name
			self:visible(room ~= nil)
			if not room then return end
			local selected = params.selected
			self:GetChild("Bg"):diffuse(selected and color("0.12,0.12,0.12,0.98") or bgCard)
			self:GetChild("Accent"):diffuse(selected and accentColor or color("0.2,0.2,0.2,1"))
			self:GetChild("Name"):settext(roomText(room, "name", "Room"))
			self:GetChild("Desc"):settext(roomText(room, "description", THEME:GetString("NetRoom", "Explain")))
			self:GetChild("State"):settext(room.passworded and THEME:GetString("NetRoom", "Passworded") or "")
		end,
		Def.Quad {
			Name = "Bg",
			InitCommand = function(self)
				self:halign(0):valign(0):zoomto(roomWidth, roomHeight):diffuse(bgCard)
			end
		},
		Def.Quad {
			Name = "Accent",
			InitCommand = function(self)
				self:halign(0):valign(0):zoomto(2, roomHeight):diffuse(color("0.2,0.2,0.2,1"))
			end
		},
		LoadFont("Common Normal") .. {
			Name = "Name",
			InitCommand = function(self)
				self:halign(0):valign(0):xy(10, 6):zoom(0.42):diffuse(brightText):maxwidth((roomWidth - 40) / 0.42)
			end
		},
		LoadFont("Common Normal") .. {
			Name = "Desc",
			InitCommand = function(self)
				self:halign(0):valign(0):xy(10, 28):zoom(0.3):diffuse(subText):maxwidth((roomWidth - 110) / 0.3)
			end
		},
		LoadFont("Common Normal") .. {
			Name = "State",
			InitCommand = function(self)
				self:halign(1):valign(0):xy(roomWidth - 10, 18):zoom(0.28):diffuse(accentColor)
			end
		},
		UIElements.QuadButton(1, 1) .. {
			InitCommand = function(self)
				self:halign(0):valign(0):zoomto(roomWidth, roomHeight):diffusealpha(0)
			end,
			MouseDownCommand = function(self, params)
				if params.event == "DeviceButton_left mouse button" and roomName and roomName ~= "" then
					local screen = getRoomScreen()
					if screen and not screen:IsTransitioning() then
						screen:SelectRoom(roomName)
					end
				end
			end
		}
	}
end

t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:zoomto(SCREEN_WIDTH, SCREEN_HEIGHT):diffuse(color("0,0,0,0.55"))
	end
}

t[#t + 1] = Def.Quad {
	InitCommand = function(self)
		self:halign(0):valign(0):xy(0, 0):zoomto(SCREEN_WIDTH, 40):diffuse(color("0.03,0.03,0.03,0.98"))
	end
}

t[#t + 1] = LoadFont("Common Normal") .. {
	InitCommand = function(self)
		self:halign(0):valign(0):xy(16, 10):zoom(0.6):diffuse(brightText)
		self:settext(THEME:GetString("NetRoom", "Name"))
	end
}

t[#t + 1] = LoadFont("Common Normal") .. {
	InitCommand = function(self)
		self:halign(1):valign(0):xy(SCREEN_WIDTH - 16, 11):zoom(0.32):diffuse(dimText)
		self:settext(THEME:GetString("NetRoom", "Explain"))
	end
}

local list = roomList()
for i = 1, maxVisibleRooms do
	list[#list + 1] = roomEntry(i)
end
t[#t + 1] = list

t[#t + 1] = LoadActor("lobbyuserlist.lua")
t[#t + 1] = LoadActor("../_cursor")

return t
