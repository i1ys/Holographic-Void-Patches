--- Holographic Void: Branching Logic
-- Handles redirection between screens based on game state (e.g. no songs).

Branch.AfterInit = function()
	-- If zero songs found (and no downloads in progress), redirect to core bundle selector
	if SONGMAN:GetNumSongs() == 0 and SONGMAN:GetNumAdditionalSongs() == 0 and #DLMAN:GetDownloads() == 0 then
		return "ScreenCoreBundleSelect"
	end
	
	-- Normal flow
	return "ScreenTitleMenu"
end

function SMOnlineScreen()
	if not IsNetSMOnline() then
		return "ScreenSelectMusic"
	end
	if not IsSMOnlineLoggedIn() then
		return "ScreenSMOnlineLogin"
	end
	return "ScreenNetRoom"
end

Branch.TitleMenu = function()
	return "ScreenTitleMenu"
end

Branch.AfterTitleMenu = function()
	if PROFILEMAN:GetNumLocalProfiles() == 0 then
		return "ScreenSelectMusic"
	end
	return "ScreenSelectProfile"
end

Branch.MultiScreen = function()
	if IsNetSMOnline() then
		return "ScreenNetSelectProfile"
	end
	return "ScreenNetworkOptions"
end

Branch.AfterSelectProfile = function()
	return "ScreenSelectMusic"
end

Branch.AfterNetSelectProfile = function()
	return SMOnlineScreen()
end

function Branch.CloseMultiplayerConnection()
	if IsNetConnected() then CloseConnection() end
end

function HV.GetMultiplayerRoomName()
	if not IsNetConnected() or not IsSMOnlineLoggedIn() then return end
	local room = NSMAN:GetCurrentRoomName()
	if room and room ~= "" then return room end
end

Branch.AfterSelectMusic = function()
	if SCREENMAN:GetTopScreen():GetGoToOptions() then return SelectFirstOptionsScreen() end
	return "ScreenStageInformation"
end

Branch.PlayerOptions = function()
	if SCREENMAN:GetTopScreen():GetGoToOptions() then return "ScreenPlayerOptions" end
	return "ScreenStageInformation"
end

Branch.BackOutOfMultiplayerRoom = function()
	return IsNetConnected() and IsSMOnlineLoggedIn() and "ScreenNetRoom" or "ScreenSelectMusic"
end

local function returnFromMultiplayerRound()
	if HV.GetMultiplayerRoomName() then return "ScreenNetSelectMusic" end
	return Branch.BackOutOfMultiplayerRoom()
end

Branch.AfterNetStageInformation = function()
	if HV.GetMultiplayerRoomName() then return ToNetGameplay() end
	return Branch.BackOutOfMultiplayerRoom()
end

Branch.AfterNetProfileSave = returnFromMultiplayerRound
Branch.BackOutOfNetPlayerOptions = returnFromMultiplayerRound
Branch.BackOutOfNetStageInformation = returnFromMultiplayerRound

Branch.LeavePackDownloader = function()
	return "ScreenTitleMenu"
end

Trace("Holographic Void: 09 Branch.lua loaded.")
