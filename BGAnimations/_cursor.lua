--- Holographic Void: Custom Mouse Cursor

local screenName = Var("LoadingScreen") or ...
local owner, registeredScreen
local tooltipActor, pointerActor, clickWaveActor

-- Modal text entry has a visual cursor. Keep the caller's buttons registered.
if screenName and screenName ~= "ScreenTextEntry" then
	BUTTON:ResetButtonTable(screenName)
end

local function hasFocus()
	return owner ~= nil and owner == SCREENMAN:GetTopScreen()
end

local function bindTooltip()
	TOOLTIP.Actor = tooltipActor
	TOOLTIP.Pointer = pointerActor
	TOOLTIP.ClickWave = clickWaveActor
end

local function releaseTooltip()
	if tooltipActor then tooltipActor:visible(false) end
	if TOOLTIP.Actor == tooltipActor then
		TOOLTIP.Actor, TOOLTIP.Pointer, TOOLTIP.ClickWave = nil, nil, nil
	end
end

local function updateLoop()
	if not hasFocus() then return end
	bindTooltip()
	TOOLTIP:SetPosition(INPUTFILTER:GetMouseX(), INPUTFILTER:GetMouseY())
	if screenName ~= "ScreenTextEntry" then BUTTON:UpdateMouseState() end
end

local function cursorCheck()
	if not hasFocus() then return end
	local fullscreen = not PREFSMAN:GetPreference("Windowed")
		and not PREFSMAN:GetPreference("FullscreenIsBorderlessWindow")
	pointerActor:visible(fullscreen)
end

local function handleInput(event)
	if not hasFocus() or not event or not event.DeviceInput then return end
	bindTooltip()
	BUTTON.InputCallback(event)
end

local function activate(self)
	if not hasFocus() then return end
	bindTooltip()
	if screenName ~= "ScreenTextEntry" and registeredScreen ~= owner then
		owner:AddInputCallback(handleInput)
		registeredScreen = owner
	end
	self:SetUpdateFunction(updateLoop)
	local refreshRate = DISPLAY:GetDisplayRefreshRate()
	if refreshRate and refreshRate > 0 then
		self:SetUpdateFunctionInterval(1 / refreshRate)
	end
	cursorCheck()
	updateLoop()
end

local function finish(self)
	if not owner then return end
	owner = nil
	self:SetUpdateFunction(nil)
	releaseTooltip()
	if registeredScreen then
		registeredScreen:RemoveInputCallback(handleInput)
		registeredScreen = nil
	end
	if screenName and screenName ~= "ScreenTextEntry" then
		BUTTON:ResetButtonTable(screenName)
	end
end

-- Fallback's Init assigns to the global singleton. Capture the child from this
-- frame and put the previous binding back until this screen is actually active.
local function own(definition, field, assign)
	local init = definition.InitCommand
	definition.InitCommand = function(self)
		local previous = TOOLTIP[field]
		init(self)
		TOOLTIP[field] = previous
		assign(self)
	end
	definition.ReloadedScriptsMessageCommand = nil
	return definition
end

local tooltip, pointer, clickWave = TOOLTIP:New()
local t = Def.ActorFrame {
	BeginCommand = function(self)
		owner = SCREENMAN:GetTopScreen()
		if owner then screenName = owner:GetName() end
		self:queuecommand("RefreshCursor")
	end,
	OnCommand = function(self)
		self:draworder(20000)
		activate(self)
	end,
	GainFocusCommand = activate,
	RefreshCursorCommand = activate,
	LoseFocusCommand = releaseTooltip,
	OffCommand = finish,
	EndCommand = finish,
	CancelCommand = finish,
	WindowedChangedMessageCommand = cursorCheck,
	ReloadedScriptsMessageCommand = function(self)
		if hasFocus() then
			bindTooltip()
			cursorCheck()
		end
	end,

	own(tooltip, "Actor", function(self) tooltipActor = self end),
	own(pointer, "Pointer", function(self) pointerActor = self end),
	own(clickWave, "ClickWave", function(self) clickWaveActor = self end),
}

return t
