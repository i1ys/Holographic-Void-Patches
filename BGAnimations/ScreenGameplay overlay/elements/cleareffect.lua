local gameplay = ...

local function CelebrationBurst()
	local burst = Def.ActorFrame{
		CelebrationCommand = function(self, params)
			local count = 0
			local maxRays = params.numRays or 10
			local speed = params.speed or 0.6
			local burstColor = params.color or color("#FFFFFF")

			self:RunCommandsOnChildren(function(child)
				count = count + 1
				if count <= maxRays then
					child:playcommand("Burst", {
						numRays = maxRays,
						speed = speed,
						color = burstColor,
						index = count
					})
				end
			end)
		end,
	}
	-- Create a pool of 24 rays (max intensity)
	for i = 1, 24 do
		burst[#burst+1] = Def.Quad{
			InitCommand = function(self)
				self:zoomto(2, 200):diffusealpha(0)
			end,
			BurstCommand = function(self, params)
				self:stoptweening():diffusealpha(0):zoomto(2, 0)
				-- Distribute rays evenly based on the current active count
				self:rotationz((params.index - 1) * (360 / params.numRays))

				-- Start white (or red flash for heartbreaks) then transition to clear type color
				if params.isHeartbreak then
					self:diffuse(color("#FF0000"))
				else
					self:diffuse(color("#FFFFFF"))
				end

				self:sleep(0.05):linear(params.speed * 0.4):zoomto(4, 400):diffusealpha(0.6):diffuse(params.color)
				self:linear(params.speed * 0.6):zoomto(0, 0):diffusealpha(0)
			end
		}
	end
	return burst
end

return Def.ActorFrame{
	Name = "EndOfChartClearType",
	InitCommand = function(self)
		self:Center():visible(true)
	end,

	CelebrationBurst(),

	Def.ActorFrame{
		Name = "CTRiseFrame",
		InitCommand = function(self)
			self:diffusealpha(0):y(30)  -- start below center
		end,
		OffCommand = function(self)
			if gameplay.isSync then return end

			-- Delay slightly to ensure statistics are stabilized
			self:sleep(0.05)

			local epn = gameplay.player
			local epss = STATSMAN:GetCurStageStats():GetPlayerStageStats(epn)
			if not epss then return end
			local steps = GAMESTATE:GetCurrentSteps()
			if not steps then return end

			local clearLevel = getClearLevel(epn, steps, epss)

			-- Fallback: if getClearLevel failed but it's a Full Combo
			if clearLevel > 7 and epss:FullComboOfScore("TapNoteScore_W3") then
				clearLevel = 7 -- Regular FC
			end

			-- MFC=1 ... FC=7
			if clearLevel <= 7 then
				local ctName = getClearType(epn, steps, epss)
				if clearLevel == 7 and (not ctName or ctName == "") then ctName = "FC" end

				local ctText = getClearTypeText(ctName)
				local ctColor = getClearTypeColor(ctName)

				-- Intensity settings: rays and speed
				local numRays = 10
				local burstSpeed = 0.6
				local isHeartbreak = false

				if clearLevel == 1 then -- MFC
					numRays = 24
					burstSpeed = 0.4
				elseif clearLevel == 2 then -- WF (Heartbreak)
					numRays = 20
					burstSpeed = 0.45
					isHeartbreak = true
				elseif clearLevel <= 4 then -- PFC variants
					numRays = 16
					burstSpeed = 0.5
				elseif clearLevel == 5 then -- BF (Heartbreak)
					numRays = 14
					burstSpeed = 0.55
					isHeartbreak = true
				end

				local txt = self:GetChild("CTText")
				txt:stoptweening():settext(ctText)

				-- Intense red flash for heartbreaks
				if isHeartbreak then
					txt:diffuse(color("#FF0000"))
				else
					txt:diffuse(color("#FFFFFF"))
				end

				-- Trigger dynamic burst
				self:GetParent():RunCommandsOnChildren(function(c)
					c:playcommand("Celebration", {
						numRays = numRays,
						speed = burstSpeed,
						color = ctColor,
						isHeartbreak = isHeartbreak
					})
				end)

				-- Rise-up animation: from y=30 to y=0
				self:stoptweening()
				self:y(30):diffusealpha(0):zoom(1.5)
				self:decelerate(0.5):y(0):diffusealpha(1):zoom(1)

				-- Special Heartbreak Shake/Pulse
				if clearLevel == 2 then -- WF: Jitter shake
					for i=1, 4 do
						self:sleep(0.02):x(-3):sleep(0.02):x(3)
					end
					self:sleep(0.02):x(0)
				elseif clearLevel == 5 then -- BF: Vertical thump/pulse
					self:bounce(0.2):effectmagnitude(0, -6, 0):effectclock("bgm"):effectperiod(0.1)
					self:sleep(0.4):stopeffect()
				end

				-- Color sweep: stay red/white then transition to clear type color
				if isHeartbreak then
					txt:sleep(0.4):linear(0.2):diffuse(color("#FFFFFF")):linear(0.5):diffuse(ctColor)
				else
					txt:sleep(0.3):linear(0.5):diffuse(ctColor)
				end

				-- Gentle pulse
				txt:sleep(0.2):linear(0.4):diffusealpha(0.8):linear(0.4):diffusealpha(1)

				-- Hold then fade out before the evaluation screen takes over
				self:sleep(3):smooth(1):diffusealpha(0):y(-10)
			end
		end,

		LoadFont("Common Large") .. {
			Name = "CTText",
			InitCommand = function(self)
				self:zoom(0.7):strokecolor(color("0,0,0,0.6"))
			end
		}
	}
}
