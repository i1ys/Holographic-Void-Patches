GRADECOUNTERSTORAGE = GRADECOUNTERSTORAGE or {
	session_AAAAA = 0,
	session_AAAA = 0,
	session_AAA = 0,
	session_AA = 0,
	session_A = 0,
	session_UnderA = 0,
}

local profileGradeBands = {
	{name = "AAAAA", grades = {"Grade_Tier01"}},
	{name = "AAAA", grades = {"Grade_Tier04", "Grade_Tier02", "Grade_Tier03"}},
	{name = "AAA", grades = {"Grade_Tier07", "Grade_Tier05", "Grade_Tier06"}},
	{name = "AA", grades = {"Grade_Tier10", "Grade_Tier08", "Grade_Tier09"}},
	{name = "A", grades = {"Grade_Tier13", "Grade_Tier11", "Grade_Tier12"}},
	{name = "B", grades = {"Grade_Tier14"}},
	{name = "C", grades = {"Grade_Tier15"}},
	{name = "D", grades = {"Grade_Tier16"}},
	{name = "F", grades = {"Grade_Failed", "Grade_Tier17"}},
}
GRADECOUNTERSTORAGE.profileGradeBands = profileGradeBands

local gradeBands = {}
for _, band in ipairs(profileGradeBands) do
	for _, grade in ipairs(band.grades) do
		gradeBands[grade] = band.name
	end
end

function GRADECOUNTERSTORAGE:incrementSession(grade)
	local band = gradeBands[grade]
	if not band then return end
	local key = "session_" .. band
	if not self[key] then key = "session_UnderA" end
	self[key] = self[key] + 1
end

function GRADECOUNTERSTORAGE:refreshProfile()
	for _, band in ipairs(profileGradeBands) do
		self[band.name] = 0
	end
	-- The engine supplies the active profile's scores for all installed charts.
	SCOREMAN:SortRecentScores()
	local rank = 1
	local score = SCOREMAN:GetRecentScore(rank)
	while score do
		local band = gradeBands[score:GetWifeGrade()]
		if band then
			self[band] = self[band] + 1
		end
		rank = rank + 1
		score = SCOREMAN:GetRecentScore(rank)
	end
end

return Def.ActorFrame {}
