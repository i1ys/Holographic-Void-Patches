local grades, sections = {}, {}
local owner, profile, normalized, midGrades

HV.WheelData = {}
local WheelData = HV.WheelData

function WheelData.Reset()
	grades, sections = {}, {}
end

function WheelData.ClearSections()
	sections = {}
end

local function refreshScoreContext(wheel)
	local currentProfile = PROFILEMAN:GetProfile(PLAYER_1)
	local currentNormalization = PREFSMAN:GetPreference("SortBySSRNormPercent")
	local currentMidGrades = PREFSMAN:GetPreference("UseMidGrades")
	if owner ~= wheel or profile ~= currentProfile or normalized ~= currentNormalization or midGrades ~= currentMidGrades then
		owner, profile, normalized, midGrades = wheel, currentProfile, currentNormalization, currentMidGrades
		WheelData.Reset()
	end
end

function WheelData.GetChartGrade(wheel, steps)
	refreshScoreContext(wheel)
	if not profile then return end
	local tier = HV.Score.GetChartBestGradeTier(steps:GetChartKey(), grades)
	if tier then return string.format("Grade_Tier%02d", tier) end
end

function WheelData.GetSection(wheel, name, style)
	refreshScoreContext(wheel)
	local showPlayed = PREFSMAN:GetPreference("PackProgressInWheel")
	local cached = sections[name]
	if cached and cached.style == style and cached.showPlayed == showPlayed then return cached end

	local songs = wheel:GetSongsInGroup(name)
	local summary = {style = style, showPlayed = showPlayed, count = #songs, cleared = 0, played = 0, grades = {}, bins = {}, charts = 0, avgMSD = 0}
	local msdTotal, ratedSongs = 0, 0
	local filterActive = FILTERMAN:AnyActiveFilter()
	for _, song in ipairs(songs) do
		local highest, best, played = 0, nil, false
		for _, chart in ipairs(song:GetChartsMatchingFilter()) do
			if profile then
				local tier, hasScores = HV.Score.GetChartBestGradeTier(chart:GetChartKey(), grades)
				if tier and (not best or tier < best) then best = tier end
				played = played or hasScores
			end
			if chart:GetStepsType() == style then
				local msd = chart:GetMSD(1, 1)
				if msd > 0 then
					local bin = math.max(1, math.min(40, math.floor(msd)))
					summary.bins[bin] = (summary.bins[bin] or 0) + 1
					summary.charts = summary.charts + 1
					highest = math.max(highest, msd)
				end
			end
		end
		if showPlayed and profile and filterActive and not played then
			for _, chart in ipairs(song:GetChartsOfCurrentGameMode()) do
				local _, hasScores = HV.Score.GetChartBestGradeTier(chart:GetChartKey(), grades)
				if hasScores then
					played = true
					break
				end
			end
		end
		if played then summary.played = summary.played + 1 end
		if best then
			summary.grades[best] = (summary.grades[best] or 0) + 1
			summary.cleared = summary.cleared + 1
		end
		if highest > 0 then
			msdTotal, ratedSongs = msdTotal + highest, ratedSongs + 1
		end
	end
	summary.avgMSD = msdTotal / math.max(1, ratedSongs)
	summary.progress = summary.cleared / math.max(1, summary.count)
	sections[name] = summary
	return summary
end
