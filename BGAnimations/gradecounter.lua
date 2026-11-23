GRADECOUNTERSTORAGE = GRADECOUNTERSTORAGE or {
	AAAAA = 0,
	AAAA = 0,
	AAA = 0,
	AA = 0,
	A = 0,
	session_AAAAA = 0,
	session_AAAA = 0,
	session_AAA = 0,
	session_AA = 0,
	session_A = 0,
	session_UnderA = 0,
}

local gradeBands = {
	Tier01 = "AAAAA",
	Tier02 = "AAAA", Tier03 = "AAAA", Tier04 = "AAAA",
	Tier05 = "AAA", Tier06 = "AAA", Tier07 = "AAA",
	Tier08 = "AA", Tier09 = "AA", Tier10 = "AA",
	Tier11 = "A", Tier12 = "A", Tier13 = "A",
	Tier14 = "UnderA", Tier15 = "UnderA", Tier16 = "UnderA", Tier17 = "UnderA",
	Failed = "UnderA",
}

function GRADECOUNTERSTORAGE:incrementSession(grade)
	local band = grade and gradeBands[ToEnumShortString(grade)]
	if not band then return end
	local key = "session_" .. band
	self[key] = self[key] + 1
end

function GRADECOUNTERSTORAGE:refreshProfile()
	self.AAAAA, self.AAAA, self.AAA, self.AA, self.A = 0, 0, 0, 0, 0
	-- The engine supplies the active profile's scores for all installed charts.
	SCOREMAN:SortRecentScores()
	local rank = 1
	local score = SCOREMAN:GetRecentScore(rank)
	while score do
		local band = gradeBands[ToEnumShortString(score:GetWifeGrade())]
		if band and band ~= "UnderA" then
			self[band] = self[band] + 1
		end
		rank = rank + 1
		score = SCOREMAN:GetRecentScore(rank)
	end
end

return Def.ActorFrame {}
