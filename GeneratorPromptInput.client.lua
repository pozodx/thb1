-- GeneratorPromptInput.client.lua
-- Tracks the nearest generator in range (no visual label) and
-- sends hold start/stop signals to repair it.
-- The player is only frozen once the SERVER confirms the repair started
-- (GeneratorActionStarted), so nothing happens if it's not the right objective.
-- Once confirmed: frozen for at least FREEZE_TIME seconds, and until every
-- movement input is released. Releasing E unfreezes immediately.
-- Moving after the freeze cancels the repair.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local generatorsFolder = Workspace:WaitForChild("Generators")

local interactRemote = ReplicatedStorage:FindFirstChild("GeneratorInteract")
if not interactRemote then
	interactRemote = Instance.new("RemoteEvent")
	interactRemote.Name = "GeneratorInteract"
	interactRemote.Parent = ReplicatedStorage
end

local actionStartedRemote = ReplicatedStorage:WaitForChild("GeneratorActionStarted")

local RANGE = 10
local FREEZE_TIME = 0.3 -- minimum seconds the player can't move once the repair starts
local CONFIRM_TIMEOUT = 0.6 -- seconds to wait for the server's confirmation before giving up
local INPUT_DEADZONE = 0.05
local FREEZE_BIND_NAME = "GeneratorFreeze"

local currentTarget = nil
local isHoldingE = false
local isPending = false -- E pressed, waiting for the server to confirm
local pendingToken = 0
local isFrozen = false
local freezeBound = false
local freezeToken = 0 -- invalidates older freeze loops

local MOVEMENT_KEYS = {
	Enum.KeyCode.W,
	Enum.KeyCode.A,
	Enum.KeyCode.S,
	Enum.KeyCode.D,
	Enum.KeyCode.Up,
	Enum.KeyCode.Down,
	Enum.KeyCode.Left,
	Enum.KeyCode.Right,
}

-- === Movement freeze ===
-- Instead of disabling the controls (which loses keys that are already held),
-- we override the humanoid's movement every frame, right after the default
-- controls have run. The controls keep tracking the held keys underneath,
-- so as soon as the override stops, movement resumes instantly.

local controls = nil
local function getControls()
	if controls then
		return controls
	end
	local ok, result = pcall(function()
		local playerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
		return playerModule:GetControls()
	end)
	if ok then
		controls = result
	end
	return controls
end

-- True while the player is physically pushing any movement input
-- (keyboard, gamepad stick or mobile thumbstick)
local function isMovementInputHeld()
	local c = getControls()
	if c and type(c.GetMoveVector) == "function" then
		local ok, moveVector = pcall(function()
			return c:GetMoveVector()
		end)
		if ok and moveVector then
			return moveVector.Magnitude > INPUT_DEADZONE
		end
	end

	-- fallback if the controls couldn't be read
	for _, keyCode in ipairs(MOVEMENT_KEYS) do
		if UserInputService:IsKeyDown(keyCode) then
			return true
		end
	end
	return false
end

local function releaseFreeze()
	isFrozen = false
	if freezeBound then
		freezeBound = false
		RunService:UnbindFromRenderStep(FREEZE_BIND_NAME)
	end
end

local function unfreeze()
	freezeToken += 1
	releaseFreeze()
end

local function freeze()
	freezeToken += 1
	local myToken = freezeToken
	isFrozen = true

	if not freezeBound then
		freezeBound = true
		RunService:BindToRenderStep(FREEZE_BIND_NAME, Enum.RenderPriority.Input.Value + 1, function()
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid:Move(Vector3.zero, false)
				humanoid.Jump = false
			end
		end)
	end

	task.spawn(function()
		task.wait(FREEZE_TIME)

		-- stay frozen until every movement input is released,
		-- so an input held from before the action can't cancel it
		while freezeToken == myToken and isMovementInputHeld() do
			task.wait()
		end

		if freezeToken == myToken then
			releaseFreeze()
		end
	end)
end

-- === End freeze ===

local function findMainPart(generatorModel)
	for _, descendant in ipairs(generatorModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function getMyPosition()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root.Position
end

-- True when the player is actually moving (only checked once the repair is confirmed and the freeze is over)
local function isMoving()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.MoveDirection.Magnitude > 0
end

local function stopHolding()
	if isHoldingE and currentTarget then
		interactRemote:FireServer(currentTarget, "stop")
	end
	isHoldingE = false
	isPending = false
	pendingToken += 1
end

-- The server accepted the repair: freeze now
actionStartedRemote.OnClientEvent:Connect(function()
	if isHoldingE and isPending then
		isPending = false
		pendingToken += 1
		freeze()
	end
end)

RunService.Heartbeat:Connect(function()
	-- Moving while holding E cancels the repair (ignored while pending or frozen)
	if isHoldingE and currentTarget and not isPending and not isFrozen and isMoving() then
		stopHolding()
	end

	local myPosition = getMyPosition()
	if not myPosition then
		return
	end

	local nearestGenerator, nearestDist = nil, RANGE
	for _, generatorModel in ipairs(generatorsFolder:GetChildren()) do
		if generatorModel:IsA("Model") and not generatorModel:GetAttribute("Completed") then
			local mainPart = findMainPart(generatorModel)
			if mainPart then
				local dist = (mainPart.Position - myPosition).Magnitude
				if dist <= nearestDist then
					nearestGenerator = generatorModel
					nearestDist = dist
				end
			end
		end
	end

	if nearestGenerator ~= currentTarget then
		stopHolding()
		unfreeze()
		currentTarget = nearestGenerator
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end

	if input.KeyCode == Enum.KeyCode.E and currentTarget then
		isHoldingE = true
		isPending = true
		pendingToken += 1
		local myPendingToken = pendingToken

		interactRemote:FireServer(currentTarget, "start")

		-- No confirmation in time = the server refused (wrong objective, too far...): do nothing
		task.delay(CONFIRM_TIMEOUT, function()
			if isPending and pendingToken == myPendingToken then
				isPending = false
				isHoldingE = false
			end
		end)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.E and (isHoldingE or isFrozen) then
		stopHolding()
		unfreeze() -- movement works right away, even with a key still held
	end
end)

-- Safety: never leave the player frozen after dying/respawning
player.CharacterAdded:Connect(function()
	isHoldingE = false
	isPending = false
	pendingToken += 1
	unfreeze()
end)