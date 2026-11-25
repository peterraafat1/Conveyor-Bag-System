local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotesFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
local changeIntervalRemote = remotesFolder:WaitForChild("ChangeInterval")
local requestIntervalStateRemote = remotesFolder:WaitForChild("RequestIntervalState")
local intervalStateRemote = remotesFolder:WaitForChild("IntervalState")

local controlPanel = script.Parent

if not controlPanel:IsA("ScreenGui") then
	warn("ControlPanel LocalScript must be inside the ControlPanel ScreenGui.")
	return
end

local frame = controlPanel:WaitForChild("Frame")
local sliderBtn = frame:WaitForChild("SliderButton")
local textLabel = frame:WaitForChild("IntervalText")

local MIN_INTERVAL = 0.1
local MAX_INTERVAL = 5.0

local dragging = false
local dragMoved = false
local activeTouch = nil
local lastPointerX = nil
local authoritativeInterval = nil
local selectedInterval = nil
local displaySuffix = ""
local pendingRequest = false
local lastRequestSentAt = -math.huge
local MIN_REQUEST_INTERVAL = 0.2
local CHANGE_ACK_TIMEOUT = 2.0
local STATE_RECOVERY_TIMEOUT = 2.0
local pendingRequestToken = 0
local recoveryRequestToken = 0
local recoveryInProgress = false

local function getMaxOffset()
	return math.max(0, frame.AbsoluteSize.X - sliderBtn.AbsoluteSize.X)
end

local function renderSlider()
	if selectedInterval == nil then
		textLabel.Text = "Interval: syncing..."
		return
	end

	local percentage = (selectedInterval - MIN_INTERVAL) / (MAX_INTERVAL - MIN_INTERVAL)
	local maxOffset = getMaxOffset()

	sliderBtn.Position = UDim2.new(
		0,
		percentage * maxOffset,
		sliderBtn.Position.Y.Scale,
		sliderBtn.Position.Y.Offset
	)

	textLabel.Text = string.format("Interval: %.1fs%s", selectedInterval, displaySuffix)
end

local function showInterval(interval, suffix)
	selectedInterval = math.clamp(interval, MIN_INTERVAL, MAX_INTERVAL)
	displaySuffix = suffix or ""
	renderSlider()
end

local function updateFromScreenX(screenX)
	local maxOffset = getMaxOffset()
	if maxOffset <= 0 then
		return
	end

	local relativePosition = math.clamp(
		screenX - frame.AbsolutePosition.X - (sliderBtn.AbsoluteSize.X / 2),
		0,
		maxOffset
	)

	local percentage = relativePosition / maxOffset
	local rawInterval = MIN_INTERVAL + ((MAX_INTERVAL - MIN_INTERVAL) * percentage)
	local roundedInterval = math.floor(rawInterval * 10 + 0.5) / 10

	showInterval(roundedInterval, " (preview)")
end

-- The server is the source of truth. Do not enable dragging until its value arrives.
intervalStateRemote.OnClientEvent:Connect(function(serverInterval)
	if typeof(serverInterval) ~= "number"
		or serverInterval ~= serverInterval
		or serverInterval < MIN_INTERVAL
		or serverInterval > MAX_INTERVAL then
		return
	end

	authoritativeInterval = serverInterval
	pendingRequest = false
	pendingRequestToken += 1 -- Invalidate any outstanding acknowledgement timeout.
	recoveryInProgress = false
	recoveryRequestToken += 1 -- Invalidate any outstanding recovery timeout.
	showInterval(serverInterval, "")
end)

textLabel.Text = "Interval: syncing..."
requestIntervalStateRemote:FireServer()

local function requestStateAfterTimeout()
	if not pendingRequest then
		return
	end

	-- Leave the pending state before asking for a fresh server snapshot.
	pendingRequest = false
	pendingRequestToken += 1
	recoveryInProgress = true
	recoveryRequestToken += 1
	local thisRecoveryToken = recoveryRequestToken
	showInterval(authoritativeInterval, " (checking server)")

	-- This is a single recovery request, not a retry loop.
	requestIntervalStateRemote:FireServer()

	task.delay(STATE_RECOVERY_TIMEOUT, function()
		if recoveryInProgress and recoveryRequestToken == thisRecoveryToken then
			recoveryInProgress = false
			showInterval(authoritativeInterval, " (sync failed; try again)")
		end
	end)
end

sliderBtn.InputBegan:Connect(function(input)
	if authoritativeInterval == nil or pendingRequest or recoveryInProgress or dragging then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging = true
		dragMoved = false
		activeTouch = nil
		lastPointerX = UserInputService:GetMouseLocation().X
	elseif input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragMoved = false
		activeTouch = input
		lastPointerX = input.Position.X
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not dragging then
		return
	end

	local pointerX = nil
	if input.UserInputType == Enum.UserInputType.MouseMovement and activeTouch == nil then
		pointerX = UserInputService:GetMouseLocation().X
	elseif input.UserInputType == Enum.UserInputType.Touch and input == activeTouch then
		pointerX = input.Position.X
	end

	if pointerX ~= nil then
		if lastPointerX == nil or math.abs(pointerX - lastPointerX) > 0 then
			dragMoved = true
			lastPointerX = pointerX
			updateFromScreenX(pointerX)
		end
	end
end)

local function finishDrag()
	if not dragging then
		return
	end

	dragging = false
	activeTouch = nil
	lastPointerX = nil

	-- A press/release without pointer movement is not treated as a drag.
	if dragMoved and selectedInterval ~= nil and selectedInterval ~= authoritativeInterval then
		pendingRequest = true
		displaySuffix = " (pending)"
		renderSlider()

		local requestedInterval = selectedInterval
		local waitTime = math.max(0, MIN_REQUEST_INTERVAL - (os.clock() - lastRequestSentAt))
		task.delay(waitTime, function()
			if not controlPanel.Parent or not pendingRequest then
				return
			end

			lastRequestSentAt = os.clock()
			pendingRequestToken += 1
			local thisRequestToken = pendingRequestToken
			changeIntervalRemote:FireServer(requestedInterval)

			-- If no server acknowledgement arrives, request the authoritative value once.
			task.delay(CHANGE_ACK_TIMEOUT, function()
				if pendingRequest and pendingRequestToken == thisRequestToken then
					requestStateAfterTimeout()
				end
			end)
		end)
	else
		showInterval(authoritativeInterval, "")
	end

	dragMoved = false
end

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		and dragging
		and activeTouch == nil then
		finishDrag()
	elseif input.UserInputType == Enum.UserInputType.Touch
		and dragging
		and input == activeTouch then
		finishDrag()
	end
end)

frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	renderSlider()
end)

controlPanel.AncestryChanged:Connect(function(_, parent)
	if parent == nil then
		dragging = false
		activeTouch = nil
		lastPointerX = nil
	end
end)
