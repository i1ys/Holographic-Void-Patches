local focus = {}
local screen, priorRedirection
local ownsRedirection = false
local callbacks, held = {}, {}

local function syncRedirection()
	if not focus.isCurrent() then return end
	local capture = HV.ActiveTab ~= "" or next(held) ~= nil
	if capture and not ownsRedirection then
		priorRedirection = SCREENMAN:get_input_redirected(PLAYER_1)
		SCREENMAN:set_input_redirected(PLAYER_1, true)
		ownsRedirection = true
	elseif capture and not SCREENMAN:get_input_redirected(PLAYER_1) then
		SCREENMAN:set_input_redirected(PLAYER_1, true)
	elseif not capture and ownsRedirection then
		SCREENMAN:set_input_redirected(PLAYER_1, priorRedirection)
		ownsRedirection = false
	end
end

function focus.attach()
	if not screen then
		screen = SCREENMAN:GetTopScreen()
		HV.ActiveTab = ""
	end
end

function focus.isCurrent()
	return screen ~= nil and SCREENMAN:GetTopScreen() == screen and not screen:IsTransitioning()
end

function focus.bind(handler)
	if not screen then return end
	local callback = function(event)
		if not focus.isCurrent() or not event or not event.DeviceInput then return false end
		local device = event.DeviceInput.device or "InputDevice_Key"
		local button = event.DeviceInput.button
		local keys = held[device]
		if keys and keys[button] and event.type ~= "InputEventType_FirstPress" then
			if event.type == "InputEventType_Release" then
				keys[button] = nil
				if next(keys) == nil then held[device] = nil end
				syncRedirection()
			end
			return true
		end
		if HV.ActiveTab == "" and next(held) ~= nil then return true end
		return handler(event, screen)
	end
	callbacks[#callbacks + 1] = callback
	screen:AddInputCallback(callback)
end

function focus.hold(event)
	local device = event.DeviceInput.device or "InputDevice_Key"
	local button = event.DeviceInput.button
	if not button then return end
	held[device] = held[device] or {}
	held[device][button] = true
	syncRedirection()
end

function focus.setTab(tab)
	if not focus.isCurrent() then return end
	HV.ActiveTab = tab or ""
	syncRedirection()
end

function focus.update()
	if not focus.isCurrent() then return end
	-- A key released while a stacked prompt had focus never reaches this screen's callback.
	for device, keys in pairs(held) do
		for button in pairs(keys) do
			if not INPUTFILTER:IsBeingPressed(ToEnumShortString(button), ToEnumShortString(device)) then
				keys[button] = nil
			end
		end
		if next(keys) == nil then held[device] = nil end
	end
	syncRedirection()
end

function focus.dispose()
	if not screen then return end
	local oldScreen = screen
	screen = nil
	if ownsRedirection then
		local top = SCREENMAN:GetTopScreen()
		if not top or top == oldScreen then SCREENMAN:set_input_redirected(PLAYER_1, priorRedirection) end
	end
	ownsRedirection = false
	HV.ActiveTab = ""
	held = {}
	for _, callback in ipairs(callbacks) do oldScreen:RemoveInputCallback(callback) end
	callbacks = {}
end

return focus
