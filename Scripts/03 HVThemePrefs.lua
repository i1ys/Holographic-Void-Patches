-- Generate 5% increment tables for Lane Cover heights (0-100%)
local laneCoverChoices = {"Off"}
local laneCoverValues = {0}
for i = 1, 20 do
	local val = i * 5
	table.insert(laneCoverChoices, tostring(val) .. "%")
	table.insert(laneCoverValues, val)
end

-- Preference definitions: each key maps to a table with a Default value.
local HVPrefs = {
	-- Offset Graph: Hover mode (Point or Slice)
	HV_OffsetGraphHoverMode = {
		Default = "point",
		Choices = {"Point", "Slice"},
		Values = {"point", "slice"}
	},

	-- Offset Graph: Slice width percent (1-100)
	HV_OffsetGraphSlicePercent = {
		Default = 25,
		Choices = (function() local c={}; for i=1,100 do c[i]=tostring(i).."%" end return c end)(),
		Values = (function() local v={}; for i=1,100 do v[i]=i end return v end)()
	},

	-- Offset Graph: Trend metric mode
	HV_OffsetGraphTrendMetric = {
		Default = "wife",
		Choices = {"Tap Wife%", "Tap Grade", "Tap Clear", "Mean", "MA", "PA", "Off"},
		Values = {"wife", "grade", "clear", "mean", "ma", "pa", "off"}
	},

	-- Offset Graph: Trend color mode
	HV_OffsetGraphTrendColor = {
		Default = "none",
		Choices = {"None", "Grade", "Clear Type"},
		Values = {"none", "grade", "clear"}
	},

	-- Visual: Background animation intensity (0 = off, 1 = subtle, 2 = full)
	HV_BGAnimIntensity = {
		Default = 1,
		Choices = {"Off", "Subtle", "Full"},
		Values = {0, 1, 2}
	},

	-- Gameplay: Show MSD ratings on music wheel
	HV_ShowMSD = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true}
	},


	-- Gameplay: Show player profile stats on select music
	HV_ShowProfileStats = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true}
	},

	-- Gameplay: Song Preview Mode (1: SM, 2: osu! New, 3: osu! Old)
	HV_SongPreview = {
		Default = 1,
		Choices = {"SM Style", "osu! Style (New)", "osu! Style (Old)"},
		Values = {1, 2, 3}
	},

	-- Music Select: Play looping BGM track on ScreenSelectMusic (imported from Til Death)
	HV_SongSelectBGM = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true}
	},

	-- Visual: Enable glow/bloom effects on active elements
	HV_EnableGlow = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true}
	},

	-- Gameplay: Show measure divider lines
	HV_ShowMeasureLines = {
		Default = false,
		Choices = {"Off", "On"},
		Values = {false, true}
	},

	-- Gameplay: UI/Background Dim (0.0 - 1.0)
	HV_ScreenFilter = {
		Default = 0.0,
		PercentScale = 100,
		Choices = {"0%", "10%", "20%", "30%", "40%", "50%", "60%", "70%", "80%", "90%", "100%"},
		Values = {0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0},
	},

	-- Compatibility mirror of Etterna's global BGBrightness preference.
	-- BGBrightness remains the source of truth and the user-facing option.
	HV_SongBackgroundBrightness = {
		Default = 1.0,
		PercentScale = 100,
		Choices = {"0%", "10%", "20%", "30%", "40%", "50%", "60%", "70%", "80%", "90%", "100%"},
		Values = {0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0},
	},

	-- Gameplay: Sudden Lane Cover height (0-100)
	HV_LaneCoverSudden = {
		Default = 0,
		PercentScale = 1,
		Choices = laneCoverChoices,
		Values = laneCoverValues,
	},

	-- Gameplay: Hidden Lane Cover height (0-100)
	HV_LaneCoverHidden = {
		Default = 0,
		PercentScale = 1,
		Choices = laneCoverChoices,
		Values = laneCoverValues,
	},

	-- Gameplay: Toggle real-time NPS display
	HV_ShowNPS = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true}
	},

	-- Gameplay: NPS Window Size (seconds)
	HV_NPSWindowSize = {
		Default = 1,
		Choices = {"1s", "2s", "3s", "4s", "5s"},
		Values = {1, 2, 3, 4, 5}
	},

	-- Gameplay: Error Bar Mode (Off, Standard, EWMA Only, Both)
	HV_ErrorBarMode = {
		Default = "Standard",
		Choices = {"Off", "Standard", "EWMA Only", "Both"},
		Values = {"Off", "Standard", "EWMAOnly", "Both"}
	},

	-- Gameplay: Error Bar Coloring Mode (J4 or Current Judge)
	HV_ErrorBarColoringMode = {
		Default = "Current",
		Choices = {"J4", "Current Judge"},
		Values = {"J4", "Current"}
	},


	-- Gameplay: Mini Pacemaker Target Type
	HV_PacemakerTargetType = {
		Default = "Target",
		Choices = {"Target", "PB", "PB Replay"},
		Values = {"Target", "PB", "PBReplay"}
	},

	-- Gameplay: Mini Pacemaker Target Goal (percentage)
	HV_PacemakerTargetGoal = {
		Default = 93,
		PercentScale = 1,
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
			"99.991%", "99.992%", "99.993%", "99.9935%", "99.994%",
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
			99.991, 99.992, 99.993, 99.9935, 99.994,
			99.995, 99.996, 99.997, 99.998, 99.999, 100
		}
	},

	-- Gameplay: Toggle Mini Text Goal Tracker (formerly Pacemaker)
	HV_ShowGoalTracker = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true}
	},

	-- Gameplay: Goal Tracker Text
	HV_GoalTrackerText = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true}
	},

	-- Gameplay: Toggle target tracker comparison
	HV_ShowTargetTracker = { Default = false },

	-- Visual: Background/Menu particles
	HV_Particles = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true}
	},
	
	-- Gameplay: Show Hit Mean Display
	HV_ShowHitMean = {
		Default = "Mean",
		Choices = {"Off", "Mean", "Tap Offset", "Std Dev", "MA Ratio", "Delta Hand"},
		Values = {"Off", "Mean", "TapOffset", "StdDev", "MARatio", "DeltaHand"}
	},
	HV_MiniProgressBar = { Default = true, Choices = {"Off", "On"}, Values = {false, true} },

	-- Gameplay: Show Hit Mean Display (Legacy compatibility)
	HV_ShowMean = {
		Default = "Mean",
		Aliases = {J4 = "Mean"},
		Choices = {"Off", "Mean", "Tap Offset", "Std Dev", "MA Ratio", "Delta Hand"},
		Values = {"Off", "Mean", "TapOffset", "StdDev", "MARatio", "DeltaHand"}
	},

	-- Gameplay: Mini (Receptor Size)
	HV_Mini = { Default = 100 },

	-- Auth: Saved EtternaOnline username and login token
	HV_Username = { Default = "" },
	HV_PasswordToken = { Default = "" },

	-- Visual: Show scrolling quotes/tips on Title Screen
	HV_QuotesMode = {
		Default = "Quotes",
		Choices = {"Off", "Quotes", "Tips"},
		Values = {"Off", "Quotes", "Tips"}
	},

	-- Gameplay Customization: HUD Elements
	HV_ShowJudgment = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true}
	},
	HV_ShowCombo = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true}
	},
	HV_ShowCurrentWife = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true}
	},
	HV_ShowJudgeCounter = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true}
	},
	HV_ShowPlayerInfo = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true}
	},
	HV_ProgressBarPosition = {
		Default = "Top",
		Choices = {"Top", "Bottom", "Off"},
		Values = {"Top", "Bottom", "Off"}
	},
	HV_ShowInGameLeaderboard = {
		Default = "Off",
		Choices = {"Off", "Local", "Online"},
		Values = {"Off", "Local", "Online"}
	},
	HV_LastInGameLeaderboardMode = {
		Default = "Local",
		Choices = {"Local", "Online"},
		Values = {"Local", "Online"}
	},
	HV_ShowNPSGraph = {
		Default = true,
		Choices = {"Off", "On"},
		Values = {false, true}
	},
	HV_ComboBreakHighlight = {
		Default = false,
		Choices = {"Off", "On"},
		Values = {false, true}
	},

	-- Gameplay: Assist Mode (Off, Clap, Metronome, Both)
	HV_AssistMode = {
		Default = "Off",
		Choices = {"Off", "Clap", "Metronome", "Both"},
		Values = {"Off", "Clap", "Metronome", "Both"}
	},
	-- Gameplay: Minimalistic Mode
	HV_MinimalisticMode = {
		Default = false,
		Choices = {"Off", "On"},
		Values = {false, true}
	},

	-- Gameplay: Judgment Tally Mode
	HV_JudgeCounterMode = {
		Default = "Simple",
		Choices = {"Full", "Simple"},
		Values = {"Full", "Simple"}
	},

	-- Gameplay: NG Indicator
	HV_ShowNGIndicator = {
		Default = false,
		Choices = {"Off", "On"},
		Values = {false, true}
	},

	-- Gameplay: Prioritize Lower Judgements
	HV_PrioritizeLowerJudgements = {
		Default = false,
		Choices = {"Off", "On"},
		Values = {false, true}
	},

	-- Visual: Judgment Animation
	HV_JudgmentAnimation = {
		Default = false,
		Choices = {"Off", "On"},
		Values = {false, true}
	},

	-- Visual: Combo Animation
	HV_ComboAnimation = {
		Default = false,
		Choices = {"Off", "On"},
		Values = {false, true}
	},
}

local Config = HV.Config
-- Keep the global definitions readable as defaults for pre-migration HV2 profiles.
Config.GameplayHUD = {}
for _, key in ipairs({
	"HV_MinimalisticMode", "HV_ShowJudgment",
	"HV_JudgmentAnimation", "HV_PrioritizeLowerJudgements",
	"HV_ShowCombo", "HV_ComboAnimation", "HV_ShowCurrentWife", "HV_ShowJudgeCounter",
	"HV_JudgeCounterMode", "HV_ShowNGIndicator", "HV_ShowPlayerInfo",
	"HV_ProgressBarPosition", "HV_MiniProgressBar", "HV_ShowInGameLeaderboard",
	"HV_LastInGameLeaderboardMode", "HV_ShowNPS", "HV_NPSWindowSize",
	"HV_ShowNPSGraph", "HV_ErrorBarMode", "HV_ErrorBarColoringMode",
	"HV_ShowMean", "HV_ShowMeasureLines", "HV_ComboBreakHighlight",
	"HV_ShowGoalTracker", "HV_PacemakerTargetType", "HV_PacemakerTargetGoal",
}) do
	Config.GameplayHUD[key] = HVPrefs[key]
end

function Config.NormalizeGameplayHUD(key, value)
	local definition = Config.GameplayHUD[key]
	if not definition then return nil end
	return Config.NormalizePreference(definition, value)
end

Config.RegisterThemePreferences(HVPrefs)

local Theme = Config.Theme
local ThemePrefs = {
	Get = function(key)
		if Config.GameplayHUD[key] and Config.Player then
			return Config.Player.Get(PLAYER_1, key)
		end
		return Theme.Get(key)
	end,
	Save = Theme.Save,
	ForceSave = Theme.Save,
	Set = function(key, value)
		if Config.GameplayHUD[key] and Config.Player then
			if not Config.Player.Set(PLAYER_1, key, value) then return false end
			if not Config.ProfileDirectory(PLAYER_1) then return true end
			return Config.Player.Save(PLAYER_1)
		end
		if not Theme.Set(key, value) then return false end
		return Theme.Save()
	end,
}
HV.LegacyPrefs = ThemePrefs

-- ==========================================================================
-- Consistency Helpers
-- ==========================================================================
local function isTrue(val)
	return val == "true" or val == true
end

--- Get the current accent color as a color table.
function HV.GetAccentColor()
	return HVColor.Accent
end

--- Check if glow effects are enabled.
function HV.IsGlowEnabled()
	return isTrue(ThemePrefs.Get("HV_EnableGlow"))
end

--- Get background animation intensity (0, 1, or 2).
function HV.GetBGAnimIntensity()
	local val = tonumber(ThemePrefs.Get("HV_BGAnimIntensity"))
	return val and HV.Clamp(val, 0, 2) or 1
end

--- Check if MSD ratings should be shown.
function HV.ShowMSD()
	return isTrue(ThemePrefs.Get("HV_ShowMSD"))
end


--- Check if player profile stats should be shown.
function HV.ShowProfileStats()
	return isTrue(ThemePrefs.Get("HV_ShowProfileStats"))
end

--- Check if measure lines should be shown.
function HV.ShowMeasureLines()
	return isTrue(ThemePrefs.Get("HV_ShowMeasureLines"))
end

--- Check if judgment text should be shown.
function HV.ShowJudgment()
	return isTrue(ThemePrefs.Get("HV_ShowJudgment"))
end

--- Check if combo counter should be shown.
function HV.ShowCombo()
	return isTrue(ThemePrefs.Get("HV_ShowCombo"))
end

--- Check if current wife% should be shown during gameplay.
function HV.ShowCurrentWife()
	return isTrue(ThemePrefs.Get("HV_ShowCurrentWife"))
end

--- Check if judge counter should be shown.
function HV.ShowJudgeCounter()
	return isTrue(ThemePrefs.Get("HV_ShowJudgeCounter"))
end

--- Check if player info should be shown.
function HV.ShowPlayerInfo()
	return isTrue(ThemePrefs.Get("HV_ShowPlayerInfo"))
end

--- Get progress bar position (Top, Bottom, or Off).
function HV.GetProgressBarPosition()
	return ThemePrefs.Get("HV_ProgressBarPosition") or "Bottom"
end

--- Get in-game leaderboard mode ("Off", "Local", or "Online").
function HV.ShowInGameLeaderboard()
	local val = ThemePrefs.Get("HV_ShowInGameLeaderboard")
	-- Backwards compat: true -> "Local", false/nil -> "Off"
	if val == true or val == "true" then return "Local" end
	if val == false or val == "false" or val == nil then return "Off" end
	return val
end

--- Get Sudden lane cover height (0-100).
function HV.GetLaneCoverSudden()
	return tonumber(ThemePrefs.Get("HV_LaneCoverSudden")) or 0
end

--- Get Hidden lane cover height (0-100).
function HV.GetLaneCoverHidden()
	return tonumber(ThemePrefs.Get("HV_LaneCoverHidden")) or 0
end

--- Apply the theme's lane-cover settings through Etterna's native appearance
--- modifiers.  Keep every option level in sync so the setting survives the
--- transition from player options into gameplay.
function HV.ApplyLaneCoverModifiers()
	local ps = GAMESTATE:GetPlayerState(PLAYER_1)
	if not ps then return end

	local sudden = math.max(0, math.min(100, HV.GetLaneCoverSudden())) / 100
	local hidden = math.max(0, math.min(100, HV.GetLaneCoverHidden())) / 100
	local levels = {
		"ModsLevel_Preferred",
		"ModsLevel_Stage",
		"ModsLevel_Song",
		"ModsLevel_Current",
	}

	for _, level in ipairs(levels) do
		local po = ps:GetPlayerOptions(level)
		if po then
			po:Sudden(sudden > 0 and 1 or 0)
			po:SuddenOffset(sudden)
			po:Hidden(hidden > 0 and 1 or 0)
			po:HiddenOffset(hidden)
		end
	end
end

--- Check if real-time NPS should be shown.
function HV.ShowNPS()
	return isTrue(ThemePrefs.Get("HV_ShowNPS"))
end

--- Check if NPS graph should be shown.
function HV.ShowNPSGraph()
	return isTrue(ThemePrefs.Get("HV_ShowNPSGraph"))
end

--- Check if combo break lane highlighting is enabled.
function HV.ComboBreakHighlight()
	return isTrue(ThemePrefs.Get("HV_ComboBreakHighlight"))
end

--- Check if assist mode is enabled.
function HV.AssistMode()
	local val = ThemePrefs.Get("HV_AssistMode")
	return val ~= "Off" and val ~= nil
end

--- Get assist mode type.
function HV.GetAssistMode()
	return ThemePrefs.Get("HV_AssistMode") or "Off"
end

--- Check if goal tracker text should be shown.
function HV.ShowGoalTrackerText()
	return isTrue(ThemePrefs.Get("HV_ShowGoalTracker"))
end

--- Get Notefield Stat Display type
function HV.GetNotefieldStat()
	local val = ThemePrefs.Get("HV_ShowMean")
	if val == true or val == "true" or val == "J4" then return "Mean" end
	if val == false or val == "false" then return "Off" end
	return val or "Mean"
end

--- Check if minimalistic mode is enabled.
function HV.MinimalisticMode()
	return isTrue(ThemePrefs.Get("HV_MinimalisticMode"))
end

--- Check if instant search is enabled.
function HV.InstantSearch()
	return Theme.Get("HV_InstantSearch")
end

--- Get judgment tally mode ("Full" or "Simple").
function HV.GetJudgmentTallyMode()
	return ThemePrefs.Get("HV_JudgeCounterMode") or "Full"
end

--- Check if NG indicator should be shown.
function HV.ShowNGIndicator()
	return isTrue(ThemePrefs.Get("HV_ShowNGIndicator"))
end

--- Check if lower judgments should be prioritized.
function HV.PrioritizeLowerJudgements()
	return isTrue(ThemePrefs.Get("HV_PrioritizeLowerJudgements"))
end

--- Check if judgment animations are enabled.
function HV.JudgmentAnimation()
	return isTrue(ThemePrefs.Get("HV_JudgmentAnimation"))
end

--- Check if combo animations are enabled.
function HV.ComboAnimation()
	return isTrue(ThemePrefs.Get("HV_ComboAnimation"))
end

--- Check if song background should be shown.
function HV.ShowSongBackground()
	return HV.GetSongBackgroundBrightness() > 0.0
end

--- Get song background brightness (0.0-1.0).
function HV.GetSongBackgroundBrightness()
	return tonumber(PREFSMAN:GetPreference("BGBrightness")) or 1.0
end

--- Get screen filter / lane cover opacity (0.0-1.0).
function HV.GetScreenFilter()
	return tonumber(ThemePrefs.Get("HV_ScreenFilter")) or 0.0
end

--- Check if Song Select BGM is enabled (imported from Til Death)
function playSongSelectBGM()
	if ThemePrefs and ThemePrefs.Get then
		return ThemePrefs.Get("HV_SongSelectBGM") ~= false
	end
	return true
end

Trace("Holographic Void: 03 HVThemePrefs.lua loaded.")
