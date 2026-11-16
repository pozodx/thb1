-- FuseboxObjectiveAnnounceService.server.lua
-- Watches StageManager for the Fuseboxes stage becoming active (fires
-- exactly once when it starts — either as the round's first stage, or
-- after the previous stage is cleared — so no debounce/reset needed).
-- Shows the "NEW OBJECTIVE" banner to every survivor. Killer is exempt.
--
-- The banner is never shown before REVEAL_REMAINING_SECONDS is reached on the
-- match timer (11:00 on a 12:00 match = the moment the first objective is
-- revealed). A stage that becomes active later than that (e.g. after the
-- previous stage is cleared) is announced after a short delay instead.
--
-- The banner is sent only once the round is really running (match timer started).
-- The round's FIRST stage fires during round setup, before RoundStarted reaches
-- the clients, so announcing instantly could get it lost.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local StageManager = require(ServerScriptService.Server.StageManager)
local ObjectiveAnnouncementService = require(ReplicatedStorage.Shared.ObjectiveAnnouncementService)

local STAGE_NAME = "Fuseboxes"
local REVEAL_REMAINING_SECONDS = 11 * 60 -- announce once the match timer shows 11:00 (or less)
local ANNOUNCE_DELAY = 1.5 -- delay for stages that start after the reveal time has already passed
local MAX_WAIT_FOR_ROUND = 5 -- how long to wait for the match timer to start

local matchTimerScript = ServerScriptService.Server:WaitForChild("MatchTimerService")
local getRemainingFunction = matchTimerScript:WaitForChild("MatchTimer_GetRemaining")

local function getRemaining()
	return getRemainingFunction:Invoke()
end

local function isRoundRunning()
	return getRemaining() > 0
end

local function waitUntilRoundIsRunning()
	local waited = 0
	while not isRoundRunning() and waited < MAX_WAIT_FOR_ROUND do
		task.wait(0.1)
		waited += 0.1
	end
end

-- Waits until the match timer reaches the reveal time. Returns early if the
-- round ends or the stage is no longer active.
local function waitUntilReveal()
	while isRoundRunning()
		and StageManager.IsStageActive(STAGE_NAME)
		and getRemaining() > REVEAL_REMAINING_SECONDS do
		task.wait(0.25)
	end
end

StageManager.StageChanged.Event:Connect(function(nextStage)
	print("FuseboxObjectiveAnnounceService: StageChanged fired with nextStage =", nextStage)

	if nextStage ~= STAGE_NAME then
		print("  -> not the " .. STAGE_NAME .. " stage, skipping")
		return
	end

	task.spawn(function()
		waitUntilRoundIsRunning()
		if not isRoundRunning() then
			print("  -> round isn't running, no banner (server start or aborted round)")
			return
		end

		if getRemaining() > REVEAL_REMAINING_SECONDS then
			-- first objective: hold the banner until the 11:00 reveal
			waitUntilReveal()
		else
			-- stage started after the reveal time: short delay only
			task.wait(ANNOUNCE_DELAY)
		end

		if not StageManager.IsStageActive(STAGE_NAME) or not isRoundRunning() then
			print("  -> " .. STAGE_NAME .. " stage is already over, no banner")
			return
		end

		for _, player in ipairs(Players:GetPlayers()) do
			if not player:GetAttribute("IsKiller") then
				print("  -> announcing to", player.Name)
				ObjectiveAnnouncementService.AnnouncePlayer(
					player,
					"NEW OBJECTIVE",
					"FIND FUSES AND POWER THE FUSEBOXES"
				)
			else
				print("  -> skipping killer", player.Name)
			end
		end
	end)
end)

print("FuseboxObjectiveAnnounceService loaded.")

return true