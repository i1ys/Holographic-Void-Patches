local gameplay = ...

local lastToastyCombo = 0

local function safeGetThemePath(type, folder, element)
	local possiblePaths = {
		"Themes/Holographic Void/" .. folder .. "/" .. element,
		"Themes/_fallback/" .. folder .. "/" .. element
	}
	for _, p in ipairs(possiblePaths) do
		local extensions = type == "G" and {".png", ".jpg", ".jpeg", ".gif", ".webm"} or {".ogg", ".wav", ".mp3"}
		for _, ext in ipairs(extensions) do
			if FILEMAN:DoesFileExist(p .. ext) then
				return p .. ext
			end
		end
	end
	return nil
end

local toastyImgPath = safeGetThemePath("G", "Graphics", "toasty") or safeGetThemePath("G", "Graphics", "Common toasty")
local toastySndPath = safeGetThemePath("S", "Sounds", "toasty") or safeGetThemePath("S", "Sounds", "Common toasty")

if not gameplay.isSync then
return Def.ActorFrame {
	Name = "Toasty",
	InitCommand = function(self)
		lastToastyCombo = 0
	end,

	Def.Sprite {
		Name = "ToastySprite",
		InitCommand = function(self)
			self:xy(SCREEN_WIDTH + 100, SCREEN_CENTER_Y):diffusealpha(0)
			if toastyImgPath then
				self:Load(toastyImgPath)
			end
		end,
		StartTransitioningCommand = function(self)
			if not toastyImgPath then return end
			self:stoptweening()
			self:diffusealpha(1)
			self:decelerate(0.25):x(SCREEN_WIDTH - 100)
			self:sleep(1.75)
			self:accelerate(0.5):x(SCREEN_WIDTH + 100)
			self:linear(0):diffusealpha(0)
		end
	},

	Def.Sound {
		Name = "ToastySound",
		InitCommand = function(self)
			if toastySndPath then
				self:load(toastySndPath)
			end
		end,
		StartTransitioningCommand = function(self)
			if toastySndPath then self:play() end
		end
	},

	JudgmentMessageCommand = function(self)
		local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats()
		if pss then
			local combo = pss:GetCurrentCombo()
			if combo and combo >= 250 then
				local milestone = math.floor(combo / 250)
				local lastMilestone = math.floor(lastToastyCombo / 250)
				if milestone > lastMilestone then
					self:playcommand("StartTransitioning")
				end
			end
			if combo then
				lastToastyCombo = combo
			end
		end
	end
}
end
