local wheelItemW, barH = 280, 5
local barW = wheelItemW - 60

local function getCompletionColor(percent)
	if percent <= 0 then return {0.4, 0.4, 0.4, 1} end -- 0% Gray
	if percent >= 1 then return {1, 1, 1, 1} end     -- 100% White (Bright)

	-- Elaborative Scale: Red -> Orange -> Yellow -> Green -> Cyan -> Gold
	local stops = {
		{0.0,  {1.0, 0.3, 0.3, 1}}, -- Clear Red
		{0.20, {1.0, 0.6, 0.2, 1}}, -- Vibrant Orange
		{0.40, {1.0, 1.0, 0.2, 1}}, -- Bright Yellow
		{0.60, {0.2, 1.0, 0.2, 1}}, -- Bright Green
		{0.80, {0.2, 1.0, 1.0, 1}}, -- Clear Cyan
		{1.0,  {1.0, 0.9, 0.5, 1}}, -- Rich Gold
	}

	for i = 1, #stops - 1 do
		local s1 = stops[i]
		local s2 = stops[i+1]
		if percent >= s1[1] and percent <= s2[1] then
			local p = (percent - s1[1]) / (s2[1] - s1[1])
			return HV.LerpColor(p, s1[2], s2[2])
		end
	end
	return stops[#stops][2]
end

local function updateCount(self, summary)
	local row = self:GetParent()
	local count = row:GetChild("SectionCount")
	if PREFSMAN:GetPreference("PackProgressInWheel") then
		count:settextf("%d/%d", summary.played, summary.count)
	else
		count:settext(tostring(summary.count))
	end
	count:diffuse(getCompletionColor(summary.progress))
end

local function refreshSection(self, cachedOnly)
	local section = self.section
	if not section then return end
	local wheel = self:GetParent():GetParent()
	local style = GAMESTATE:GetCurrentStyle()
	local summary = HV.WheelData.GetSection(wheel, section, style and style:GetStepsType(), cachedOnly)
	if not summary then
		self:GetChild("ProgressionBar"):visible(false)
		HV.WheelData.QueueRow(wheel, self, "UpdateSection", self.focused)
		return
	end
	HV.WheelData.CancelRow(self)
	updateCount(self, summary)
	local bar = self:GetChild("ProgressionBar")
	bar:visible(true)
	if self.summary == summary then return end
	self.summary = summary

	local x, widthPerSong = -barW/2, barW / math.max(1, summary.count)
	for tier = 1, 17 do
		local width = (summary.grades[tier] or 0) * widthPerSong
		bar:GetChild("Bar_" .. tier):x(x):zoomto(width, barH)
		x = x + width
	end
	bar:GetChild("BarBG"):x(x):zoomto(math.max(0, barW/2 - x), barH)
end

local t = Def.ActorFrame {
	SetMessageCommand = function(self, params)
		local active = params and params.Type and self:GetName() == params.Type .. "NormalPart"
		local section = active and params.Text
		if not section or section == "" then
			self.section, self.summary = nil, nil
			HV.WheelData.CancelRow(self)
			return
		end

		local row = self:GetParent()
		local title = row:GetChild(params.Type)
		if title then title:diffuse(HVColor.Accent):halign(0):x(-wheelItemW/2 + 12):y(0) end
		self.section, self.focused = section, params.HasFocus
		refreshSection(self, true)
	end,
	UpdateSectionCommand = function(self) refreshSection(self, false) end,
	HV_WheelScoresChangedMessageCommand = function(self) refreshSection(self, true) end,
	ColorThemeChangedMessageCommand = function(self)
		if not self.section then return end
		local row = self:GetParent()
		local title = row:GetChild(self:GetName():gsub("NormalPart$", ""))
		if title then title:diffuse(HVColor.Accent) end
		self:GetChild("BgAccent"):diffuse(HVColor.Accent)
	end,
	Def.Quad {
		Name = "BgQuad",
		InitCommand = function(self)
			self:zoomto(wheelItemW, 38):diffuse(color("0.10,0.10,0.10,1"))
		end,
	},
	Def.Quad {
		Name = "BgAccent",
		InitCommand = function(self)
			self:x(-wheelItemW/2 + 2):zoomto(4, 34):diffuse(HVColor.Accent):diffusealpha(0.5)
		end,
	},
}

local bar = Def.ActorFrame {
	Name = "ProgressionBar",
	InitCommand = function(self) self:y(14):draworder(150):ztest(false):visible(false) end,
}
for tier = 1, 17 do
	bar[#bar + 1] = Def.Quad {
		Name = "Bar_" .. tier,
		InitCommand = function(self)
			self:halign(0):valign(1):diffuse(HVColor.GetGradeColor(string.format("Grade_Tier%02d", tier)))
		end,
	}
end
bar[#bar + 1] = Def.Quad {
	Name = "BarBG",
	InitCommand = function(self)
		self:halign(0):valign(1):diffuse(color("0.3,0.3,0.3,1")):diffusealpha(0.4)
	end,
}
t[#t + 1] = bar

return t
