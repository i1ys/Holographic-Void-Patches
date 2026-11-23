HV.Judgment = HV.Judgment or {}
HV.Score = HV.Score or {}

local tapWindows = {22.5, 45, 90, 135}
local tapKeys = {"W1", "W2", "W3", "W4"}

function HV.Judgment.GetWindows(scale, includeRidiculous)
	scale = math.max(0.001, math.min(tonumber(scale) or 1, 1))
	local windows = { W5 = 180 }
	for i, key in ipairs(tapKeys) do
		local seconds = PREFSMAN:GetPreference("TimingWindowSeconds" .. key)
		local milliseconds = type(seconds) == "number" and seconds * 1000 or tapWindows[i]
		windows[key] = math.max(0, math.min(milliseconds * scale, 180))
	end
	if includeRidiculous then windows.Ridiculous = 11.25 * scale end
	return windows
end

function HV.Judgment.ClassifyOffset(offsetMs, windows)
	local offset = math.abs(offsetMs)
	if windows.Ridiculous and offset <= windows.Ridiculous then return "Ridiculous" end
	for _, key in ipairs(tapKeys) do
		if offset <= windows[key] then return key end
	end
	if offset <= windows.W5 then return "W5" end
	return "Miss"
end

function HV.Score.GetLiveWifePercent(message, player)
	if message.Player ~= player or type(message.MaxWifeScore) ~= "number" or message.MaxWifeScore <= 0 then return end
	local percent = message.WifePercent
	if type(percent) == "number" and percent == percent and math.abs(percent) < math.huge then return percent end
end
