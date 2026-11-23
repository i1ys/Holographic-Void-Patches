local gameplay = ...
local statType = HV.GetNotefieldStat()

local function formatHandDelta(stats)
	if not stats.handScores then return "-" end
	local score, count = stats.handScores, stats.handCounts
	if not stats.hasMiddleColumn then
		if count[1] == 0 or count[3] == 0 then return "0.0000%" end
		local direction = score[1] > score[3] and "> " or "< "
		return string.format("%s%.4f%%", direction, math.abs(score[1] - score[3]) * 100)
	end
	if count[1] + count[2] + count[3] == 0 then return "0.0000%" end

	local labels = {"L", "M", "R"}
	local order = {1, 2, 3}
	table.sort(order, function(a, b)
		if score[a] == score[b] then return a < b end
		return score[a] > score[b]
	end)
	local delta = (score[order[1]] - score[order[3]]) * 100
	return string.format("%s>%s>%s %.4f%%", labels[order[1]], labels[order[2]], labels[order[3]], delta)
end

local function formatStat(stats)
	if statType == "MARatio" then
		return stats.maRatio == math.huge and "∞" or string.format("%.2f:1", stats.maRatio)
	end
	if statType == "TapOffset" then
		return stats.lastOffset == nil and "-" or string.format("%+.2fms", stats.lastOffset)
	end
	if statType == "DeltaHand" then return formatHandDelta(stats) end
	local value = stats.mean
	if statType == "StdDev" then value = stats.stdDev end
	return value == nil and "-" or string.format("%.2fms", value)
end

return Def.ActorFrame {
	Name = "NotefieldMean",
	InitCommand = function(self)
		self:xy(gameplay.gameplayCoord("DisplayMeanX"), gameplay.gameplayCoord("DisplayMeanY"))
			:zoom(gameplay.gameplaySize("DisplayMeanZoom")):diffusealpha(0)
		self.HVBaseVisible = statType ~= "Off" and not gameplay.isSync
		self:visible(gameplay.minimalisticHUDVisible(self.HVBaseVisible))
	end,
	HV_MinimalisticModeChangedMessageCommand = function(self, params)
		gameplay.animateGameplayHUDVisibility(self, gameplay.minimalisticHUDVisible(self.HVBaseVisible, params and params.Enabled))
	end,
	OnCommand = function(self)
		setMovableActor({"DeviceButton_m", "DeviceButton_comma"}, self, self:GetChild("Border"))
		self:linear(0.2):diffusealpha(0.8)
	end,
	SetGameplayStatsCommand = function(self, stats)
		if self.HVBaseVisible then self:GetChild("Value"):settext(formatStat(stats)) end
	end,

	LoadFont("Common Normal") .. {
		Name = "Value",
		InitCommand = function(self)
			self:zoom(0.35):diffuse(gameplay.mainText)
			local initial = "0.00ms"
			if statType == "MARatio" then
				initial = "0.00:1"
			elseif statType == "DeltaHand" then
				initial = "0.0000%"
			elseif statType == "TapOffset" then
				initial = "+0.00ms"
			end
			self:settext(initial)
		end,
	},
	MovableBorder(100, 18, 1, 0, 0),
}
