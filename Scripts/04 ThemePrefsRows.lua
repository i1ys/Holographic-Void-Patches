local ThemePrefs = HV.LegacyPrefs

--- Holographic Void: ThemePrefs Option Rows
-- @module 04_ThemePrefsRows
-- Defines option row handlers for the in-client ThemePrefs system.
-- These rows appear in ScreenOptionsService when theme options are accessed.
-- Uses _Fallback's ThemePrefsRows.Init system.

-- Generate 5% increment tables for Lane Cover heights (0-100%)
local laneCoverChoices = {"Off"}
local laneCoverValues = {0}
for i = 1, 20 do
	local val = i * 5
	table.insert(laneCoverChoices, tostring(val) .. "%")
	table.insert(laneCoverValues, val)
end

local HVPrefRows = {
	-- Auto Login Tokens (Secret, non-visible in menu)
	HV_Username = {
		Default = "",
		Choices = {""},
		Values  = {""},
	},
	HV_PasswordToken = {
		Default = "",
		Choices = {""},
		Values  = {""},
	},


	-- Background Animation Intensity
	HV_BGAnimIntensity = {
		Default = 1,
		Choices = {"Off", "Subtle", "Full"},
		Values = {0, 1, 2},
	},

	-- Mouse Parallax
	HV_Parallax = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true},
	},

	-- Song Preview Mode
	HV_SongPreview = {
		Default = 1,
		Choices = {"SM Style", "osu! Style (New)", "osu! Style (Old)"},
		Values = {1, 2, 3},
	},

	-- Song Select BGM
	HV_SongSelectBGM = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true},
	},


	-- Show MSD Ratings
	HV_ShowMSD = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true},
	},


	-- Show Profile Stats on Select Music
	HV_ShowProfileStats = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true},
	},




	-- Show Measure Lines
	HV_ShowMeasureLines = {
		Default = false,
		Choices = {"Off", "On"},
		Values = {false, true},
	},

	-- Screen Filter
	HV_ScreenFilter = {
		Default = 0.0,
		Choices = {"0%", "10%", "20%", "30%", "40%", "50%", "60%", "70%", "80%", "90%", "100%"},
		Values = {0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0},
	},

	-- Lane Cover
	HV_LaneCoverSudden = {
		Default = 0,
		Choices = laneCoverChoices,
		Values = laneCoverValues,
	},
	HV_LaneCoverHidden = {
		Default = 0,
		Choices = laneCoverChoices,
		Values = laneCoverValues,
	},

	-- Glow Effects
	HV_EnableGlow = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true},
	},

	-- Show NPS
	HV_ShowNPS = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true},
	},

	-- NPS Window Size
	HV_NPSWindowSize = {
		Default = 1,
		Choices = {"1s", "2s", "3s", "4s", "5s"},
		Values = {1, 2, 3, 4, 5},
	},

	-- Error Bar Mode
	HV_ErrorBarMode = {
		Default = "Standard",
		Choices = {"Off", "Standard", "EWMA Only", "Both"},
		Values  = {"Off", "Standard", "EWMAOnly", "Both"},
	},

	-- Error Bar Coloring Mode
	HV_ErrorBarColoringMode = {
		Default = "Current",
		Choices = {"J4", "Current Judge"},
		Values  = {"J4", "Current"},
	},


	-- Show Mini Text Goal Tracker (formerly Pacemaker)
	HV_ShowGoalTracker = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true},
	},

	-- Pacemaker Target Type
	HV_PacemakerTargetType = {
		Default = "Target",
		Choices = {"Target", "PB", "PB Replay"},
		Values  = {"Target", "PB", "PBReplay"},
	},

	-- Pacemaker Target Goal
	HV_PacemakerTargetGoal = {
		Default = 93,
		Choices = {
			"0%", "1%", "2%", "3%", "4%", "5%", "6%", "7%", "8%", "9%", "10%",
			"11%", "12%", "13%", "14%", "15%", "16%", "17%", "18%", "19%", "20%",
			"21%", "22%", "23%", "24%", "25%", "26%", "27%", "28%", "29%", "30%",
			"31%", "32%", "33%", "34%", "35%", "36%", "37%", "38%", "39%", "40%",
			"41%", "42%", "43%", "44%", "45%", "46%", "47%", "48%", "49%", "50%",
			"51%", "52%", "53%", "54%", "55%", "56%", "57%", "58%", "59%", "60%",
			"61%", "62%", "63%", "64%", "65%", "66%", "67%", "68%", "69%", "70%",
			"71%", "72%", "73%", "74%", "75%", "76%", "77%", "78%", "79%", "80%",
			"81%", "82%", "83%", "84%", "85%", "86%", "87%", "88%", "89%", "90%",
			"91%", "92%", "93%", "94%", "95%", "96%", "97%", "98%", "99%",
			"99.50%", "99.70%", "99.80%", "99.90%", "99.95%",
			"99.96%", "99.97%", "99.98%", "99.99%",
			"99.990%", "99.991%", "99.992%", "99.993%", "99.994%",
			"99.995%", "99.996%", "99.997%", "99.998%", "99.999%", "100%"
		},
		Values = {
			0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
			11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
			21, 22, 23, 24, 25, 26, 27, 28, 29, 30,
			31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
			41, 42, 43, 44, 45, 46, 47, 48, 49, 50,
			51, 52, 53, 54, 55, 56, 57, 58, 59, 60,
			61, 62, 63, 64, 65, 66, 67, 68, 69, 70,
			71, 72, 73, 74, 75, 76, 77, 78, 79, 80,
			81, 82, 83, 84, 85, 86, 87, 88, 89, 90,
			91, 92, 93, 94, 95, 96, 97, 98, 99,
			99.50, 99.70, 99.80, 99.90, 99.95,
			99.96, 99.97, 99.98, 99.99,
			99.990, 99.991, 99.992, 99.993, 99.994,
			99.995, 99.996, 99.997, 99.998, 99.999, 100
		},
	},

	-- Show Particles
	HV_Particles = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true},
	},

	-- Show Mean on Notefield
	HV_ShowMean = {
		Default = "Mean",
		Choices = {"Off", "Mean", "Tap Offset", "Std Dev", "MA Ratio", "Delta Hand"},
		Values = {"Off", "Mean", "TapOffset", "StdDev", "MARatio", "DeltaHand"},
	},
	
	-- Accent Color
	HV_AccentColor = {
		Default = "#5ABAFF",
		Choices = {"Blue", "Pink", "Mint", "Orange", "Purple", "White"},
		Values  = {"#5ABAFF", "#FF5ABB", "#5AFFBA", "#FFBA5A", "#BA5AFF", "#D9D9D9"},
	},

	-- Use Custom Grade Names (from grade.costom.md)
	HV_UseCustomGrades = {
		Default = false,
		Choices = {"Off", "On"},
		Values = {false, true},
	},


	
	-- Background Effect Style

	-- Title Screen Text Mode
	HV_QuotesMode = {
		Default = "Quotes",
		Choices = {"Off", "Quotes", "Tips"},
		Values  = {"Off", "Quotes", "Tips"},
	},

	-- Gameplay HUD Customization
	HV_ShowJudgment = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true},
	},
	HV_ShowCombo = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true},
	},
	HV_ShowCurrentWife = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true},
	},
	HV_ShowJudgeCounter = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true},
	},
	HV_ShowPlayerInfo = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true},
	},
	HV_ProgressBarPosition = {
		Default = "Top",
		Choices = {"Top", "Bottom", "Off"},
		Values = {"Top", "Bottom", "Off"},
	},
	HV_ShowInGameLeaderboard = {
		Default = "Off",
		Choices = {"Off", "Local", "Online"},
		Values = {"Off", "Local", "Online"},
	},
	HV_ShowNPSGraph = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true},
	},
	HV_ComboBreakHighlight = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true},
	},
	HV_AssistMode = {
		Default = "Off",
		Choices = {"Off", "Clap", "Metronome", "Both"},
		Values = {"Off", "Clap", "Metronome", "Both"},
	},
	HV_GoalTrackerText = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true},
	},

	-- Minimalistic Mode
	HV_MinimalisticMode = {
		Default = false,
		Choices = {"Off", "On"},
		Values = {false, true},
	},

	-- Judgment Tally Mode
	HV_JudgeCounterMode = {
		Default = "Full",
		Choices = {"Full", "Simple"},
		Values = {"Full", "Simple"},
	},

	-- NG Indicator
	HV_ShowNGIndicator = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true},
	},
	-- Instant Search
	HV_InstantSearch = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true},
	},

	-- Prioritize Lower Judgements
	HV_PrioritizeLowerJudgements = {
		Default = false,
		Choices = {"Off", "On"},
		Values = {false, true},
	},

	-- Display Lower Judgement Offset
	HV_DisplayLowerJudgementOffset = {
		Default = false,
		Choices = {"Off", "On"},
		Values = {false, true},
	},

	-- Offset Display Judgement
	HV_OffsetDisplayJudgement = {
		Default = "W3",
		Choices = {"Marvelous", "Perfect", "Great", "Good", "Bad"},
		Values = {"W1", "W2", "W3", "W4", "W5"},
	},

	-- Judgment Animation
	HV_JudgmentAnimation = {
		Default = false,
		Choices = {"Off", "On"},
		Values = {false, true},
	},

	-- Combo Animation
	HV_ComboAnimation = {
		Default = false,
		Choices = {"Off", "On"},
		Values = {false, true},
	},

	-- Recent Judgement Display
	HV_RecentJudgmentDisplay = {
		Default = false,
		Choices = {"Off", "On"},
		Values = {false, true},
	},


	-- Auto-Fail Action Mode
	HV_AutoFailMode = {
		Default = "Off",
		Choices = {"Off", "Fail", "Restart"},
		Values = {"Off", "Fail", "Restart"},
	},

	-- Auto-Fail Trigger Condition
	HV_AutoFailCondition = {
		Default = "Wife Percent",
		Choices = {"Wife Percent", "Sync to Goal", "Judgement Count", "Personal Best"},
		Values = {"Wife Percent", "Sync to Goal", "Judgement Count", "Personal Best"},
	},

	-- Auto-Fail Judgement
	HV_AutoFailJudgement = {
		Default = "Miss",
		Choices = {"Perfect", "Great", "Good", "Bad", "Miss"},
		Values = {"W2", "W3", "W4", "W5", "Miss"},
	},

	-- Auto-Fail Threshold Wife Percent
	HV_AutoFailThreshold_Wife = {
		Default = 93,
		Choices = {
			"0%", "1%", "2%", "3%", "4%", "5%", "6%", "7%", "8%", "9%", "10%",
			"11%", "12%", "13%", "14%", "15%", "16%", "17%", "18%", "19%", "20%",
			"21%", "22%", "23%", "24%", "25%", "26%", "27%", "28%", "29%", "30%",
			"31%", "32%", "33%", "34%", "35%", "36%", "37%", "38%", "39%", "40%",
			"41%", "42%", "43%", "44%", "45%", "46%", "47%", "48%", "49%", "50%",
			"51%", "52%", "53%", "54%", "55%", "56%", "57%", "58%", "59%", "60%",
			"61%", "62%", "63%", "64%", "65%", "66%", "67%", "68%", "69%", "70%",
			"71%", "72%", "73%", "74%", "75%", "76%", "77%", "78%", "79%", "80%",
			"81%", "82%", "83%", "84%", "85%", "86%", "87%", "88%", "89%", "90%",
			"91%", "92%", "93%", "94%", "95%", "96%", "97%", "98%", "99%",
			"99.50%", "99.60%", "99.70%", "99.80%", "99.90%", "99.95%", "99.955%",
			"99.96%", "99.97%", "99.98%", "99.99%",
			"99.990%", "99.991%", "99.992%", "99.993%", "99.9935%", "99.994%",
			"99.995%", "99.996%", "99.997%", "99.998%", "99.999%", "100%"
		},
		Values = {
			0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
			11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
			21, 22, 23, 24, 25, 26, 27, 28, 29, 30,
			31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
			41, 42, 43, 44, 45, 46, 47, 48, 49, 50,
			51, 52, 53, 54, 55, 56, 57, 58, 59, 60,
			61, 62, 63, 64, 65, 66, 67, 68, 69, 70,
			71, 72, 73, 74, 75, 76, 77, 78, 79, 80,
			81, 82, 83, 84, 85, 86, 87, 88, 89, 90,
			91, 92, 93, 94, 95, 96, 97, 98, 99,
			99.50, 99.60, 99.70, 99.80, 99.90, 99.95, 99.955,
			99.96, 99.97, 99.98, 99.99,
			99.990, 99.991, 99.992, 99.993, 99.9935, 99.994,
			99.995, 99.996, 99.997, 99.998, 99.999, 100
		},
	},

	-- Auto-Fail Judgement Limit 0 to 99
	HV_AutoFailThreshold_Count = {
		Default = 10,
		Choices = (function() local c = {}; for i=0, 99 do c[#c+1]=tostring(i) end return c end)(),
		Values = (function() local v = {}; for i=0, 99 do v[#v+1]=i end return v end)(),
	},
	-- Emulate Ridiculous Judgement
	HV_EmulateRidiculous = {
		Default = false,
		Choices = {"Off", "On"},
		Values = {false, true},
	},
} -- End of HVPrefRows

-- Register the rows with the _Fallback ThemePrefsRows system
ThemePrefsRows.Init(HVPrefRows)

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

-- Adapt the fallback option row to HV2's theme or active-profile store.
function HV.OptionRow(name, title, config)
	local baseRow = ThemePrefRow(name, title)
	local row = baseRow and DeepCopy(baseRow)
	local prefs = config or ThemePrefs
	local hud = HV.Config.GameplayHUD[name]
	local hvPref = hud or HVPrefRows[name]
	local profileDirectory
	
	if not row then
		row = {
			Name = name,
			Title = title or name,
			Choices = (hvPref and hvPref.Choices) or {"Off", "On"},
			Values = (hvPref and hvPref.Values) or {false, true},
		}
	elseif hvPref then
		row.Choices = hvPref.Choices
		row.Values = hvPref.Values
	end
	-- ThemePrefRow may omit layout metadata for custom rows; the options
	-- screen requires this to be a string.
	row.LayoutType = "ShowAllInRow"
	row.SelectType = "SelectOne"
	if hud then row.OneChoiceForAllPlayers = true end
	
	row.ExportOnChange = true
	
	-- Define a robust load function that handles string/boolean mismatch
	row.LoadSelections = function(self, list, pn)
		local val
		if hud then
			profileDirectory = HV.Config.ProfileDirectory(PLAYER_1) or false
			val = HV.Config.Player.Get(PLAYER_1, name)
		else
			val = prefs.Get(name)
		end
		local found = false
		for i, v in ipairs(self.Values) do
			if v == val or tostring(v) == tostring(val) then
				list[i] = true
				found = true
				break
			end
		end
		-- If not found, default based on truthiness or fallback to first index
		if not found then
			if val == "true" or val == true or val == 1 or val == "1" then
				list[#list] = true -- Usually 'On'
			else
				list[1] = true -- Usually 'Off'
			end
		end
	end

	-- Define a robust save function that ensures disk persistence
	row.SaveSelections = function(self, list, pn)
		local val = nil
		for i, selected in ipairs(list) do
			if selected then
				val = self.Values[i]
				break
			end
		end
		if val == nil then return end
		local ok, err
		if hud then
			local directory = HV.Config.ProfileDirectory(PLAYER_1)
			if profileDirectory ~= nil and profileDirectory ~= (directory or false) then return end
			ok = HV.Config.Player.Set(PLAYER_1, name, val, directory)
			if ok and directory then ok, err = HV.Config.Player.Save(PLAYER_1, directory) end
		else
			ok, err = prefs.Set(name, val)
			if ok and config then ok, err = config.Save() end
		end
		if not ok and err then SCREENMAN:SystemMessage(err) end
		MESSAGEMAN:Broadcast("ThemePrefChanged", {Name = name})
		if (name == "HV_LaneCoverSudden" or name == "HV_LaneCoverHidden")
			and HV and HV.ApplyLaneCoverModifiers then
			HV.ApplyLaneCoverModifiers()
		end
	end
	
	return row
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

function OptionRowEmulateRidiculous()
	return HV.OptionRow("HV_EmulateRidiculous", "Emulate Ridiculous")
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

function OptionRowDisplayLowerJudgementOffset()
	return HV.OptionRow("HV_DisplayLowerJudgementOffset", "Display Lower Judgement Offset")
end

function OptionRowOffsetDisplayJudgement()
	return HV.OptionRow("HV_OffsetDisplayJudgement", "Offset Display Judgement")
end

function OptionRowJudgmentAnimation()
	return HV.OptionRow("HV_JudgmentAnimation", "Judgment Animation")
end

function OptionRowComboAnimation()
	return HV.OptionRow("HV_ComboAnimation", "Combo Animation")
end

function OptionRowRecentJudgmentDisplay()
	return HV.OptionRow("HV_RecentJudgmentDisplay", "Recent Judgement Display")
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

-- Auto-Fail / Restart Option Rows for ScreenPlayerOptions
function OptionRowAutoFailMode()
	return HV.OptionRow("HV_AutoFailMode", "Auto-Fail/Restart Action")
end
function OptionRowAutoFailCondition()
	return HV.OptionRow("HV_AutoFailCondition", "Auto-Fail Condition")
end
function OptionRowAutoFailJudgement()
	return HV.OptionRow("HV_AutoFailJudgement", "Judgement Criteria")
end
function OptionRowAutoFailThresholdWife()
	return HV.OptionRow("HV_AutoFailThreshold_Wife", "Wife% Threshold")
end
function OptionRowAutoFailThresholdCount()
	return HV.OptionRow("HV_AutoFailThreshold_Count", "Judgement Limit")
end

Trace("Holographic Void: 04 ThemePrefsRows.lua loaded.")
