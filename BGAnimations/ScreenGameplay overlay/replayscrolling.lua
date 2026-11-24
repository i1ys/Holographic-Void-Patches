if not HV.IsReplayPlayback() then return Def.Actor {} end

local btnW, btnH, spacing = 60, 24, 30
local panelWidth, panelHeight = btnW + 10, spacing * 5 + 60
local accentColor = HVColor.Accent or color("#00CFFF")
local panelColor = color("0.05,0.05,0.05,0.7")
local buttonColor = color("0.15,0.15,0.15,0.8")
local textMain = color("1,1,1,1")
local textDim = color("0.6,0.6,0.6,1")

local owner, controls
local leaving = false

local function usablePosition(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function seek(delta)
	local position = owner:GetSongPosition()
	local steps = GAMESTATE:GetCurrentSteps()
	local finish = steps and steps:GetLastSecond()
	if not usablePosition(finish) or finish <= 0 then
		local song = GAMESTATE:GetCurrentSong()
		finish = song and song:GetLastSecond()
	end
	if not usablePosition(position) or not usablePosition(finish) or finish <= 0 then return end
	local target = math.max(0, math.min(finish, position + delta))
	if target ~= position then owner:SetSongPosition(target) end
end

local function results()
	leaving = true
	owner:PostScreenMessage("SM_NotesEnded", 0)
end

local function exit()
	leaving = true
	owner:Cancel()
end

local buttons = {
	{name = "Rewind", label = "<< 5s", key = "EffectDown", requiresPause = true, action = function() seek(-5) end},
	{name = "Pause", label = "PAUSE", key = "Coin", action = function() owner:TogglePause() end},
	{name = "Forward", label = "5s >>", key = "EffectUp", requiresPause = true, action = function() seek(5) end},
	{name = "Results", label = "RESULTS", action = results},
	{name = "Exit", label = "EXIT", action = exit},
}
local keyActions = {}

local function getButtonActor(buttonsActor, button)
	return buttonsActor:GetChild(button.name .. "Button")
end

local function activate(button)
	if button.requiresPause and not GAMESTATE:IsPaused() then
		ms.ok("Pause the replay to seek.")
		return
	end
	button.action()
end

local function input(event)
	if not event or event.type ~= "InputEventType_FirstPress"
		or not owner or owner ~= SCREENMAN:GetTopScreen() or owner:IsTransitioning() or leaving then
		return false
	end

	local button = keyActions[event.GameButton] or keyActions[event.button]
	if button then
		activate(button)
		return true
	end

	if event.DeviceInput and event.DeviceInput.button == "DeviceButton_left mouse button" then
		for _, candidate in ipairs(buttons) do
			local actor = getButtonActor(controls, candidate)
			if isOver(actor:GetChild("BG")) then
				activate(candidate)
				return true
			end
		end
	end
	-- Back belongs to ScreenGameplayReplay, which applies the delayed Back preference.
	return false
end

local function updateVisuals()
	if not owner or owner ~= SCREENMAN:GetTopScreen() then return end
	local paused = GAMESTATE:IsPaused()
	for _, button in ipairs(buttons) do
		local actor = getButtonActor(controls, button)
		local bg, label = actor:GetChild("BG"), actor:GetChild("Label")
		local enabled = paused or not button.requiresPause
		if enabled and isOver(bg) then
			bg:diffuse(accentColor):diffusealpha(0.4)
		else
			bg:diffuse(buttonColor)
		end
		label:diffuse(enabled and textMain or textDim)
		if button.name == "Pause" then label:settext(paused and "PLAY" or "PAUSE") end
	end
end

local function stop(self)
	if owner then owner:RemoveInputCallback(input) end
	owner, controls = nil, nil
	self:SetUpdateFunction(nil)
end

local function playerName(screen)
	local replayName = HV.GetOnlineReplayPlayerName()
	if replayName then return replayName end
	local score = screen.GetReplayScore and screen:GetReplayScore(PLAYER_1)
	if score then return score:GetDisplayName() or score:GetName() or "Replay" end
	return "Replay"
end

local buttonActors = Def.ActorFrame {
	Name = "Buttons",
	InitCommand = function(self) self:y(10) end,
}
for i, button in ipairs(buttons) do
	if button.key then keyActions[button.key] = button end
	local y, label = (i - 3) * spacing, button.label
	buttonActors[#buttonActors + 1] = Def.ActorFrame {
		Name = button.name .. "Button",
		InitCommand = function(self) self:y(y) end,
		Def.Quad {
			Name = "BG",
			InitCommand = function(self) self:zoomto(btnW, btnH):diffuse(buttonColor) end,
		},
		LoadFont("Common Normal") .. {
			Name = "Label",
			InitCommand = function(self) self:zoom(0.32):settext(label):diffuse(textMain) end,
		},
	}
end

return Def.ActorFrame {
	Name = "ReplayControls",
	InitCommand = function(self)
		local x = (MovableValues and MovableValues.ReplayButtonsX) or getDefaultGameplayCoordinate("ReplayButtonsX") or SCREEN_RIGHT - 40
		local y = (MovableValues and MovableValues.ReplayButtonsY) or getDefaultGameplayCoordinate("ReplayButtonsY") or SCREEN_CENTER_Y + 50
		self:xy(x, y):diffusealpha(0)
	end,
	OnCommand = function(self)
		local screen = SCREENMAN:GetTopScreen()
		if not screen or screen == owner then return end
		if owner then stop(self) end
		owner, controls, leaving = screen, self:GetChild("Buttons"), false
		setMovableActor({"DeviceButton_f"}, self, self:GetChild("Border"))
		self:GetChild("PlayerName"):settext(playerName(screen))
		screen:AddInputCallback(input)
		self:linear(0.2):diffusealpha(1)
		self:SetUpdateFunction(updateVisuals)
		updateVisuals()
	end,
	OffCommand = stop,
	EndCommand = stop,

	Def.Quad {
		InitCommand = function(self) self:zoomto(panelWidth, panelHeight):diffuse(panelColor) end,
	},
	Def.Quad {
		InitCommand = function(self)
			self:halign(1):x(panelWidth / 2):zoomto(2, panelHeight):diffuse(accentColor):diffusealpha(0.5)
		end,
	},
	LoadFont("Common Normal") .. {
		Name = "PlayerName",
		InitCommand = function(self) self:y(-spacing * 2.5 - 15):zoom(0.35):diffuse(accentColor):maxwidth((btnW + 4) / 0.35) end,
	},
	buttonActors,
	MovableBorder(panelWidth, panelHeight, 1, 0, 0),
}
