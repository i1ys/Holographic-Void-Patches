return {
	-- Use #RRGGBB or #RRGGBBAA.
	accent = "#5ABAFF",

	-- Each palette accepts Holographic, Classic, or Custom.
	palettes = {
		grades = "Holographic",
		judgment = "Holographic",
		difficulty = "Holographic",
		clearType = "Holographic",
	},

	-- Holographic, Classic, None, Monochrome, or Accent.
	msdScale = "Holographic",

	overrides = {
		-- grades = {AA = "#A0CFAB", ["AA:"] = "#A5D4B0"},
		-- judgment = {W2 = "#FFFFB7"},
		-- difficulty = {Hard = "#CF9898"},
		-- clearType = {MFC = "#E0F8FF"},
		-- goalTracker = {Positive = "#A0CFAB", Negative = "#CF9898"},
		-- lifeBar = {L4 = "#5ABAFF"},
		-- radar = {Power = "#E0B080"},
	},

	syncToAccent = {
		-- difficulty = {Challenge = true},
	},
}
