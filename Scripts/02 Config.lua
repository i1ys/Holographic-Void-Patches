local Config = HV.Config

Config.Directory = THEME:GetRealThemeDisplayName() .. "_settings"
Config.SaveDirectory = "Save/" .. Config.Directory

local function readFile(path)
	local file = RageFileUtil.CreateRageFile()
	local text
	if file:Open(path, 1) then
		text = file:Read()
		file:Close()
	end
	file:destroy()
	return text
end

local function decodeSettings(text, path)
	if type(text) ~= "string" or text:byte(1) == 27 then return nil end
	local chunk = loadstring(text, "@" .. path)
	if not chunk then return nil end
	setfenv(chunk, {})
	local ok, result = pcall(chunk)
	if ok and type(result) == "table" then return result end
end

function Config.IsFinite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

-- Use fallback's setting object for cached state. Check file I/O here because its
-- load and save methods cannot distinguish failure from an absent or clean file.
function Config.CreateStore(filename, defaults, normalize)
	local setting = create_setting(filename, filename, defaults, 0)
	local unreadable = {}
	local function pathFor(directory)
		return directory .. "/" .. Config.Directory .. "/" .. filename
	end

	local store = {}
	function store.Get(directory)
		local data = setting.data_set[directory]
		if data then return data end

		local path = pathFor(directory)
		if FILEMAN:DoesFileExist(path) then
			data = decodeSettings(readFile(path), path)
			if not data then
				unreadable[directory] = true
				Warn("HV2: Could not load " .. path .. ". Using defaults and preserving the file.")
			end
		end
		data = normalize(data or {})
		setting:set_data(directory, data)
		return data
	end

	function store.Set(directory, key, value)
		local data = store.Get(directory)
		if data[key] ~= value then
			data[key] = value
			setting:set_dirty(directory)
		end
	end

	function store.MarkDirty(directory)
		setting:set_dirty(directory)
	end

	function store.Save(directory)
		if not setting:check_dirty(directory) then return true end

		local path = pathFor(directory)
		local function fail(reason)
			local message = "HV2: Could not save " .. path .. " (" .. reason .. ")."
			Warn(message)
			return false, message
		end
		if unreadable[directory] then return fail("the existing file could not be loaded") end

		local ok, serialized = pcall(lua_table_to_string, store.Get(directory))
		if not ok then return fail("invalid settings data") end
		local output = "return " .. serialized
		if not decodeSettings(output, path) then return fail("invalid settings data") end

		local file = RageFileUtil.CreateRageFile()
		if not file:Open(path, 2) then
			file:destroy()
			return fail("file open failed")
		end
		local written = file:Write(output)
		file:Close()
		file:destroy()
		if written ~= #output or readFile(path) ~= output then
			return fail("write verification failed")
		end

		setting.dirty_table[directory] = nil
		return true
	end
	return store
end

function Config.ProfileDirectory(pn)
	local slot = pn and pn_to_profile_slot(pn)
	if not slot or slot == "ProfileSlot_Invalid" or not PROFILEMAN then return nil end
	local directory = PROFILEMAN:GetProfileDir(slot)
	if directory and directory ~= "" then
		return (directory:gsub("/+$", ""))
	end
end

local themeDefinitions = {
	HV_InstantSearch = {Default = true, Choices = {"Off", "On"}, Values = {false, true}},
}

function Config.NormalizePreference(definition, value)
	if definition.Aliases then value = definition.Aliases[value] or value end
	if type(value) ~= type(definition.Default) then return nil end
	if type(value) == "number" and not Config.IsFinite(value) then return nil end

	-- Percent rows may display a discrete list while accepting custom values.
	if definition.PercentScale then
		if value >= 0 and value <= 100 / definition.PercentScale then return value end
		return nil
	end
	if not definition.Values then return value end
	for _, choice in ipairs(definition.Values) do
		if choice == value then return value end
	end
end

local function normalizeTheme(data)
	for key, definition in pairs(themeDefinitions) do
		local value = Config.NormalizePreference(definition, data[key])
		if value == nil then
			value = definition.Default
		end
		data[key] = value
	end
	return data
end

local themeStore = Config.CreateStore("themeConfig.lua", {}, normalizeTheme)

function Config.RegisterThemePreferences(definitions)
	for key, definition in pairs(definitions) do
		themeDefinitions[key] = definition
	end
end

function Config.GetThemePreference(key)
	return themeDefinitions[key]
end

Config.Theme = {
	Get = function(key)
		if themeDefinitions[key] then return themeStore.Get("Save")[key] end
	end,
	Set = function(key, value)
		local definition = themeDefinitions[key]
		if not definition then return false end
		value = Config.NormalizePreference(definition, value)
		if value == nil then return false end
		themeStore.Set("Save", key, value)
		return true
	end,
	Save = function()
		return themeStore.Save("Save")
	end,
}
