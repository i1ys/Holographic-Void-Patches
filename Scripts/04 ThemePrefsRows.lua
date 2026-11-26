local ThemePrefs = HV.LegacyPrefs

-- Helper for 1% - 250% choices
local RSChoices = {}
for i = 1, 250 do
	RSChoices[i] = tostring(i) .. "%"
end

-- ReceptorSize OptionRow (Til' Death style)
function OptionRowMini()
	return {
		Name = "Mini",
		LayoutType = "ShowAllInRow",
		SelectType = "SelectOne",
		OneChoiceForAllPlayers = true,
		-- Persist the receptor scale immediately.  This row is used from the
		-- player-options screen immediately before starting a song, so waiting
		-- for a later export can leave the setting at its default (100%).
		ExportOnChange = true,
		ExportOnCancel = true,
		Choices = RSChoices,
		LoadSelections = function(self, list, pn)
			local prefs = tonumber(ThemePrefs.Get("HV_Mini")) or 100
			-- Ensure index is within range [1, 250]
			local idx = math.max(1, math.min(math.floor(prefs), 250))
			list[idx] = true
		end,
		SaveSelections = function(self, list, pn)
			for i = 1, #list do
				if list[i] then
					ThemePrefs.Set("HV_Mini", i)
					ThemePrefs.Save()
					break
				end
			end
		end
	}
end

-- Build an Etterna Lua option row from the same definition used by the store.
function HV.OptionRow(name, title, config)
	local settings = HV.Config
	local definition = assert(settings.GetThemePreference(name), "Unknown theme preference: " .. name)
	local prefs = config or ThemePrefs
	local hud = settings.GameplayHUD[name]
	local choices = DeepCopy(definition.Choices)
	local values = DeepCopy(definition.Values)
	local profileDirectory

	local function findChoice(value)
		for i, choice in ipairs(values) do
			if choice == value then return i end
		end
	end

	if definition.PercentScale then
		local current = prefs.Get(name)
		if not findChoice(current) then
			values[#values + 1] = current
			choices[#choices + 1] = tostring(current * definition.PercentScale) .. "%"
		end
	end

	return {
		Name = name,
		Title = title or name,
		Choices = choices,
		LayoutType = "ShowAllInRow",
		SelectType = "SelectOne",
		OneChoiceForAllPlayers = true,
		ExportOnChange = true,
		LoadSelections = function(self, list, pn)
			if hud then profileDirectory = settings.ProfileDirectory(PLAYER_1) or false end
			local index = findChoice(prefs.Get(name)) or findChoice(definition.Default)
			list[index] = true
		end,
		SaveSelections = function(self, list, pn)
			local value
			for i, selected in ipairs(list) do
				if selected then
					value = values[i]
					break
				end
			end
			if value == nil then return end

			local ok, err
			if hud then
				local directory = settings.ProfileDirectory(PLAYER_1)
				if profileDirectory ~= nil and profileDirectory ~= (directory or false) then return end
				ok = settings.Player.Set(PLAYER_1, name, value, directory)
				if ok and directory then ok, err = settings.Player.Save(PLAYER_1, directory) end
			else
				ok, err = prefs.Set(name, value)
				if ok and config then ok, err = config.Save() end
			end
			if not ok and err then SCREENMAN:SystemMessage(err) end
			MESSAGEMAN:Broadcast("ThemePrefChanged", {Name = name})
			if (name == "HV_LaneCoverSudden" or name == "HV_LaneCoverHidden") and HV.ApplyLaneCoverModifiers then
				HV.ApplyLaneCoverModifiers()
			end
		end,
	}
end

function OptionRowSongPreview()
	return HV.OptionRow("HV_SongPreview", "Song Preview Mode")
end
_G["OptionRowSongPreview"] = OptionRowSongPreview


function OptionRowSongSelectBGM()
	return HV.OptionRow("HV_SongSelectBGM", "Song Select BGM")
end
_G["OptionRowSongSelectBGM"] = OptionRowSongSelectBGM

function OptionRowShowMSD()
	return HV.OptionRow("HV_ShowMSD", "Show MSD Ratings")
end

function OptionRowShowProfileStats()
	return HV.OptionRow("HV_ShowProfileStats", "Show Profile Stats")
end

function OptionRowInstantSearch()
	return HV.OptionRow("HV_InstantSearch", "Instant Search", HV.Config.Theme)
end

function OptionRowShowNPS()
	return HV.OptionRow("HV_ShowNPS", "Show NPS")
end

function OptionRowShowMean()
	return HV.OptionRow("HV_ShowMean", "Mean Display")
end

function OptionRowPacemakerType()
	return HV.OptionRow("HV_PacemakerTargetType", "Pacemaker Target Type")
end

function OptionRowPacemakerGoal()
	return HV.OptionRow("HV_PacemakerTargetGoal", "Pacemaker Target Goal")
end

function OptionRowShowGoalTracker()
	return HV.OptionRow("HV_ShowGoalTracker", "Goal Tracker")
end


-- ScreenPlayerOptions Helpers
function OptionRowScreenFilter()
	return HV.OptionRow("HV_ScreenFilter", "Screen Filter")
end

function OptionRowLaneCoverSudden()
	return HV.OptionRow("HV_LaneCoverSudden", "Sudden Height")
end

function OptionRowLaneCoverHidden()
	return HV.OptionRow("HV_LaneCoverHidden", "Hidden Height")
end

function OptionRowErrorBarMode()
	return HV.OptionRow("HV_ErrorBarMode", "Error Bar Mode")
end

function OptionRowErrorBarColoringMode()
	return HV.OptionRow("HV_ErrorBarColoringMode", "Error Bar Coloring")
end

function OptionRowProgressBarPosition()
	return HV.OptionRow("HV_ProgressBarPosition", "Progress Bar Position")
end

function OptionRowShowJudgment()
	return HV.OptionRow("HV_ShowJudgment", "Show Judgment")
end

function OptionRowShowCombo()
	return HV.OptionRow("HV_ShowCombo", "Show Combo")
end

function OptionRowShowCurrentWife()
	return HV.OptionRow("HV_ShowCurrentWife", "Show Current %")
end

function OptionRowShowJudgeCounter()
	return HV.OptionRow("HV_ShowJudgeCounter", "Show Judge Counter")
end

function OptionRowShowPlayerInfo()
	return HV.OptionRow("HV_ShowPlayerInfo", "Show Player Info")
end

function OptionRowShowInGameLeaderboard()
	return HV.OptionRow("HV_ShowInGameLeaderboard", "In-Game Leaderboard")
end

function OptionRowShowNPSGraph()
	return HV.OptionRow("HV_ShowNPSGraph", "Show NPS Graph")
end

function OptionRowComboBreakHighlight()
	return HV.OptionRow("HV_ComboBreakHighlight", "Combo Break Highlight")
end

function OptionRowAssistMode()
	return HV.OptionRow("HV_AssistMode", "Assist Clap")
end

function OptionRowGoalTrackerText()
	return HV.OptionRow("HV_GoalTrackerText", "Goal Tracker Text")
end

function OptionRowMinimalisticMode()
	return HV.OptionRow("HV_MinimalisticMode", "Minimalistic Mode")
end

function OptionRowJudgeCounterMode()
	return HV.OptionRow("HV_JudgeCounterMode", "Judgment Tally Mode")
end

function OptionRowShowNGIndicator()
	return HV.OptionRow("HV_ShowNGIndicator", "Show NG Indicator")
end

function OptionRowPrioritizeLowerJudgements()
	return HV.OptionRow("HV_PrioritizeLowerJudgements", "Prioritize Lower Judgements")
end

function OptionRowJudgmentAnimation()
	return HV.OptionRow("HV_JudgmentAnimation", "Judgment Animation")
end

function OptionRowComboAnimation()
	return HV.OptionRow("HV_ComboAnimation", "Combo Animation")
end

-- Custom Brightness row backed by Etterna's internal BGBrightness preference.
function OptionRowSongBackgroundBrightness()
	local row = {
		Name = "HV_SongBackgroundBrightness",
		Title = "Background Brightness",
		LayoutType = "ShowAllInRow",
		SelectType = "SelectOne",
		OneChoiceForAllPlayers = true,
		ExportOnChange = true,
		Choices = {"0%", "10%", "20%", "30%", "40%", "50%", "60%", "70%", "80%", "90%", "100%"},
	}
	row.LoadSelections = function(self, list, pn)
		local brightness = tonumber(PREFSMAN:GetPreference("BGBrightness")) or 1.0
		local index = math.max(1, math.min(11, math.floor((brightness * 10) + 0.5) + 1))
		list[index] = true
	end
	row.SaveSelections = function(self, list, pn)
		for i = 1, #self.Choices do
			if list[i] then
				local brightness = (i - 1) / 10
				PREFSMAN:SetPreference("BGBrightness", brightness)
				PREFSMAN:SavePreferences()
				break
			end
		end
	end
	return row
end

-- Customize Gameplay toggle (used in ScreenPlayerOptions)
function OptionRowCustomizeGameplay()
	return {
		Name = "HV_CustomizeGameplay",
		LayoutType = "ShowAllInRow",
		SelectType = "SelectOne",
		OneChoiceForAllPlayers = true,
		ExportOnChange = true,
		Choices = {"Off", "On"},
		LoadSelections = function(self, list, pn)
			local enabled = HV.IsGameplayCustomizationEnabled()
			if enabled then
				list[2] = true
			else
				list[1] = true
			end
		end,
		SaveSelections = function(self, list, pn)
			HV.SetGameplayCustomization(list[2])
			if not list[2] then GAMESTATE:SetAutoplay(false) end
		end
	}
end
_G["OptionRowCustomizeGameplay"] = OptionRowCustomizeGameplay

function OptionRowMiniProgressBar()
	return HV.OptionRow("HV_MiniProgressBar", "Mini Progress Bar")
end
_G["OptionRowMiniProgressBar"] = OptionRowMiniProgressBar

-- Practice Mode toggle (used in ScreenPlayerOptions)
function PracticeMode()
	return {
		Name = "PracticeMode",
		LayoutType = "ShowAllInRow",
		SelectType = "SelectOne",
		OneChoiceForAllPlayers = true,
		ExportOnChange = true,
		Choices = {"Off", "On"},
		LoadSelections = function(self, list, pn)
			if GAMESTATE:IsPracticeMode() then
				list[2] = true
			else
				list[1] = true
			end
		end,
		SaveSelections = function(self, list, pn)
			if list[2] then
				GAMESTATE:SetPracticeMode(true)
			else
				GAMESTATE:SetPracticeMode(false)
			end
		end
	}
end
_G["PracticeMode"] = PracticeMode

-- Listen for pref changes and refresh accent color
local function OnThemePrefChanged(params)
	if params and params.Name == "HV_AccentColor" then
		if HVColor and HVColor.RefreshAccent then
			HVColor.RefreshAccent()
		end
		if HVCustomColors and HVCustomColors.SyncAccentLinkedColors then
			HVCustomColors.SyncAccentLinkedColors(ThemePrefs.Get("HV_AccentColor"))
		end
	end
end

-- Hook into the broadcast system
-- This is called from _Fallback when a ThemePref is saved
if MESSAGEMAN then
	-- We can't directly subscribe here, but themes handle this
	-- via the ThemePrefChangedMessageCommand on actors
end

Trace("Holographic Void: 04 ThemePrefsRows.lua loaded.")
