local Config = HV.Config
local defaults = {playerTags = {}}
local tags = Config.CreateStore("tags.lua", defaults, function(data)
	if type(data.playerTags) ~= "table" then data.playerTags = {} end
	return data
end)

local function profileDirectory()
	return Config.ProfileDirectory(GAMESTATE:GetMasterPlayerNumber()) or Config.ProfileDirectory(PLAYER_1)
end

TAGMAN = {
	get_data = function()
		local directory = profileDirectory()
		return directory and tags.Get(directory) or DeepCopy(defaults)
	end,
	set_dirty = function()
		local directory = profileDirectory()
		if directory then tags.MarkDirty(directory) end
	end,
	save = function()
		local directory = profileDirectory()
		if directory then return tags.Save(directory) end
		return false
	end,
}
