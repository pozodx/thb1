-- KillerChanceToggle.client.lua
-- Inside LobbyUI > Other > KillerChance (frames can be nested at any depth),
-- 4 frames named '0'/'1'/'2'/'3', each containing a button (any name:
-- 'Button', 'button'...), let the player pick their odds of being chosen
-- as killer. 0 = never picked, 1 = default/normal odds, 2/3 = increasingly
-- more likely. Selecting one sends it to the server
-- (KillerChanceService.server.lua), which weights killer selection in
-- LobbyService.server.lua accordingly.
--
-- Selected look: if the number frame has 'Selected' / 'Unselected' UIGradients
-- they are toggled. Otherwise the frame's BackgroundColor3 is used
-- (green = selected, gray = not selected). Edit the two colors below.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SELECTED_COLOR = Color3.fromRGB(60, 200, 90)
local UNSELECTED_COLOR = Color3.fromRGB(70, 70, 70)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local screenGui = playerGui:WaitForChild("LobbyUI") -- adjust if named differently
local otherFolder = screenGui:WaitForChild("Other")
local killerChanceFrame = otherFolder:WaitForChild("KillerChance")

local killerChanceRemote = ReplicatedStorage:FindFirstChild("SetKillerChance")
if not killerChanceRemote then
	killerChanceRemote = Instance.new("RemoteEvent")
	killerChanceRemote.Name = "SetKillerChance"
	killerChanceRemote.Parent = ReplicatedStorage
end

local VALID_VALUES = { [0] = true, [1] = true, [2] = true, [3] = true }

-- Case-insensitive search for a direct child by name
local function findChildIgnoreCase(parent, name)
	local lowered = name:lower()
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name:lower() == lowered then
			return child
		end
	end
	return nil
end

-- First button (TextButton / ImageButton) found anywhere inside the frame
local function findButton(frame)
	for _, descendant in ipairs(frame:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			return descendant
		end
	end
	return nil
end

local options = {} -- [value] = { frame, button, selectedGradient, unselectedGradient }

-- Search at any depth, so an extra 'Frame' between KillerChance and the
-- number frames doesn't matter.
for _, descendant in ipairs(killerChanceFrame:GetDescendants()) do
	local value = tonumber(descendant.Name)
	if value and VALID_VALUES[value] and descendant:IsA("GuiObject") and not descendant:IsA("GuiButton") then
		local button = findButton(descendant)
		if button then
			options[value] = {
				frame = descendant,
				button = button,
				selectedGradient = findChildIgnoreCase(descendant, "Selected"),
				unselectedGradient = findChildIgnoreCase(descendant, "Unselected"),
			}
		else
			warn("KillerChanceToggle: frame '" .. descendant:GetFullName() .. "' has no button inside.")
		end
	end
end

if next(options) == nil then
	warn("KillerChanceToggle: no frames named 0/1/2/3 found inside " .. killerChanceFrame:GetFullName() .. ".")
end

local function refreshSelection()
	local current = player:GetAttribute("KillerChance")
	if current == nil then
		current = 1
	end
	for value, option in pairs(options) do
		local isChosen = (value == current)

		if option.selectedGradient or option.unselectedGradient then
			if option.selectedGradient then
				option.selectedGradient.Enabled = isChosen
			end
			if option.unselectedGradient then
				option.unselectedGradient.Enabled = not isChosen
			end
		else
			-- no gradients: color the frame itself
			option.frame.BackgroundColor3 = isChosen and SELECTED_COLOR or UNSELECTED_COLOR
		end
	end
end

for value, option in pairs(options) do
	option.button.Activated:Connect(function()
		killerChanceRemote:FireServer(value)
		-- instant visual feedback (the server value will confirm it right after)
		player:SetAttribute("KillerChance", value)
	end)
end

player:GetAttributeChangedSignal("KillerChance"):Connect(refreshSelection)
refreshSelection()