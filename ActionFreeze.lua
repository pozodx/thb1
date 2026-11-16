-- ActionFreeze.lua
-- Put this in ReplicatedStorage.Shared (next to ActionAnimationService).
-- Briefly stops a player from moving when they start a timed action
-- (generator repair, fuse chest, healing, self-healing).

local ActionFreeze = {}

local FREEZE_TIME = 0.5

function ActionFreeze.Freeze(player, duration)
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	-- Already frozen: don't save the zeroed values as the "original" ones
	if player:GetAttribute("ActionFrozen") then
		return
	end
	player:SetAttribute("ActionFrozen", true)

	local oldSpeed = humanoid.WalkSpeed
	local oldJumpPower = humanoid.JumpPower
	local oldJumpHeight = humanoid.JumpHeight

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0

	task.delay(duration or FREEZE_TIME, function()
		player:SetAttribute("ActionFrozen", nil)
		if humanoid.Parent then
			humanoid.WalkSpeed = oldSpeed
			humanoid.JumpPower = oldJumpPower
			humanoid.JumpHeight = oldJumpHeight
		end
	end)
end

return ActionFreeze