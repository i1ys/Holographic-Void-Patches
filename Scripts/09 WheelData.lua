local grades, sections = {}, {}
local owner, profile, normalized, midGrades
local pendingRows = {}
local sectionBuild
local sectionRevision = 0
local numericFilter
local sectionWorkPerUpdate = 64

HV.WheelData = {}
local WheelData = HV.WheelData

function WheelData.Reset()
	grades = {}
	WheelData.ClearSections()
end

function WheelData.ClearSections()
	sections = {}
	sectionBuild = nil
	numericFilter = nil
end

local function getNumericFilterKey()
	if not FILTERMAN:AnyActiveFilter() then return false end
	local values = {
		tostring(FILTERMAN:GetFilterMode()),
		tostring(FILTERMAN:GetHighestSkillsetsOnly()),
		tostring(FILTERMAN:GetHighestDifficultyOnly()),
		FILTERMAN:GetMinFilterRate(),
		FILTERMAN:GetMaxFilterRate(),
	}
	for row = 1, #ms.SkillSets + 2 do
		values[#values + 1] = FILTERMAN:GetSSFilter(row, 0)
		values[#values + 1] = FILTERMAN:GetSSFilter(row, 1)
	end
	return table.concat(values, ":")
end

function WheelData.FilterResultsChanged()
	-- Etterna broadcasts before publishing the new section lists.
	local currentFilter = getNumericFilterKey()
	if currentFilter ~= numericFilter then sections = {} end
	numericFilter = currentFilter
	sectionRevision = sectionRevision + 1
	sectionBuild = nil
end

function WheelData.QueueRow(wheel, row, command, focused, section)
	pendingRows[row] = {wheel = wheel, command = command, focused = focused, section = section}
end

function WheelData.CancelRow(row)
	pendingRows[row] = nil
end

function WheelData.ClearPendingRows()
	pendingRows = {}
	sectionBuild = nil
end

function WheelData.RefreshNextRow(wheel)
	if not next(pendingRows) then return false end
	local settled = wheel:IsSettled()
	local wanted, job
	for row, entry in pairs(pendingRows) do
		if entry.wheel ~= wheel then
			pendingRows[row] = nil
		elseif (entry.section or settled) and
			(not wanted or entry.focused or (sectionBuild and entry.section == sectionBuild.name)) then
			wanted, job = row, entry
			if entry.focused then break end
		end
	end
	if not wanted then return false end
	pendingRows[wanted] = nil
	wanted:playcommand(job.command)
	return true
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

function WheelData.GetChartGrade(wheel, steps, cachedOnly)
	refreshScoreContext(wheel)
	if not profile then return nil, true end
	local key = steps:GetChartKey()
	if cachedOnly and not grades[key] then return nil, false end
	local tier = HV.Score.GetChartBestGradeTier(key, grades)
	return tier and string.format("Grade_Tier%02d", tier) or nil, true
end

local function buildSection(songs, style, sort, showPlayed, checkpoint)
	local summary = {songs = songs, revision = sectionRevision, style = style, sort = sort, showPlayed = showPlayed,
		count = #songs, cleared = 0, played = 0, grades = {}, bins = {}, charts = 0, avgMSD = 0}
	local msdTotal, ratedSongs = 0, 0
	local filterActive = FILTERMAN:AnyActiveFilter()
	for _, song in ipairs(songs) do
		checkpoint()
		local highest, best, played = 0, nil, false
		for _, chart in ipairs(song:GetChartsMatchingFilter()) do
			checkpoint()
			if profile then
				local tier, hasScores = HV.Score.GetChartBestGradeTier(chart:GetChartKey(), grades, checkpoint)
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
				checkpoint()
				local _, hasScores = HV.Score.GetChartBestGradeTier(chart:GetChartKey(), grades, checkpoint)
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
	return summary
end

local function sameSectionSongs(previous, current)
	if #previous ~= #current then return false end
	for i, song in ipairs(current) do
		if previous[i] ~= song then return false end
	end
	return true
end

function WheelData.GetSection(wheel, name, style, cachedOnly)
	refreshScoreContext(wheel)
	local showPlayed = PREFSMAN:GetPreference("PackProgressInWheel")
	local sort = GAMESTATE:GetSortOrder()
	if sort == "SortOrder_ModeMenu" then return end
	local cached = sections[name]
	local songs
	if cached and cached.style == style and cached.showPlayed == showPlayed and cached.sort == sort then
		if cached.revision == sectionRevision then return cached end
		songs = wheel:GetSongsInGroup(name)
		if sameSectionSongs(cached.songs, songs) then
			cached.revision = sectionRevision
			return cached
		end
		sections[name] = nil
	end
	if cachedOnly then return end

	local job = sectionBuild
	if not job or job.name ~= name or job.style ~= style or job.showPlayed ~= showPlayed or job.sort ~= sort then
		if numericFilter == nil then numericFilter = getNumericFilterKey() end
		songs = songs or wheel:GetSongsInGroup(name)
		local work = 0
		local function checkpoint()
			if work == sectionWorkPerUpdate then
				work = 0
				coroutine.yield()
			end
			work = work + 1
		end
		job = {name = name, style = style, showPlayed = showPlayed, sort = sort,
			thread = coroutine.create(function() return buildSection(songs, style, sort, showPlayed, checkpoint) end)}
		sectionBuild = job
	end
	local ok, summary = coroutine.resume(job.thread)
	if not ok or summary then sectionBuild = nil end
	if not ok then error(summary, 0) end
	if summary then sections[name] = summary end
	return summary
end
