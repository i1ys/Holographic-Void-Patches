return function(score)
	local replay = score and score:GetReplay()
	if not replay or not replay:LoadAllData() then return end
	return {
		nrv = replay:GetNoteRowVector(), dvt = replay:GetOffsetVector(),
		ctt = replay:GetTrackVector(), ntt = replay:GetTapNoteTypeVector(),
		misses = replay.GetMissDataVector and replay:GetMissDataVector() or nil,
	}
end
