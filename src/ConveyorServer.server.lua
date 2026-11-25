local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
if not sharedFolder then
	sharedFolder = Instance.new("Folder")
	sharedFolder.Name = "Shared"
	sharedFolder.Parent = ReplicatedStorage
end

local remotesFolder = sharedFolder:FindFirstChild("Remotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "Remotes"
	remotesFolder.Parent = sharedFolder
end

local function getOrCreateRemote(remoteName)
	local remote = remotesFolder:FindFirstChild(remoteName)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = remoteName
		remote.Parent = remotesFolder
	end
	assert(remote:IsA("RemoteEvent"), remoteName .. " must be a RemoteEvent")
	return remote
end

local changeIntervalRemote = getOrCreateRemote("ChangeInterval")
local spawnBagRemote = getOrCreateRemote("SpawnBag")
local bagClickedRemote = getOrCreateRemote("BagClicked")
local bagSnapshotRemote = getOrCreateRemote("BagSnapshot")
local requestBagSnapshotRemote = getOrCreateRemote("RequestBagSnapshot")
local requestIntervalStateRemote = getOrCreateRemote("RequestIntervalState")
local intervalStateRemote = getOrCreateRemote("IntervalState")

local MAX_BAGS = 30
local MIN_INTERVAL = 0.1
local MAX_INTERVAL = 5.0
local spawnInterval = 1.0

local CONVEYOR_START = Vector3.new(0, 5, 0)
local CONVEYOR_END = Vector3.new(0, 5, 50)
local CONVEYOR_LENGTH = (CONVEYOR_END - CONVEYOR_START).Magnitude
local CONVEYOR_SPEED = 10

local timings = {
	spawnDuration = 0.5,
	transitDuration = CONVEYOR_LENGTH / CONVEYOR_SPEED,
	despawnDuration = 0.3
}
local TOTAL_BAG_LIFETIME = timings.spawnDuration
	+ timings.transitDuration
	+ timings.despawnDuration

local materials = {
	Enum.Material.Plastic,
	Enum.Material.Wood,
	Enum.Material.Neon,
	Enum.Material.Fabric,
	Enum.Material.Metal,
	Enum.Material.SmoothPlastic
}

local activeBags = {}
local activeBagsCount = 0
local lastIntervalRequest = {}
local lastClickRequest = {}
local lastBagSnapshotRequest = {}
local lastIntervalStateRequest = {}

local controller = nil
local controlPanelTemplate = ServerStorage:WaitForChild("ControlPanel")

local function giveControlPanel(player)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		playerGui = player:WaitForChild("PlayerGui")
	end

	local oldPanel = playerGui:FindFirstChild("ControlPanel")
	if oldPanel then
		oldPanel:Destroy()
	end

	local panel = controlPanelTemplate:Clone()
	panel.Name = "ControlPanel"
	panel.ResetOnSpawn = false
	panel.Parent = playerGui
end

local function assignController(player)
	controller = player
	giveControlPanel(player)
	print(string.format("[Server] %s is now the interval controller.", player.Name))
end

local function assignFirstAvailableController()
	if controller and controller.Parent == Players then
		return
	end

	controller = nil
	local currentPlayers = Players:GetPlayers()
	if #currentPlayers > 0 then
		assignController(currentPlayers[1])
	end
end

local function getBagPosition(bagData, now)
	local elapsed = math.max(0, now - bagData.startTime)
	if elapsed <= timings.spawnDuration then
		return CONVEYOR_START
	end

	local travelElapsed = math.clamp(
		elapsed - timings.spawnDuration,
		0,
		timings.transitDuration
	)
	local progress = travelElapsed / timings.transitDuration
	return CONVEYOR_START:Lerp(CONVEYOR_END, progress)
end

local function spawnBag()
	if activeBagsCount >= MAX_BAGS then
		return
	end

	local bagId = HttpService:GenerateGUID(false)
	local randomColor = Color3.new(math.random(), math.random(), math.random())
	local randomMaterial = materials[math.random(1, #materials)]
	local startTime = workspace:GetServerTimeNow()

	activeBags[bagId] = {
		color = randomColor,
		material = randomMaterial,
		startTime = startTime
	}
	activeBagsCount += 1

	spawnBagRemote:FireAllClients(
		bagId,
		randomColor,
		randomMaterial,
		startTime,
		timings
	)

	task.delay(TOTAL_BAG_LIFETIME, function()
		if activeBags[bagId] then
			activeBags[bagId] = nil
			activeBagsCount = math.max(0, activeBagsCount - 1)
		end
	end)
end

local function sendBagSnapshot(player)
	local snapshot = {}

	for bagId, bagData in pairs(activeBags) do
		table.insert(snapshot, {
			id = bagId,
			color = bagData.color,
			material = bagData.material,
			startTime = bagData.startTime
		})
	end

	bagSnapshotRemote:FireClient(player, snapshot, timings)
end

local function isRateLimited(rateTable, player, minimumDelay)
	local now = os.clock()
	local previous = rateTable[player]

	if previous and now - previous < minimumDelay then
		return true
	end

	rateTable[player] = now
	return false
end

-- The client requests state only after its corresponding listeners are connected.
requestBagSnapshotRemote.OnServerEvent:Connect(function(player)
	if isRateLimited(lastBagSnapshotRequest, player, 1.0) then
		return
	end

	sendBagSnapshot(player)
end)

requestIntervalStateRemote.OnServerEvent:Connect(function(player)
	if isRateLimited(lastIntervalStateRequest, player, 0.5) then
		return
	end

	if player == controller then
		intervalStateRemote:FireClient(player, spawnInterval)
	end
end)

bagClickedRemote.OnServerEvent:Connect(function(player, bagId)
	if isRateLimited(lastClickRequest, player, 0.2) then
		return
	end

	if type(bagId) ~= "string" or #bagId > 64 then
		return
	end

	local bagData = activeBags[bagId]
	if not bagData then
		return
	end

	local bagAge = workspace:GetServerTimeNow() - bagData.startTime
	if bagAge >= TOTAL_BAG_LIFETIME then
		return
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	local bagPosition = getBagPosition(bagData, workspace:GetServerTimeNow())
	if (rootPart.Position - bagPosition).Magnitude > 14 then
		return
	end

	print(string.format("[Server] Player %s clicked bag ID: %s", player.Name, bagId))
	-- No currency, item, or reward is granted by this prototype.
end)

changeIntervalRemote.OnServerEvent:Connect(function(player, newInterval)
	-- Rate-limit every sender before authorization checks. Rejected requests stay silent.
	if isRateLimited(lastIntervalRequest, player, 0.15) then
		return
	end

	if player ~= controller then
		return
	end

	if typeof(newInterval) ~= "number"
		or newInterval ~= newInterval
		or newInterval < MIN_INTERVAL
		or newInterval > MAX_INTERVAL then
		intervalStateRemote:FireClient(player, spawnInterval)
		return
	end

	local roundedInterval = math.floor(newInterval * 10 + 0.5) / 10
	spawnInterval = roundedInterval

	print(string.format(
		"[Server] Interval changed to %.1fs by %s",
		spawnInterval,
		player.Name
	))

	-- Echo the accepted server value so the UI displays the authoritative setting.
	intervalStateRemote:FireClient(player, spawnInterval)
end)

Players.PlayerAdded:Connect(function(player)
	if not controller then
		assignController(player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastIntervalRequest[player] = nil
	lastClickRequest[player] = nil
	lastBagSnapshotRequest[player] = nil
	lastIntervalStateRequest[player] = nil

	if player == controller then
		controller = nil

		task.defer(function()
			assignFirstAvailableController()
		end)
	end
end)

-- Also handles players already present if this Script starts after they join.
assignFirstAvailableController()

task.spawn(function()
	while true do
		spawnBag()
		task.wait(spawnInterval)
	end
end)
