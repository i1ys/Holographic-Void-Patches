local gameplay = ...
local minimalisticHUDVisible = gameplay.minimalisticHUDVisible
local animateGameplayHUDVisibility = gameplay.animateGameplayHUDVisibility

if HV.ShowNGIndicator() and not gameplay.isSync then
	local isReverse = GAMESTATE:GetPlayerState(PLAYER_1):GetCurrentPlayerOptions():UsingReverse()
	local ngY = isReverse and (SCREEN_CENTER_Y + 164 - 40) or (SCREEN_CENTER_Y - 164 + 40)
	local colOffsets = {-96, -32, 32, 96}

	local ngFrame = Def.ActorFrame {
		Name = "NGIndicator",
		InitCommand = function(self)
			self:visible(minimalisticHUDVisible(true))
		end,
		HV_MinimalisticModeChangedMessageCommand = function(self, params)
			animateGameplayHUDVisibility(self, minimalisticHUDVisible(true, params and params.Enabled))
		end,
	}
	for i = 1, 4 do
		ngFrame[#ngFrame + 1] = LoadFont("Common Normal") .. {
			Name = "NG_" .. i,
			InitCommand = function(self)
				self:xy(SCREEN_CENTER_X + colOffsets[i], ngY)
				self:zoom(1.2):diffuse(color("#FF4444")):diffusealpha(0):settext("NG")
			end,
			JudgmentMessageCommand = function(self, params)
				if params.HoldNoteScore == "HoldNoteScore_LetGo" then
					local laneMatch = false
					if params.Notes and params.Notes[i] ~= nil then
						laneMatch = true
					elseif params.FirstTrack == (i - 1) then
						laneMatch = true
					end
					if laneMatch then
						self:stoptweening():diffusealpha(1):zoom(1.2):linear(0.2):zoom(1.5):linear(0.2):zoom(1.2):sleep(0.5):linear(0.2):diffusealpha(0)
					end
				end
			end
		}
	end
	return ngFrame
end
