local customDefaults = {
	grades = {
		AAAAA = "#FFFFFF",
		AAAA  = "#80C0CF",
		AAA   = "#CFD198",
		AA    = "#A0CFAB",
		A     = "#CF9898",
		B     = "#98B8CF",
		C     = "#B898CF",
		D     = "#CF98B8",
		F     = "#606060",
		None  = "#454545",
		-- Mid-tier grades
		["AAAA:"] = "#85C5D2",
		["AAAA."] = "#8ACAD6",
		["AAA:"]  = "#D4D59D",
		["AAA."]  = "#D9D9A2",
		["AA:"]   = "#A5D4B0",
		["AA."]   = "#AAD9B5",
		["A:"]    = "#D49D9D",
		["A."]    = "#D9A2A2",
	},

	judgment = {
		W1   = "#f1ffff",
		W2   = "#FFFFB7",
		W3   = "#A0E0A0",
		W4   = "#A0C8E0",
		W5   = "#C8A0E0",
		Miss = "#E0A0A0",
		Held = "#8fbb84ff",
		LetGo = "#E0A0A0",
	},

	difficulty = {
		Beginner  = "#98B8CF",
		Easy      = "#A0CFAB",
		Medium    = "#CFD198",
		Hard      = "#CF9898",
		Challenge = "#B898CF",
		Edit      = "#8C8C8C",
	},

	clearType = {
		MFC     = "#E0F8FF",
		WF      = "#E0E0E0",
		SDP     = "#CFD198",
		PFC     = "#CFD198",
		BF      = "#B898CF",
		SDG     = "#A0CFAB",
		FC      = "#A0CFAB",
		MF      = "#CF9898",
		SDCB    = "#80C0CF",
		Clear   = "#5ABAFF",
		Failed  = "#CF9898",
		Invalid = "#454545",
		NoPlay  = "#252525",
		None    = "#252525",
	},

	goalTracker = {
		Positive = "#A0CFAB",
		Negative = "#CF9898",
	},

	lifeBar = {
		L1 = "#A0CFAB",
		L2 = "#A0CFAB",
		L3 = "#5ABAFF",
		L4 = "#5ABAFF",
		L5 = "#CFD198",
		L6 = "#E0B080",
		L7 = "#CF9898",
		Danger = "#FF4444",
	},

	radar = {
		Power = "#E0B080",
		Chaos = "#B898CF",
		Hell = "#CF9898",
		Mach = "#80C0CF",
		Freeze = "#CFD198",
		Earth = "#A0CFAB",
	},
}


local Config = HV.Config
local accentDefault = "#5ABAFF"
local paletteNames = {holographic = "Holographic", classic = "Classic", custom = "Custom"}
local scaleNames = {holographic = true, classic = true, none = true, monochrome = true, accent = true}

local function asTable(value)
	return type(value) == "table" and value or {}
end

local function hexColor(value)
	if type(value) ~= "string" then return end
	local hex = value:match("^#?([0-9a-fA-F]+)$")
	if hex and (#hex == 6 or #hex == 8) then return "#" .. hex end
end

local path = Config.SaveDirectory .. "/colorConfig.lua"
local usingLegacy = not FILEMAN:DoesFileExist(path)
local settings

if usingLegacy then
	-- Only read the old files in HV2's own save directory.
	local prefs = asTable(Config.ReadTable(Config.SaveDirectory .. "/themeConfig.lua"))
	local palette = Config.ReadTable(Config.SaveDirectory .. "/Holographic Void_customColors.lua")
		or Config.ReadTable(Config.SaveDirectory .. "/HVCustomColors.lua")
	palette = asTable(palette)
	settings = {
		accent = prefs.HV_AccentColor,
		msdScale = prefs.HV_MSDColorScaleV3,
		palettes = {
			grades = prefs.HV_GradeColorStyle,
			judgment = prefs.HV_JudgmentColorStyle,
			difficulty = prefs.HV_DifficultyColorStyle,
			clearType = prefs.HV_ClearTypeColorStyle,
		},
		overrides = palette,
		syncToAccent = palette.__syncToAccent,
	}
else
	settings = Config.ReadTable(path)
	if not settings then
		Warn("HV2: Could not load " .. path .. ". Using default colors.")
		settings = {}
	end
end

local accent = hexColor(settings.accent) or accentDefault
local msdScale = type(settings.msdScale) == "string" and settings.msdScale:lower()
if not scaleNames[msdScale] then msdScale = "holographic" end

local palettes = asTable(settings.palettes)
local overrides = asTable(settings.overrides)
local links = asTable(settings.syncToAccent)

local function resolvePalette(group, holographic, classic)
	local style = type(palettes[group]) == "string" and paletteNames[palettes[group]:lower()] or "Holographic"
	local preset
	if style ~= "Custom" then preset = style == "Classic" and classic or holographic end

	local groupOverrides, groupLinks = {}, {}
	if not usingLegacy or not preset then
		groupOverrides = asTable(overrides[group])
		groupLinks = asTable(links[group])
	end

	local palette = {}
	for element, fallback in pairs(customDefaults[group]) do
		-- Existing HV2 grade presets grouped the intermediate grades.
		if not (usingLegacy and group == "grades" and element:match("[:.]$")) then
			local hex = groupLinks[element] == true and accent or hexColor(groupOverrides[element])
			if hex then
				palette[element] = color(hex)
			elseif preset then
				palette[element] = preset[element]
			else
				palette[element] = color(fallback)
			end
		end
	end
	return palette
end

HV.Color.ApplyConfig(accent, msdScale, resolvePalette)
