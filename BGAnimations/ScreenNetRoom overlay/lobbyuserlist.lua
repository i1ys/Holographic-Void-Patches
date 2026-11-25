local scale = 0.45
local startX = 24
local startY = SCREEN_HEIGHT - 62
local nameColor = color("0.75,0.75,0.75,1")
local names = {}

local function refresh(self)
	local screen = SCREENMAN:GetTopScreen()
	if not screen or screen:GetName() ~= "ScreenNetRoom" or not IsNetConnected() or not IsSMOnlineLoggedIn() then return end
	local current = NSMAN:GetLobbyUserList()
	local changed = #current ~= #names
	if not changed then
		for i, name in ipairs(current) do
			if name ~= names[i] then
				changed = true
				break
			end
		end
	end
	if changed then
		names = current
		self:playcommand("SetLobbyUsers", names)
	end
end

local t = Def.ActorFrame {
	Name = "LobbyUsers",
	BeginCommand = function(self)
		refresh(self)
		-- Full lobby user lists arrive without a UsersUpdate broadcast in v0.75.1.
		self:SetUpdateFunction(refresh)
		self:SetUpdateFunctionInterval(0.5)
	end,
	EndCommand = function(self) self:SetUpdateFunction(nil) end,
	UsersUpdateMessageCommand = refresh,
}

for i = 1, 40 do
	t[#t + 1] = LoadFont("Common Normal") .. {
		InitCommand = function(self) self:halign(0):zoom(scale):diffuse(nameColor) end,
		SetLobbyUsersCommand = function(self, users)
			local name = users[i]
			self:visible(name ~= nil)
			if not name then return end
			local columns = #users < 13 and 6 or 10
			local width = #users < 13 and 64 or 40
			local gap = #users < 13 and 6 or 3
			self:xy(startX + (width + gap) * ((i - 1) % columns), startY + 18 * math.floor((i - 1) / columns))
				:maxwidth(width / scale):settext(name):diffuse(i == 1 and HVColor.Accent or nameColor)
		end,
	}
end

return t
