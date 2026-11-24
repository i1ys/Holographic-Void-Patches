local density = {}

-- GetCDGraphVectors bins taps and hold heads in one-second playback intervals.
function density.At(vectors, playbackSecond)
	local bins = vectors and vectors[1]
	if bins and playbackSecond >= 0 and playbackSecond < #bins then
		return bins[math.floor(playbackSecond) + 1]
	end
end

function density.Summarize(vectors)
	local bins = vectors and vectors[1]
	if not bins or #bins == 0 then return end

	local peak = 0
	for _, count in ipairs(bins) do
		peak = math.max(peak, count)
	end

	-- The existing average summarizes sections at or above half the peak NPS.
	local total, samples = 0, 0
	for _, count in ipairs(bins) do
		if count >= peak / 2 then
			total, samples = total + count, samples + 1
		end
	end
	return {peak = peak, denseMean = total / samples}
end

return density
