local gameplay = LoadActor("elements/context.lua")
local t = LoadActor("elements/controller.lua", gameplay)

t[#t + 1] = LoadActor("elements/replaywatermark.lua")
t[#t + 1] = LoadActor("elements/failsound.lua", gameplay)
t[#t + 1] = LoadActor("elements/frameupdate.lua", gameplay)

t[#t + 1] = LoadActor("../_cursor")
t[#t + 1] = LoadActor("practice_input.lua")
t[#t + 1] = LoadActor("elements/fullprogressbar.lua", gameplay)
t[#t + 1] = LoadActor("elements/miniprogressbar.lua", gameplay)
t[#t + 1] = LoadActor("elements/displaypercent.lua", gameplay)
t[#t + 1] = LoadActor("elements/targettracker.lua", gameplay)
t[#t + 1] = LoadActor("elements/stats.lua", gameplay)
t[#t + 1] = LoadActor("elements/timingstats.lua", gameplay)
t[#t + 1] = LoadActor("elements/combo.lua", gameplay)
t[#t + 1] = LoadActor("elements/combobreak.lua", gameplay)
t[#t + 1] = LoadActor("elements/practicelabel.lua", gameplay)
t[#t + 1] = LoadActor("replayscrolling.lua")
t[#t + 1] = LoadActor("elements/errorbar.lua", gameplay)
t[#t + 1] = LoadActor("elements/judgecounter.lua", gameplay)
t[#t + 1] = LoadActor("elements/bpm.lua", gameplay)
t[#t + 1] = LoadActor("elements/songtitle.lua", gameplay)
t[#t + 1] = LoadActor("elements/toasty.lua", gameplay)

if not gameplay.isSync then
	if HV.ApplyLaneCoverModifiers then HV.ApplyLaneCoverModifiers() end
	t[#t + 1] = LoadActor("scoretracking")
	t[#t + 1] = LoadActor("elements/autofaildisplay.lua", gameplay)
	t[#t + 1] = LoadActor("npscalc")
	t[#t + 1] = LoadActor("multiplayer")
	t[#t + 1] = LoadActor("leaderboard")
	t[#t + 1] = LoadActor("avatar")
end

t[#t + 1] = LoadActor("intro")
t[#t + 1] = LoadActor("messagebox")
t[#t + 1] = LoadActor("elements/ngindicator.lua", gameplay)
t[#t + 1] = LoadActor("elements/syncchallenge.lua", gameplay)
t[#t + 1] = LoadActor("elements/autofail.lua", gameplay)
t[#t + 1] = LoadActor("elements/nowplaying.lua")

return t
