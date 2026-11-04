--!strict
-- Robux purchases (data domain). Cosmetic only: no random items, no revives, no classes, no power,
-- no eggs, no currency. Design: docs/dossier/70-donnees-progression-monetisation.md section 9.
-- Vault: "Developer Products and ProcessReceipt", "Game Passes", "Pricing and Store Design".
--
-- * The ONLY ProcessReceipt assignment in the codebase.
-- * PurchaseId marker stored in the SAME profile as the grant; grant -> saveNow -> PurchaseGranted.
-- * NotProcessedYet when: product unknown, player absent, profile not mutable, save failed.
-- * Passes: server cache per player, checked on join with retries; unknown is never stored as false.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Products = require(Config:WaitForChild("Products"))
local Cosmetics = require(Config:WaitForChild("Cosmetics"))
local Progression = require(Config:WaitForChild("Progression"))
local Net = require(Shared:WaitForChild("Net"))
local Registry = require(Shared:WaitForChild("Registry"))

local MonetizationService = {}

local productKeyById: { [number]: string } = {}
local passKeyById: { [number]: string } = {}
for key, def in Products.Products do
	assert(type(def.cosmetics) == "table" and #def.cosmetics > 0, `[Monetization] product {key} grants nothing`)
	for _, id in def.cosmetics do
		assert(Cosmetics[id] ~= nil, `[Monetization] product {key}: unknown cosmetic {id}`)
	end
	if def.id ~= 0 then
		assert(productKeyById[def.id] == nil, `[Monetization] product id {def.id} used twice`)
		productKeyById[def.id] = key
	end
end
for key, def in Products.Passes do
	for _, id in def.cosmetics do
		assert(Cosmetics[id] ~= nil, `[Monetization] pass {key}: unknown cosmetic {id}`)
	end
	if def.id ~= 0 then
		passKeyById[def.id] = key
	end
end

local function dataService(): any
	return Registry.get("DataService")
end

---------------------------------------------------------------------------------------------------
-- Game passes
---------------------------------------------------------------------------------------------------
local owned: { [Player]: { [string]: boolean } } = {}

local function markDirty(player: Player)
	local progression = Registry.find("ProgressionService")
	if progression and type(progression.markDirty) == "function" then
		progression.markDirty(player)
	end
end

local function setOwned(player: Player, key: string, value: boolean)
	local t = owned[player]
	if not t or t[key] == value then
		return
	end
	t[key] = value
	markDirty(player)
end

local function ownsWithRetry(userId: number, passId: number): boolean?
	for attempt = 1, Products.PassCheckAttempts do
		local ok, result = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(userId, passId)
		end)
		if ok then
			return result == true
		end
		task.wait(attempt)
	end
	return nil -- unknown: never stored as false
end

local function checkPass(player: Player, key: string, passId: number)
	local result = ownsWithRetry(player.UserId, passId)
	if result == nil then
		warn(`[Monetization] pass ownership unknown for {key}, rechecking in {Products.PassRecheckSeconds} s`)
		task.delay(Products.PassRecheckSeconds, function()
			if player.Parent and owned[player] and not owned[player][key] then
				local again = ownsWithRetry(player.UserId, passId)
				if again then
					setOwned(player, key, true)
				end
			end
		end)
	elseif player.Parent and owned[player] then
		setOwned(player, key, result)
	end
end

local function loadPasses(player: Player)
	owned[player] = owned[player] or {}
	for key, def in Products.Passes do
		if def.id ~= 0 then
			task.spawn(checkPass, player, key, def.id)
		end
	end
end

function MonetizationService.ownsPass(player: Player, key: string): boolean
	local t = owned[player]
	return t ~= nil and t[key] == true
end

function MonetizationService.isVip(player: Player): boolean
	return MonetizationService.ownsPass(player, "VIP")
end

---------------------------------------------------------------------------------------------------
-- Developer products: ProcessReceipt
---------------------------------------------------------------------------------------------------
local inFlight: { [string]: boolean } = {}

local function ownsAll(data: { [string]: any }, def: Products.ProductDef): boolean
	for _, id in def.cosmetics do
		if not data.cosmetics[id] then
			return false
		end
	end
	return true
end

local function trimReceipts(data: { [string]: any })
	local maxReceipts = Progression.Data.MaxReceipts
	while #data.receiptOrder > maxReceipts do
		local oldest = table.remove(data.receiptOrder, 1)
		if oldest then
			data.receipts[oldest] = nil
		end
	end
	while #data.purchaseLog > Progression.Data.MaxPurchaseLog do
		table.remove(data.purchaseLog, 1)
	end
end

local function processReceipt(receiptInfo: { [string]: any }): Enum.ProductPurchaseDecision
	local purchaseId = tostring(receiptInfo.PurchaseId)
	local productId = tonumber(receiptInfo.ProductId) or 0
	local key = productKeyById[productId]
	if not key then
		warn(`[Monetization] unknown product {productId} ({purchaseId}): kept pending`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local player = Players:GetPlayerByUserId(tonumber(receiptInfo.PlayerId) or 0)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- redelivered when they rejoin
	end
	if inFlight[purchaseId] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	inFlight[purchaseId] = true

	local decision = Enum.ProductPurchaseDecision.NotProcessedYet
	local granted = false
	local ok, err = pcall(function()
		local ds = dataService()
		ds.waitForProfile(player, Products.ProfileWaitSeconds)
		if not ds.canMutate(player) then
			return -- not loaded, released for teleport, or lost
		end
		local data = ds.peek(player)
		if not data then
			return
		end
		if data.receipts[purchaseId] then
			-- Granted earlier on this profile; make sure it is saved before acknowledging.
			if ds.saveNow(player) then
				decision = Enum.ProductPurchaseDecision.PurchaseGranted
			end
			return
		end
		local def = Products.Products[key]
		local spent = tonumber(receiptInfo.CurrencySpent) or 0
		-- Grant + marker + log in the same document, with no yield in between.
		local mutated = ds.mutate(player, function(d)
			for _, id in def.cosmetics do
				d.cosmetics[id] = true
			end
			d.receipts[purchaseId] = os.time()
			table.insert(d.receiptOrder, purchaseId)
			table.insert(d.purchaseLog, { k = key, r = spent, t = os.time() })
			trimReceipts(d)
		end)
		if not mutated then
			return
		end
		granted = true
		-- Acknowledge only after a successful save. On failure the marker stays in memory and the
		-- retry finds it and saves again.
		if ds.saveNow(player) then
			decision = Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end)
	inFlight[purchaseId] = nil
	if not ok then
		warn(`[Monetization] receipt {purchaseId} error: {err}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if granted then
		markDirty(player)
	end
	if decision == Enum.ProductPurchaseDecision.PurchaseGranted and granted then
		local spent = tonumber(receiptInfo.CurrencySpent) or 0
		local progression = Registry.find("ProgressionService")
		if progression and type(progression.logCustom) == "function" then
			pcall(progression.logCustom, player, "Purchase", spent, { key })
		end
	end
	return decision
end

---------------------------------------------------------------------------------------------------
-- Prompt requests (validated server-side; one-per-player rules enforced HERE, not at receipt time)
---------------------------------------------------------------------------------------------------
local function onRequestPurchase(player: Player, productKey: any)
	if type(productKey) ~= "string" or #productKey > 40 then
		return
	end
	local ds = dataService()
	if not ds.canMutate(player) then
		return -- never prompt into a profile that cannot be saved
	end
	local product = Products.Products[productKey]
	if product then
		local data = ds.peek(player)
		if product.id == 0 or not data or ownsAll(data, product) then
			return
		end
		pcall(function()
			MarketplaceService:PromptProductPurchase(player, product.id)
		end)
		return
	end
	local pass = Products.Passes[productKey]
	if pass then
		if pass.id == 0 or MonetizationService.ownsPass(player, productKey) then
			return
		end
		pcall(function()
			MarketplaceService:PromptGamePassPurchase(player, pass.id)
		end)
	end
end

function MonetizationService.init()
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, wasPurchased: boolean)
		local key = passKeyById[passId]
		if key and wasPurchased and owned[player] then
			setOwned(player, key, true)
			local progression = Registry.find("ProgressionService")
			if progression and type(progression.logCustom) == "function" then
				pcall(progression.logCustom, player, "PassPurchase", 1, { key })
			end
		end
	end)
	Net.onServerEvent("RequestPurchase", 1, onRequestPurchase)
	Players.PlayerAdded:Connect(loadPasses)
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
	end)
end

function MonetizationService.start()
	for _, p in Players:GetPlayers() do
		if not owned[p] then
			task.spawn(loadPasses, p)
		end
	end
end

return MonetizationService
