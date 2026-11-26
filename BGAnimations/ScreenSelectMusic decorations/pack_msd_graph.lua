local selection, panelW = ...
local accentColor = HVColor.Accent
local mainText = color("0.85,0.85,0.85,1")
local subText = color("0.65,0.65,0.65,1")

return Def.ActorFrame {
	Name = "PackMSDGraph",
	InitCommand = function(self) self:xy(-5, -4):visible(false) end,
	InstantChartUpdateMessageCommand = function(self) self:playcommand("SetPackGraph") end,
	PackDetailsUpdateMessageCommand = function(self) self:playcommand("SetPackGraph") end,
	SetPackGraphCommand = function(self)
		local data = selection
		local show = data.group ~= nil and data.group ~= ""
		self:visible(show)
		if not show or self.summary == data.packSummary then return end
		self.summary = data.packSummary
		local summary = data.packSummary
		local bins = summary and summary.bins or {}
		local maxCount = 1
		for i = 1, 40 do maxCount = math.max(maxCount, bins[i] or 0) end
		self:GetChild("Title"):settext(summary and string.format("PACK MSD DISTRIBUTION ACROSS %d CHARTS", summary.charts) or "")
		local bars = self:GetChild("Bars")
		for i = 1, 40 do
			local bar, count = bars:GetChild("Bar_" .. i), bins[i] or 0
			bar:GetChild("Fill"):zoomy(48 * count / maxCount)
			bar:GetChild("Value"):settext(count > 0 and tostring(count) or "")
		end
	end,
	LoadFont("Common Normal") .. { Name = "Title", InitCommand = function(self) self:halign(0):valign(0):xy(5, 6):zoom(0.40):diffuse(accentColor) end },
	(function()
		local graph = Def.ActorFrame { Name = "Bars" }
		local barW, gap, baseY = (panelW - 68) / 40, 1, 92
		for i = 1, 40 do
			graph[#graph + 1] = Def.ActorFrame {
				Name = "Bar_" .. i, InitCommand = function(self) self:x((i - 1) * (barW + gap)) end,
				Def.Quad { Name = "Fill", InitCommand = function(self) self:halign(0):valign(1):xy(0, baseY):zoomto(barW, 0):diffuse(HVColor.GetMSDRatingColor(math.max(1, i + 0.5))) end },
				LoadFont("Common Normal") .. { Name = "Value", InitCommand = function(self) self:halign(0.5):valign(1):xy(barW / 2, baseY - 62):zoom(0.28):diffuse(mainText) end },
				LoadFont("Common Normal") .. { Name = "Label", InitCommand = function(self) self:halign(0.5):valign(0):xy(barW / 2, baseY + 4):zoom(0.28):diffuse(subText):settext(i == 1 and "0" or (i % 5 == 0 and tostring(i) or "")) end }
			}
		end
		return graph
	end)()
}
