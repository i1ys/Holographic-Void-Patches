local defaultGameplayCoordinates = {
	JudgeX = 0,
	JudgeY = 0,
	ComboX = 0,
	ComboY = -55,
	MiniProgressBarX = SCREEN_CENTER_X,
	MiniProgressBarY = SCREEN_CENTER_Y - 15,
	ErrorBarX = SCREEN_CENTER_X,
	ErrorBarY = SCREEN_CENTER_Y + SCREEN_HEIGHT * 0.15 - 40,
	TargetTrackerX = SCREEN_CENTER_X,
	TargetTrackerY = SCREEN_CENTER_Y - 115,
	FullProgressBarX = SCREEN_CENTER_X,
	FullProgressBarY = 12,
	JudgeCounterX = SCREEN_CENTER_X + 160,
	JudgeCounterY = SCREEN_HEIGHT - 176,
	DisplayPercentX = SCREEN_CENTER_X,
	DisplayPercentY = SCREEN_CENTER_Y - 90,
	DisplayMeanX = SCREEN_CENTER_X,
	DisplayMeanY = SCREEN_CENTER_Y + 70,
	NPSDisplayX = 10,
	NPSDisplayY = SCREEN_CENTER_Y + 95,
	NPSGraphX = 10,
	NPSGraphY = SCREEN_CENTER_Y + 100,
	ProgressBarPos = 1,
	LeaderboardX = 10,
	LeaderboardY = 40,
	ReplayButtonsX = SCREEN_RIGHT - 40,
	ReplayButtonsY = SCREEN_CENTER_Y + 50,
	LifeP1X = 178,
	LifeP1Y = 10,
	LifeP1Rotation = 0,
	PracticeCDGraphX = 10,
	PracticeCDGraphY = 85,
	BPMTextX = SCREEN_CENTER_X,
	BPMTextY = SCREEN_BOTTOM - 20,
	RecentJudgmentDisplayX = -160,
	RecentJudgmentDisplayY = 50,
	AutoFailDisplayX = 10,
	AutoFailDisplayY = SCREEN_CENTER_Y + 40,
	NotefieldX = 0,
	NotefieldY = 0
}

local defaultGameplaySizes = {
	JudgeZoom = 1.0,
	ComboZoom = 1.0,
	TargetTrackerZoom = 1.0,
	DisplayPercentZoom = 1,
	DisplayMeanZoom = 1,
	NPSDisplayZoom = 0.65,
	NPSGraphWidth = 1.0,
	NPSGraphHeight = 1.0,
	LeaderboardWidth = 1.0,
	LeaderboardHeight = 1.0,
	RecentJudgmentDisplayZoom = 1.0,
	BPMTextZoom = 1.0,
	AutoFailDisplayZoom = 1.0,
	NotefieldWidth = 1.0,
	NotefieldHeight = 1.0,
	NotefieldSpacing = 0.0,
	ErrorBarScale = 1.0
}

local defaultConfig = {
	ScreenFilter = 1,
	JudgeType = 1,
	AvgScoreType = 0,
	GhostScoreType = 1,
	DisplayPercent = true,
	DisplayMean = false,
	TargetTracker = true,
	TargetGoal = 93,
	TargetTrackerMode = 0, -- 0: set percent, 1: pb, 2: pb (replay)
	JudgeCounter = true,
	ErrorBar = 1,
	leaderboardEnabled = false,
	PlayerInfo = true,
	FullProgressBar = true,
	MiniProgressBar = true,
	LaneCover = 0, -- soon to be changed to: 0=off, 1=sudden, 2=hidden
	LaneCoverHeight = 10,
	NPSDisplay = true,
	NPSGraph = false,
	CBHighlight = false,
	OneShotMirror = false,
	JudgmentText = true,
	ComboText = true,
	ReceptorSize = 100,
	ErrorBarCount = 30,
	BackgroundType = 1,
	UserName = "",
	PasswordToken = "",
	CustomEvaluationWindowTimings = false,
	GameplayXYCoordinates = {
		["3K"] = DeepCopy(defaultGameplayCoordinates),
		["4K"] = DeepCopy(defaultGameplayCoordinates),
		["5K"] = DeepCopy(defaultGameplayCoordinates),
		["6K"] = DeepCopy(defaultGameplayCoordinates),
		["7K"] = DeepCopy(defaultGameplayCoordinates),
		["8K"] = DeepCopy(defaultGameplayCoordinates),
		["9K"] = DeepCopy(defaultGameplayCoordinates),
		["10K"] = DeepCopy(defaultGameplayCoordinates),
		["12K"] = DeepCopy(defaultGameplayCoordinates),
		["16K"] = DeepCopy(defaultGameplayCoordinates)
	},
	GameplaySizes = {
		["3K"] = DeepCopy(defaultGameplaySizes),
		["4K"] = DeepCopy(defaultGameplaySizes),
		["5K"] = DeepCopy(defaultGameplaySizes),
		["6K"] = DeepCopy(defaultGameplaySizes),
		["7K"] = DeepCopy(defaultGameplaySizes),
		["8K"] = DeepCopy(defaultGameplaySizes),
		["9K"] = DeepCopy(defaultGameplaySizes),
		["10K"] = DeepCopy(defaultGameplaySizes),
		["12K"] = DeepCopy(defaultGameplaySizes),
		["16K"] = DeepCopy(defaultGameplaySizes)
	}
}

function getDefaultGameplaySize(obj)
	return defaultGameplaySizes[obj]
end

function getDefaultGameplayCoordinate(obj)
	return defaultGameplayCoordinates[obj]
end

local Config = HV.Config
local function normalizeLayout(layout, defaults)
	if type(layout) ~= "table" then layout = {} end
	local result = {}
	for keymode, modeDefaults in pairs(defaults) do
		local saved = type(layout[keymode]) == "table" and layout[keymode] or layout
		local values = {}
		for key, default in pairs(modeDefaults) do
			values[key] = Config.IsFinite(saved[key]) and saved[key] or default
		end
		result[keymode] = values
	end
	return result
end

local function normalizePlayer(data)
	for key in pairs(Config.GameplayHUD) do
		data[key] = Config.NormalizeGameplayHUD(key, data[key])
	end
	data.CustomizeGameplay = nil
	data.PracticeMode = nil
	for key, default in pairs(defaultConfig) do
		local value = data[key]
		if type(default) == "table" then
			data[key] = normalizeLayout(value, default)
		elseif type(value) ~= type(default) or (type(value) == "number" and not Config.IsFinite(value)) then
			data[key] = default
		end
	end
	return data
end

local profiles = Config.CreateStore("playerConfig.lua", defaultConfig, normalizePlayer)
local guestHUD = {}

Config.Player = {
	Get = function(pn, key)
		local hud = Config.GameplayHUD[key]
		if not hud and defaultConfig[key] == nil then return nil end
		local directory = Config.ProfileDirectory(pn)
		local data = directory and profiles.Get(directory) or (hud and guestHUD or defaultConfig)
		local value = data[key]
		if hud and value == nil then
			if directory then value = Config.NormalizeGameplayHUD(key, Config.Theme.Get(key)) end
			if value == nil then value = hud.Default end
		end
		return type(value) == "table" and DeepCopy(value) or value
	end,
	Set = function(pn, key, value, directory)
		directory = directory or Config.ProfileDirectory(pn)
		if Config.GameplayHUD[key] then
			value = Config.NormalizeGameplayHUD(key, value)
			if value == nil then return false end
			if directory then
				profiles.Set(directory, key, value)
			else
				guestHUD[key] = value
			end
			return true
		end
		local default = defaultConfig[key]
		if not directory or default == nil or type(value) ~= type(default) then return false end
		if type(value) == "table" then
			for keymode, values in pairs(value) do
				if not default[keymode] or type(values) ~= "table" then return false end
				for field, number in pairs(values) do
					if not default[keymode][field] or not Config.IsFinite(number) then return false end
				end
			end
			value = normalizeLayout(value, default)
		elseif type(value) == "number" and not Config.IsFinite(value) then
			return false
		end
		profiles.Set(directory, key, value)
		return true
	end,
	Save = function(pn, directory)
		directory = directory or Config.ProfileDirectory(pn)
		if not directory then return false end
		return profiles.Save(directory)
	end,
}

local customizationProfile
function HV.IsGameplayCustomizationEnabled()
	return customizationProfile ~= nil and customizationProfile == Config.ProfileDirectory(PLAYER_1)
end

function HV.SetGameplayCustomization(enabled)
	customizationProfile = enabled and Config.ProfileDirectory(PLAYER_1) or nil
end
