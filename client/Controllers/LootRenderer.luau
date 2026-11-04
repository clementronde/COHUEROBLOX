--!strict
-- Draws loot from LootSnapshot (LootCodec): XP gems, coins, pots, own chests, the merchant.
-- Pooled anchored parts, one shared animation loop, one BulkMoveTo per frame (vault: Collectible
-- Pickup FX). Collected items fly to the nearest character with an accelerating pull aimed at the
-- torso, then pop. Paid chests and the merchant get a local ProximityPrompt -> LootInteract(id);
-- the server re-checks owner, distance and coins.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Loot = require(Config:WaitForChild("Loot"))
local Codec = require(Shared:WaitForChild("LootCodec"))
local Heightmap = require(Shared:WaitForChild("Heightmap"))
local Net = require(Shared:WaitForChild("Net"))

local K = Codec.Kind
local S = Codec.State
local HIDDEN = CFrame.new(0, -10000, 0)
local CULL_DISTANCE = 150
local VISIBLE_CAP = 450
local POP_TIME = 0.15
local FLY_MAX_TIME = 0.8
local localPlayer = Players.LocalPlayer
local isFrench = string.sub(string.lower(localPlayer.LocaleId), 1, 2) == "fr"

type Entry = {
	id: number,
	kind: number,
	paid: boolean,
	part: BasePart,
	x: number,
	z: number,
	y: number,
	phase: number,
	born: number, -- server tick when first seen
	lastFull: number,
	flying: boolean,
	speed: number,
	flyStart: number,
	popAt: number, -- os.clock() when the pop started, 0 if not popping
	prompt: ProximityPrompt?,
}

type KindLook = {
	size: Vector3,
	shape: Enum.PartType,
	color: Color3,
	material: Enum.Material,
	height: number, -- centre height above ground
	spin: boolean,
	bob: number,
	tilt: CFrame,
}

local LootRenderer = {}

local entries: { [number]: Entry } = {}
local pools: { [number]: { BasePart } } = {}
local container: Folder
local visibleCount = 0
local chestCost = 0
local fullTick = -1
local fullChunks = 0
local fullCount = 0
local latestDeltaTick = 0

local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}
local releaseList: { Entry } = {}

local interactRemote: RemoteEvent
local buyRemote: RemoteEvent

local merchantGui: BillboardGui? = nil
local merchantGuiAt = 0

local function text(t: { fr: string, en: string }): string
	return if isFrench then t.fr else t.en
end

local DIAMOND = CFrame.Angles(math.rad(45), 0, math.rad(45))
local UPRIGHT_CYL = CFrame.Angles(0, 0, math.rad(90))
local COIN_EDGE = CFrame.new()

local LOOKS: { [number]: KindLook } = {
	[K.GemSmall] = { size = Vector3.new(0.6, 0.6, 0.6), shape = Enum.PartType.Block, color = Color3.fromRGB(80, 220, 255), material = Enum.Material.Neon, height = 1, spin = true, bob = 0.25, tilt = DIAMOND },
	[K.GemMedium] = { size = Vector3.new(0.8, 0.8, 0.8), shape = Enum.PartType.Block, color = Color3.fromRGB(90, 230, 110), material = Enum.Material.Neon, height = 1.1, spin = true, bob = 0.25, tilt = DIAMOND },
	[K.GemLarge] = { size = Vector3.new(1.1, 1.1, 1.1), shape = Enum.PartType.Block, color = Color3.fromRGB(200, 90, 255), material = Enum.Material.Neon, height = 1.3, spin = true, bob = 0.3, tilt = DIAMOND },
	[K.GemHuge] = { size = Vector3.new(1.5, 1.5, 1.5), shape = Enum.PartType.Block, color = Color3.fromRGB(255, 150, 40), material = Enum.Material.Neon, height = 1.6, spin = true, bob = 0.35, tilt = DIAMOND },
	[K.Coin] = { size = Vector3.new(0.2, 1, 1), shape = Enum.PartType.Cylinder, color = Color3.fromRGB(255, 205, 50), material = Enum.Material.Metal, height = 0.9, spin = true, bob = 0.2, tilt = COIN_EDGE },
	[K.CoinPile] = { size = Vector3.new(0.3, 1.6, 1.6), shape = Enum.PartType.Cylinder, color = Color3.fromRGB(255, 190, 30), material = Enum.Material.Metal, height = 1.2, spin = true, bob = 0.2, tilt = COIN_EDGE },
	[K.Pot] = { size = Vector3.new(2.2, 1.7, 1.7), shape = Enum.PartType.Cylinder, color = Color3.fromRGB(165, 95, 55), material = Enum.Material.Slate, height = 1.1, spin = false, bob = 0, tilt = UPRIGHT_CYL },
	[K.ChestNormal] = { size = Vector3.new(2.6, 1.8, 1.8), shape = Enum.PartType.Block, color = Color3.fromRGB(140, 90, 45), material = Enum.Material.Wood, height = 0.9, spin = false, bob = 0, tilt = CFrame.new() },
	[K.ChestElite] = { size = Vector3.new(2.6, 1.8, 1.8), shape = Enum.PartType.Block, color = Loot.RarityColors.Epic, material = Enum.Material.SmoothPlastic, height = 0.9, spin = false, bob = 0, tilt = CFrame.new() },
	[K.ChestBoss] = { size = Vector3.new(3.2, 2.2, 2.2), shape = Enum.PartType.Block, color = Loot.RarityColors.Legendary, material = Enum.Material.Metal, height = 1.1, spin = false, bob = 0, tilt = CFrame.new() },
	[K.ChestShrine] = { size = Vector3.new(2.6, 1.8, 1.8), shape = Enum.PartType.Block, color = Loot.RarityColors.Rare, material = Enum.Material.SmoothPlastic, height = 0.9, spin = false, bob = 0, tilt = CFrame.new() },
	[K.Merchant] = { size = Vector3.new(3, 5, 3), shape = Enum.PartType.Block, color = Color3.fromRGB(120, 60, 170), material = Enum.Material.SmoothPlastic, height = 2.5, spin = false, bob = 0, tilt = CFrame.new() },
}

local function isPickup(kind: number): boolean
	return kind <= K.CoinPile
end

local function makePart(kind: number): BasePart
	local look = LOOKS[kind]
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Shape = look.shape
	part.Size = look.size
	part.Color = look.color
	part.Material = look.material
	part.CFrame = HIDDEN
	part.Parent = container
	return part
end

local function acquire(kind: number): BasePart
	local pool = pools[kind]
	local part = pool and table.remove(pool)
	return part or makePart(kind)
end

local function releasePart(kind: number, part: BasePart)
	part.CFrame = HIDDEN
	local pool = pools[kind]
	if not pool then
		pool = {}
		pools[kind] = pool
	end
	table.insert(pool, part)
end

local function chestPromptText(): string
	return if isFrench then `Ouvrir ({chestCost} pièces)` else `Open ({chestCost} coins)`
end

local function attachPrompt(e: Entry)
	if e.prompt then
		return
	end
	local isMerchant = e.kind == K.Merchant
	if not isMerchant and not e.paid then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = if isMerchant then 0 else 0.3
	prompt.MaxActivationDistance = if isMerchant then Loot.MerchantRange else Loot.InteractRange
	prompt.ObjectText = if isMerchant then text(Loot.MerchantName) else (if isFrench then "Coffre" else "Chest")
	prompt.ActionText = if isMerchant then (if isFrench then "Marchander" else "Trade") else chestPromptText()
	local id = e.id
	prompt.Triggered:Connect(function()
		interactRemote:FireServer(id)
	end)
	prompt.Parent = e.part
	e.prompt = prompt
end

local function destroyEntry(e: Entry)
	entries[e.id] = nil
	local prompt = e.prompt
	if prompt then
		prompt:Destroy()
		e.prompt = nil
	end
	releasePart(e.kind, e.part)
end

local function upsert(id: number, kind: number, state: number, x: number, z: number, tick: number)
	if not LOOKS[kind] then
		return
	end
	local e = entries[id]
	if e and (e.flying or e.popAt > 0) then
		return -- already leaving
	end
	local paid = bit32.band(state, S.Paid) ~= 0
	if e and (e.kind ~= kind or e.paid ~= paid) then
		destroyEntry(e)
		e = nil
	end
	if not e then
		local newEntry: Entry = {
			id = id,
			kind = kind,
			paid = paid,
			part = acquire(kind),
			x = x,
			z = z,
			y = Heightmap.getY(x, z),
			phase = (id * 0.618) % 1 * math.pi * 2,
			born = tick,
			lastFull = tick,
			flying = false,
			speed = 0,
			flyStart = 0,
			popAt = 0,
			prompt = nil,
		}
		entries[id] = newEntry
		attachPrompt(newEntry)
	else
		if e.x ~= x or e.z ~= z then
			e.x, e.z = x, z
			e.y = Heightmap.getY(x, z)
		end
		e.lastFull = math.max(e.lastFull, tick)
	end
end

local function onRecord(tick: number, isFull: boolean, id: number, x: number, z: number, flags: number)
	local kind, state = Codec.unpackFlags(flags)
	if not isFull and bit32.band(state, S.Collected) ~= 0 then
		local e = entries[id]
		if e and not e.flying and e.popAt == 0 then
			if isPickup(e.kind) then
				e.flying = true
				e.flyStart = os.clock()
				e.speed = 20
			else
				e.popAt = os.clock()
			end
		end
		return
	end
	if not isFull and bit32.band(state, S.Removed) ~= 0 then
		local e = entries[id]
		if e and e.popAt == 0 and not e.flying then
			e.popAt = os.clock()
		end
		return
	end
	upsert(id, kind, state, x, z, tick)
end

local function onSnapshot(payload: unknown)
	if typeof(payload) ~= "buffer" then
		return
	end
	local header = Codec.readHeader(payload)
	if not header then
		return
	end
	local tick = header.tick
	if header.mode == Codec.Mode.Full then
		if tick < fullTick then
			return
		end
		if tick > fullTick then
			fullTick = tick
			fullChunks = 0
			fullCount = header.chunkCount
		end
		fullChunks += 1
		Codec.forEach(payload, header.count, function(id, x, z, flags)
			onRecord(tick, true, id, x, z, flags)
		end)
		if fullChunks >= fullCount then
			-- Complete full set: drop what it no longer contains (lost deltas, out of range).
			for _, e in entries do
				if e.lastFull < tick and e.born < tick and not e.flying and e.popAt == 0 then
					destroyEntry(e)
				end
			end
		end
	else
		latestDeltaTick = math.max(latestDeltaTick, tick)
		Codec.forEach(payload, header.count, function(id, x, z, flags)
			onRecord(tick, false, id, x, z, flags)
		end)
	end
end

local function nearestCharacterTorso(x: number, z: number): Vector3?
	local best: Vector3? = nil
	local bestD2 = math.huge
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local p = root.Position
			local dx, dz = p.X - x, p.Z - z
			local d2 = dx * dx + dz * dz
			if d2 < bestD2 then
				bestD2 = d2
				best = p
			end
		end
	end
	return best
end

local function render(dt: number)
	local now = os.clock()
	local camera = Workspace.CurrentCamera
	local camPos = if camera then camera.CFrame.Position else Vector3.zero
	local cull2 = CULL_DISTANCE * CULL_DISTANCE
	local n = 0
	local nRelease = 0
	for _, e in entries do
		local look = LOOKS[e.kind]
		if e.popAt > 0 then
			local a = (now - e.popAt) / POP_TIME
			if a >= 1 then
				nRelease += 1
				releaseList[nRelease] = e
				continue
			end
			n += 1
			moveParts[n] = e.part
			moveCFrames[n] = CFrame.new(e.x, e.y + look.height + a * 1.5, e.z) * look.tilt
			continue
		end
		if e.flying then
			local target = nearestCharacterTorso(e.x, e.z)
			if not target or now - e.flyStart > FLY_MAX_TIME then
				e.popAt = now
				continue
			end
			local pos = Vector3.new(e.x, e.y + look.height, e.z)
			local offset = target - pos
			local dist = offset.Magnitude
			if dist < 1.5 then
				e.popAt = now
				continue
			end
			e.speed = math.min(e.speed + 120 * dt, 90)
			local stepLen = math.min(e.speed * dt, dist)
			local newPos = pos + offset.Unit * stepLen
			e.x, e.z = newPos.X, newPos.Z
			e.y = newPos.Y - look.height
			n += 1
			moveParts[n] = e.part
			moveCFrames[n] = CFrame.new(newPos) * look.tilt
			continue
		end
		local dx, dz = e.x - camPos.X, e.z - camPos.Z
		if dx * dx + dz * dz > cull2 or n >= VISIBLE_CAP then
			if e.part.CFrame.Y > -5000 then
				n += 1
				moveParts[n] = e.part
				moveCFrames[n] = HIDDEN
			end
			continue
		end
		local y = e.y + look.height + math.sin(now * 2 + e.phase) * look.bob
		local cf = CFrame.new(e.x, y, e.z)
		if look.spin then
			cf *= CFrame.Angles(0, now * 1.6 + e.phase, 0)
		end
		n += 1
		moveParts[n] = e.part
		moveCFrames[n] = cf * look.tilt
	end
	for i = 1, nRelease do
		destroyEntry(releaseList[i])
		releaseList[i] = nil :: any
	end
	for i = n + 1, #moveParts do
		moveParts[i] = nil :: any
		moveCFrames[i] = nil :: any
	end
	if n > 0 then
		Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	visibleCount = n
end

-- Merchant offer (small billboard over the merchant; tap a line to buy) ----------------

local function closeMerchantGui()
	local gui = merchantGui
	if gui then
		gui:Destroy()
		merchantGui = nil
	end
end

local function itemName(itemId: string): string
	local module = Config:FindFirstChild("Items")
	if module and module:IsA("ModuleScript") then
		local ok, items = pcall(require :: any, module)
		if ok and type(items) == "table" then
			local def = items[itemId]
			if type(def) == "table" and type(def.name) == "table" then
				local name = if isFrench then def.name.fr else def.name.en
				if type(name) == "string" then
					return name
				end
			end
		end
	end
	return itemId
end

local function onMerchantOffer(payload: any)
	if type(payload) ~= "table" or type(payload.offers) ~= "table" or type(payload.merchantId) ~= "number" then
		return
	end
	local e = entries[payload.merchantId]
	if not e then
		return
	end
	closeMerchantGui()
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "MerchantOffer"
	gui.Adornee = e.part
	gui.Active = true
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(240, 44 * (#payload.offers + 1))
	gui.StudsOffset = Vector3.new(0, 5, 0)
	gui.ResetOnSpawn = false
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.Parent = gui
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 36)
	title.BackgroundTransparency = 0.3
	title.BackgroundColor3 = Color3.fromRGB(30, 20, 45)
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextScaled = true
	title.Font = Enum.Font.GothamBold
	title.Text = text(Loot.MerchantName)
	title.Parent = gui
	for _, offer in payload.offers do
		if type(offer) ~= "table" or type(offer.slot) ~= "number" then
			continue
		end
		local button = Instance.new("TextButton")
		button.Size = UDim2.new(1, 0, 0, 40)
		button.BackgroundColor3 = Loot.RarityColors[offer.rarity] or Loot.RarityColors.Common
		button.BackgroundTransparency = if offer.sold then 0.7 else 0.1
		button.TextColor3 = Color3.new(1, 1, 1)
		button.TextScaled = true
		button.Font = Enum.Font.GothamBold
		local label = if offer.kind == "Heal"
			then (if isFrench then "Soin" else "Heal")
			else itemName(tostring(offer.itemId))
		button.Text = if offer.sold
			then `{label} — {if isFrench then "vendu" else "sold"}`
			else `{label} — {offer.price}`
		button.AutoButtonColor = not offer.sold
		local slot = offer.slot
		button.Activated:Connect(function()
			if not offer.sold then
				buyRemote:FireServer(slot)
			end
		end)
		button.Parent = gui
	end
	gui.Parent = playerGui
	merchantGui = gui
	merchantGuiAt = os.clock()
end

local function watchMerchantGui()
	local gui = merchantGui
	if not gui then
		return
	end
	local adornee = gui.Adornee
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local far = true
	if adornee and adornee:IsA("BasePart") and root and root:IsA("BasePart") then
		far = (adornee.Position - root.Position).Magnitude > Loot.MerchantRange + 6
	end
	if far or os.clock() - merchantGuiAt > 30 then
		closeMerchantGui()
	end
end

-- Public -----------------------------------------------------------------------

function LootRenderer.getVisibleCount(): number
	return visibleCount
end

function LootRenderer.getChestCost(): number
	return chestCost
end

function LootRenderer.init()
	container = Instance.new("Folder")
	container.Name = "ClientLoot"
	container.Parent = Workspace
end

function LootRenderer.start()
	interactRemote = Net.event("LootInteract")
	buyRemote = Net.event("MerchantBuy")
	Net.unreliable("LootSnapshot").OnClientEvent:Connect(onSnapshot)
	Net.event("Coins").OnClientEvent:Connect(function(payload: any)
		if type(payload) == "table" and type(payload.chestCost) == "number" and payload.chestCost ~= chestCost then
			chestCost = payload.chestCost
			local label = chestPromptText()
			for _, e in entries do
				local prompt = e.prompt
				if prompt and e.paid then
					prompt.ActionText = label
				end
			end
		end
	end)
	Net.event("MerchantOffer").OnClientEvent:Connect(onMerchantOffer)
	RunService.PreRender:Connect(function(dt)
		render(dt)
		watchMerchantGui()
	end)
end

return LootRenderer
