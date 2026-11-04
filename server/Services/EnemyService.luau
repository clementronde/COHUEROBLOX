--!strict
-- Enemies as data, not Humanoids (doc 12.2).
-- Struct-of-arrays, dense indices 1..count, swap-remove on death.
-- 15 Hz: steer toward nearest player + separation through a spatial grid, then send each
-- client only the enemies around it, in chunks of <= 900 bytes over an UnreliableRemoteEvent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Balance = require(Config:WaitForChild("Balance"))
local Enemies = require(Config:WaitForChild("Enemies"))
local Codec = require(Shared:WaitForChild("EnemyCodec"))
local Net = require(Shared:WaitForChild("Net"))
local Bus = require(script.Parent.Parent:WaitForChild("Bus"))

local DT = 1 / Balance.SimHz
local CELL = Balance.GridCellSize
local MAX_ID = 65535

type Target = { player: Player, root: BasePart, x: number, z: number }

local EnemyService = {}

-- Enemy state (parallel arrays)
local count = 0
local ids: { number } = {}
local xs: { number } = {}
local zs: { number } = {}
local hps: { number } = {}
local kinds: { number } = {}
local states: { number } = {}
local targetOf: { [number]: Player } = {} -- index -> player being chased
local indexOf: { [number]: number } = {} -- id -> index

local nextId = 1
local simTick = 0
local runStart = 0
local grid: { [number]: { number } } = {}
local snapshot: UnreliableRemoteEvent

-- Reused send buffers
local sendIds: { number } = {}
local sendXs: { number } = {}
local sendZs: { number } = {}
local sendFlags: { number } = {}

-- Ids increase and wrap at 65535, so a dead enemy's id is not reused for a long time.
local function allocId(): number?
	for _ = 1, MAX_ID do
		local id = nextId
		nextId = nextId % MAX_ID + 1
		if indexOf[id] == nil then
			return id
		end
	end
	return nil
end

local function cellKey(cx: number, cz: number): number
	return (cx + 32768) * 65536 + (cz + 32768)
end

local function spawnEnemy(kind: number, x: number, z: number, hpMult: number)
	if count >= Balance.MaxEnemies then
		return
	end
	local def = Enemies[kind]
	if not def then
		return
	end
	local id = allocId()
	if not id then
		return
	end
	count += 1
	ids[count] = id
	xs[count] = x
	zs[count] = z
	hps[count] = def.hp * hpMult
	kinds[count] = kind
	states[count] = 0
	targetOf[count] = nil
	indexOf[id] = count
end

local function removeAt(i: number)
	indexOf[ids[i]] = nil
	if i ~= count then
		ids[i] = ids[count]
		xs[i] = xs[count]
		zs[i] = zs[count]
		hps[i] = hps[count]
		kinds[i] = kinds[count]
		states[i] = states[count]
		targetOf[i] = targetOf[count]
		indexOf[ids[i]] = i
	end
	ids[count] = nil :: any
	xs[count] = nil :: any
	zs[count] = nil :: any
	hps[count] = nil :: any
	kinds[count] = nil :: any
	states[count] = nil :: any
	targetOf[count] = nil
	count -= 1
end

local function gatherTargets(): { Target }
	local list: { Target } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local p = root.Position
			table.insert(list, { player = player, root = root, x = p.X, z = p.Z })
		end
	end
	return list
end

local function nearest(targets: { Target }, x: number, z: number): Target?
	local best: Target? = nil
	local bestD2 = math.huge
	for _, t in targets do
		local dx, dz = t.x - x, t.z - z
		local d2 = dx * dx + dz * dz
		if d2 < bestD2 then
			bestD2 = d2
			best = t
		end
	end
	return best
end

local function ringPoint(t: Target): (number, number)
	local angle = math.random() * math.pi * 2
	local r = Balance.SpawnRingMin + math.random() * (Balance.SpawnRingMax - Balance.SpawnRingMin)
	return t.x + math.cos(angle) * r, t.z + math.sin(angle) * r
end

local function desiredAlive(elapsed: number, nPlayers: number): number
	local forced = Balance.Debug.ForceAlive
	if forced then
		return math.min(forced, Balance.MaxEnemies)
	end
	local curve = Balance.DensityCurve
	local base = curve[#curve][2]
	for k = 1, #curve - 1 do
		local a, b = curve[k], curve[k + 1]
		if elapsed <= b[1] then
			local u = (elapsed - a[1]) / (b[1] - a[1])
			base = a[2] + (b[2] - a[2]) * math.clamp(u, 0, 1)
			break
		end
	end
	local scaled = base * (1 + Balance.DensityPerExtraPlayer * (nPlayers - 1))
	return math.min(math.floor(scaled), Balance.MaxEnemies)
end

local function rebuildGrid()
	table.clear(grid)
	for i = 1, count do
		local key = cellKey(xs[i] // CELL, zs[i] // CELL)
		local cell = grid[key]
		if cell then
			table.insert(cell, i)
		else
			grid[key] = { i }
		end
	end
end

-- Hard non-overlap constraint (position-based): every overlapping pair is pushed apart by half
-- the overlap each, then enemies are pushed out of the player they chase. A soft "steering"
-- push loses against the walk of the outer ring and the crowd collapses into one pile.
-- Neighbour range is r_i + r_j + gap, well under one 8-stud grid cell.
local function relax(byPlayer: { [Player]: Target })
	for _ = 1, Balance.RelaxIterations do
		for i = 1, count do
			local ri = Enemies[kinds[i]].radius + Balance.SeparationGap
			local cx, cz = xs[i] // CELL, zs[i] // CELL
			for ox = -1, 1 do
				for oz = -1, 1 do
					local cell = grid[cellKey(cx + ox, cz + oz)]
					if cell then
						for _, j in cell do
							if j > i then
								local minD = ri + Enemies[kinds[j]].radius
								local dx, dz = xs[j] - xs[i], zs[j] - zs[i]
								local d2 = dx * dx + dz * dz
								if d2 < minD * minD then
									local d = math.sqrt(d2)
									if d < 1e-3 then
										-- Exactly stacked: split them in a direction derived from the id.
										local a = ids[i] * 2.39996
										dx, dz, d = math.cos(a), math.sin(a), 1
									end
									local corr = (minD - d) * 0.5 / d
									xs[i] -= dx * corr
									zs[i] -= dz * corr
									xs[j] += dx * corr
									zs[j] += dz * corr
								end
							end
						end
					end
				end
			end
		end
	end

	-- The player is a solid circle: enemies stay outside it.
	for i = 1, count do
		local chased = targetOf[i]
		local t = chased and byPlayer[chased]
		if t then
			local minD = Balance.ContactDistance + Enemies[kinds[i]].radius
			local dx, dz = xs[i] - t.x, zs[i] - t.z
			local d2 = dx * dx + dz * dz
			if d2 < minD * minD then
				local d = math.sqrt(d2)
				if d < 1e-3 then
					local a = ids[i] * 2.39996
					dx, dz, d = math.cos(a), math.sin(a), 1
				end
				xs[i] = t.x + dx / d * minD
				zs[i] = t.z + dz / d * minD
			end
		end
	end
end

local function step(targets: { Target })
	local nPlayers = #targets
	if nPlayers == 0 then
		return
	end

	-- Spawning
	local toSpawn = math.min(desiredAlive(os.clock() - runStart, nPlayers) - count, Balance.MaxSpawnsPerTick)
	local hpMult = 1 + Balance.HpPerExtraPlayer * (nPlayers - 1)
	for _ = 1, toSpawn do
		local x, z = ringPoint(targets[math.random(nPlayers)])
		local kind = if math.random() < Balance.SwarmShare then 1 else 2
		spawnEnemy(kind, x, z, hpMult)
	end

	-- Movement (no removals inside this loop: indices must stay valid for the grid)
	rebuildGrid()
	local byPlayer: { [Player]: Target } = {}
	for _, t in targets do
		byPlayer[t.player] = t
	end
	local recycle2 = Balance.RecycleDistance * Balance.RecycleDistance

	for i = 1, count do
		local x, z = xs[i], zs[i]
		local chased = targetOf[i]
		local t = chased and byPlayer[chased]
		if not t or (i + simTick) % Balance.TargetRefreshTicks == 0 then
			t = nearest(targets, x, z)
			targetOf[i] = if t then t.player else nil
		end
		if not t then
			continue
		end

		local dx, dz = t.x - x, t.z - z
		local d2 = dx * dx + dz * dz
		if d2 > recycle2 then
			-- Too far behind: put it back in play near its target instead of deleting it.
			xs[i], zs[i] = ringPoint(t)
			continue
		end

		local def = Enemies[kinds[i]]
		-- Walk toward the player, but stop at contact instead of walking into their centre.
		local seekX, seekZ = 0, 0
		local stop = Balance.ContactDistance + def.radius
		if d2 > stop * stop then
			local d = math.sqrt(d2)
			seekX, seekZ = dx / d, dz / d
		end
		xs[i] = x + seekX * def.speed * DT
		zs[i] = z + seekZ * def.speed * DT
	end

	relax(byPlayer)
end

local function send(targets: { Target })
	local near2 = Balance.InterestRadiusNear ^ 2
	local far2 = Balance.InterestRadiusFar ^ 2
	local farTick = simTick % Balance.FarSendEveryNTicks == 0
	for _, t in targets do
		local n = 0
		for i = 1, count do
			local dx, dz = xs[i] - t.x, zs[i] - t.z
			local d2 = dx * dx + dz * dz
			if d2 <= near2 or (farTick and d2 <= far2) then
				n += 1
				sendIds[n] = ids[i]
				sendXs[n] = xs[i]
				sendZs[n] = zs[i]
				sendFlags[n] = Codec.packFlags(kinds[i], states[i])
			end
		end
		for _, chunk in Codec.encode(simTick, sendIds, sendXs, sendZs, sendFlags, n) do
			snapshot:FireClient(t.player, chunk)
		end
	end
end

-- Public API ------------------------------------------------------------------

-- Applies damage on the server. Returns true if the enemy died (fires Bus.EnemyKilled).
-- state bit 1 (value 1) = elite; the run domain owns the meaning of the other state bits.
function EnemyService.damage(id: number, amount: number, source: Player?): boolean
	local i = indexOf[id]
	if not i then
		return false
	end
	hps[i] -= amount
	if hps[i] <= 0 then
		local kind, x, z = kinds[i], xs[i], zs[i]
		local isElite = bit32.band(states[i], 1) ~= 0
		removeAt(i)
		Bus.EnemyKilled:fire(id, kind, x, z, source, isElite)
		return true
	end
	return false
end

-- Current position of a live enemy, or nil.
function EnemyService.getPosition(id: number): (number?, number?)
	local i = indexOf[id]
	if not i then
		return nil, nil
	end
	return xs[i], zs[i]
end

function EnemyService.isAlive(id: number): boolean
	return indexOf[id] ~= nil
end

-- Ids of enemies within radius. Uses the grid from the last tick, then re-checks the real
-- position, so results are always correct but may miss an enemy that died and was swapped.
function EnemyService.queryRadius(x: number, z: number, radius: number, out: { number }): number
	local n = 0
	local r2 = radius * radius
	local cells = math.ceil(radius / CELL)
	local cx, cz = x // CELL, z // CELL
	for ox = -cells, cells do
		for oz = -cells, cells do
			local cell = grid[cellKey(cx + ox, cz + oz)]
			if cell then
				for _, i in cell do
					if i <= count then
						local dx, dz = xs[i] - x, zs[i] - z
						if dx * dx + dz * dz <= r2 then
							n += 1
							out[n] = ids[i]
						end
					end
				end
			end
		end
	end
	return n
end

function EnemyService.getCount(): number
	return count
end

function EnemyService.init()
	snapshot = Net.unreliable("EnemySnapshot")
end

function EnemyService.start()
	runStart = os.clock()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < DT then
			return
		end
		acc = math.min(acc - DT, DT) -- never run more than one catch-up tick
		simTick += 1
		local targets = gatherTargets()
		step(targets)
		send(targets)
	end)
end

return EnemyService
