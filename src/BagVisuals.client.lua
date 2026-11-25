local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local remotesFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes")
local spawnBagRemote = remotesFolder:WaitForChild("SpawnBag")
local bagSnapshotRemote = remotesFolder:WaitForChild("BagSnapshot")
local requestBagSnapshotRemote = remotesFolder:WaitForChild("RequestBagSnapshot")
local bagClickedRemote = remotesFolder:WaitForChild("BagClicked")

local CONVEYOR_START = Vector3.new(0, 5, 0)
local CONVEYOR_END = Vector3.new(0, 5, 50)
local BAG_SIZE = Vector3.new(2, 2, 2)

local localBags = {}

local function removeBag(bagId)
	local bag = localBags[bagId]
	if bag then
		localBags[bagId] = nil
		bag:Destroy()
	end
end

local function createBagVisual(bagId, color, material, serverStartTime, timings)
	if type(bagId) ~= "string" or localBags[bagId] then
		return
	end

	if typeof(color) ~= "Color3" or typeof(material) ~= "EnumItem" then
		return
	end

	local spawnDuration = timings.spawnDuration
	local transitDuration = timings.transitDuration
	local despawnDuration = timings.despawnDuration
	local totalDuration = spawnDuration + transitDuration + despawnDuration
	local elapsed = math.max(0, workspace:GetServerTimeNow() - serverStartTime)

	if elapsed >= totalDuration then
		return
	end

	local bag = Instance.new("Part")
	bag.Name = "Bag_" .. bagId
	bag.Size = BAG_SIZE
	bag.Color = color
	bag.Material = material
	bag.Anchored = true
	bag.CanCollide = false
	bag.Parent = workspace

	local idValue = Instance.new("StringValue")
	idValue.Name = "UUID"
	idValue.Value = bagId
	idValue.Parent = bag

	localBags[bagId] = bag

	local function finishBag()
		if localBags[bagId] == bag then
			localBags[bagId] = nil
		end
		if bag.Parent then
			bag:Destroy()
		end
	end

	if elapsed < spawnDuration then
		bag.Size = Vector3.new(0, 0, 0)
		bag.Position = CONVEYOR_START

		local remainingSpawn = spawnDuration - elapsed
		local spawnTween = TweenService:Create(
			bag,
			TweenInfo.new(remainingSpawn, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
			{Size = BAG_SIZE}
		)
		spawnTween:Play()

		task.delay(remainingSpawn, function()
			if localBags[bagId] ~= bag or not bag.Parent then
				return
			end

			local remainingTravel = transitDuration
			local moveTween = TweenService:Create(
				bag,
				TweenInfo.new(remainingTravel, Enum.EasingStyle.Linear),
				{Position = CONVEYOR_END}
			)
			moveTween:Play()
			moveTween.Completed:Once(function()
				if localBags[bagId] ~= bag or not bag.Parent then
					return
				end

				local despawnTween = TweenService:Create(
					bag,
					TweenInfo.new(despawnDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{Size = Vector3.new(0, 0, 0), Transparency = 1}
				)
				despawnTween:Play()
				despawnTween.Completed:Once(finishBag)
			end)
		end)
	else
		local travelElapsed = elapsed - spawnDuration
		local travelProgress = math.clamp(travelElapsed / transitDuration, 0, 1)
		bag.Position = CONVEYOR_START:Lerp(CONVEYOR_END, travelProgress)

		if elapsed < spawnDuration + transitDuration then
			local remainingTravel = transitDuration - travelElapsed
			local moveTween = TweenService:Create(
				bag,
				TweenInfo.new(remainingTravel, Enum.EasingStyle.Linear),
				{Position = CONVEYOR_END}
			)
			moveTween:Play()
			moveTween.Completed:Once(function()
				if localBags[bagId] ~= bag or not bag.Parent then
					return
				end

				local despawnTween = TweenService:Create(
					bag,
					TweenInfo.new(despawnDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{Size = Vector3.new(0, 0, 0), Transparency = 1}
				)
				despawnTween:Play()
				despawnTween.Completed:Once(finishBag)
			end)
		else
			local despawnElapsed = elapsed - spawnDuration - transitDuration
			bag.Position = CONVEYOR_END
			local remainingDespawn = despawnDuration - despawnElapsed
			local despawnTween = TweenService:Create(
				bag,
				TweenInfo.new(remainingDespawn, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{Size = Vector3.new(0, 0, 0), Transparency = 1}
			)
			despawnTween:Play()
			despawnTween.Completed:Once(finishBag)
		end
	end
end

spawnBagRemote.OnClientEvent:Connect(function(bagId, color, material, serverStartTime, timings)
	createBagVisual(bagId, color, material, serverStartTime, timings)
end)

bagSnapshotRemote.OnClientEvent:Connect(function(activeBags, timings)
	if type(activeBags) ~= "table" then
		return
	end

	for _, bagData in ipairs(activeBags) do
		createBagVisual(
			bagData.id,
			bagData.color,
			bagData.material,
			bagData.startTime,
			timings
		)
	end
end)

-- Request the current conveyor state only after both client listeners are ready.
requestBagSnapshotRemote:FireServer()

mouse.Button1Down:Connect(function()
	local target = mouse.Target
	if not target then
		return
	end

	local idValue = target:FindFirstChild("UUID")
	if idValue and idValue:IsA("StringValue") then
		local bagId = idValue.Value
		if localBags[bagId] == target then
			bagClickedRemote:FireServer(bagId)
		end
	end
end)
