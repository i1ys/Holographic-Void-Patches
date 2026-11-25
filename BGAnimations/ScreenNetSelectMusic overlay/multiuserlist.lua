local width = ...
local statusColors = {
	[2] = color("0.65,0.75,1,1"),
	[3] = color("1,1,1,1"),
	[4] = HVColor.Accent,
}
local readyColor = color("0.65,1,0.85,1")
local idleColor = color("0.65,0.65,0.65,1")
local rows = 8
local columns = 4
local t = Def.ActorFrame {
	Name = "Roster",
	InitCommand = function(self) self:xy(12, 182) end,
}

for i = 1, rows * columns do
	t[#t + 1] = LoadFont("Common Normal") .. {
		InitCommand = function(self)
			local columnWidth = (width - 24) / columns
			self:xy(math.floor((i - 1) / rows) * columnWidth, ((i - 1) % rows) * 12)
				:halign(0):valign(0):zoom(0.32):maxwidth((columnWidth - 4) / 0.32)
		end,
		SetUsersCommand = function(self, users)
			local user = users[i]
			self:visible(user ~= nil)
			if user then
				self:settext(user.name):diffuse(statusColors[user.status] or (user.ready and readyColor or idleColor))
			end
		end,
	}
end

return t
