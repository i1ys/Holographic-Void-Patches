local gameplay = ...
local showJudgeCounter = HV.ShowJudgeCounter()
if not showJudgeCounter or gameplay.isSync then return end

local simple = HV.GetJudgmentTallyMode() == "Simple"
local useRidiculous = HV.EmulateRidiculousEnabled()
local judgmentRows = {}

local function countText(value)
	return value == nil and "—" or tostring(value)
end

local function ratioText(value)
	return value == math.huge and "inf:1" or string.format("%.2f:1", value)
end

local function offsetText(value, format)
	return value == nil and "—" or string.format(format or "%.2f", value)
end

if useRidiculous then
	judgmentRows[#judgmentRows + 1] = {
		label = THEME:GetString("TapNoteScore", "Ridiculous"),
		color = HVColor.GetJudgmentColor("Ridiculous"),
		value = function(stats) return countText(stats.ridiculous) end,
		initial = "0",
	}
end
for _, key in ipairs({"W1", "W2", "W3", "W4", "W5", "Miss"}) do
	local judgment = key
	judgmentRows[#judgmentRows + 1] = {
		label = THEME:GetString("TapNoteScore", judgment),
		color = HVColor.GetJudgmentColor(judgment),
		value = function(stats)
			if useRidiculous and judgment == "W1" then
				if stats.ridiculous == nil then return "—" end
				return countText(stats.taps.W1 - stats.ridiculous)
			end
			return countText(stats.taps[judgment])
		end,
		initial = "0",
	}
end
for _, hold in ipairs({
	{label = "OK", color = "Held", field = "held"},
	{label = "NG", color = "LetGo", field = "letGo"},
}) do
	local field = hold.field
	judgmentRows[#judgmentRows + 1] = {
		label = THEME:GetString("HoldNoteScore", hold.label),
		color = HVColor.GetJudgmentColor(hold.color),
		value = function(stats) return countText(stats[field]) end,
		initial = "0",
		inset = 4,
	}
end

local metricRows = {
	{label = "MA", initial = "0.00:1", value = function(stats) return ratioText(stats.maRatio) end},
	{label = "PA", initial = "0.00:1", value = function(stats) return ratioText(stats.paRatio) end},
	{label = "Longest", initial = "0", value = function(stats) return countText(stats.longest) end},
	{label = "SD", initial = "0.00", value = function(stats) return offsetText(stats.stdDev) end},
	{label = "Mean", initial = "+0.00", value = function(stats) return offsetText(stats.mean, "%+.2f") end},
	{label = "Max", initial = "0.00", value = function(stats) return offsetText(stats.largest) end},
}

local function makeColumn(name, rows, x, valueX, valueColor, alpha)
	local column = Def.ActorFrame {
		Name = name,
		InitCommand = function(self) self:x(x) end,
		SetGameplayStatsCommand = function(self, stats)
			for i, row in ipairs(rows) do
				self:GetChild("Value" .. i):settext(row.value(stats))
			end
		end,
	}
	for i, row in ipairs(rows) do
		local entry = row
		local y = (i - 1) * 16 + (entry.inset or 0)
		column[#column + 1] = LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:halign(0):valign(0):y(y):zoom(0.34):diffuse(entry.color or gameplay.dimText):diffusealpha(alpha)
				self:settext(entry.label)
			end,
		}
		column[#column + 1] = LoadFont("Common Normal") .. {
			Name = "Value" .. i,
			InitCommand = function(self)
				self:halign(1):valign(0):xy(valueX, y):zoom(0.34):diffuse(valueColor):diffusealpha(alpha)
				self:settext(entry.initial)
			end,
		}
	end
	return column
end

local counter = Def.ActorFrame {
	Name = "TallyAndMetrics",
	InitCommand = function(self)
		self:xy(gameplay.gameplayCoord("JudgeCounterX"), gameplay.gameplayCoord("JudgeCounterY")):diffusealpha(0.8)
		self:visible(gameplay.minimalisticHUDVisible(showJudgeCounter))
	end,
	HV_MinimalisticModeChangedMessageCommand = function(self, params)
		gameplay.animateGameplayHUDVisibility(self, gameplay.minimalisticHUDVisible(showJudgeCounter, params and params.Enabled))
	end,
	OnCommand = function(self) setMovableActor({"DeviceButton_p"}, self, self:GetChild("Border")) end,
	SetGameplayStatsCommand = function(self, stats)
		self:RunCommandsOnChildren(function(child) child:playcommand("SetGameplayStats", stats) end)
	end,

	makeColumn("Column1_Judgments", judgmentRows, 0, 60, gameplay.mainText, 0.8),
}
if not simple then
	counter[#counter + 1] = makeColumn("Column2_Metrics", metricRows, 70, 65, gameplay.subText, 1)
end
counter[#counter + 1] = MovableBorder(140, 100, 1, 70, 50)
return counter
