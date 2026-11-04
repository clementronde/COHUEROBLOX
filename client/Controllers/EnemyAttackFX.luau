--!strict
-- Short, pooled client-only attack effects. The server owns all hit checks.
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Motion = require(script.Parent.EnemyMotion)
type Profile = Motion.Profile
type Spark = { part: BasePart, frame: CFrame, velocity: Vector3, size: Vector3, spin: number, ring: boolean }
type Effect = { start: number, life: number, sparks: { Spark } }

local Effects = {}
local active: { Effect } = {}
local pools: { [string]: { BasePart } } = {}
local container: Folder
local rng = Random.new()
local LIMIT = 18

local function take(shape: string, color: Color3): BasePart
	local pool = pools[shape]
	local part = pool and table.remove(pool)
	if not part then
		if shape == "Wedge" then
			part = Instance.new("WedgePart")
		else
			local p = Instance.new("Part")
			if shape == "Ball" then
				p.Shape = Enum.PartType.Ball
			elseif shape == "Cylinder" then
				p.Shape = Enum.PartType.Cylinder
			end
			part = p
		end
		part.Name = shape
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Parent = container
	end
	part.Color = color
	return part
end

local function release(effect: Effect)
	for _, s in effect.sparks do
		local part = s.part
		part.Transparency = 1
		local key = part.Name
		if not pools[key] then
			pools[key] = {}
		end
		table.insert(pools[key], part)
	end
end

function Effects.emit(profile: Profile, origin: Vector3, facing: Vector3, mode: string, radius: number)
	if #active >= LIMIT then
		release(table.remove(active, 1) :: Effect)
	end

	local shoot = mode == "shot"
	local ground = mode == "land" or mode == "boss" or (not shoot and profile.style == "burst")
	local r = math.clamp(radius, .7, if mode == "boss" then 10 else 4)
	local forward = if facing.Magnitude > .01 then facing.Unit else -Vector3.zAxis
	local base = CFrame.lookAt(origin, origin + forward)
	local light = profile.color:Lerp(Color3.new(1, 1, 1), .5)
	local effect: Effect = { start = os.clock(), life = if mode == "boss" then .56 elseif shoot then .30 else .40, sparks = {} }

	local function add(shape: string, color: Color3, frame: CFrame, velocity: Vector3, size: Vector3, spin: number, ring: boolean)
		local part = take(shape, color)
		part.CFrame = frame
		part.Size = size
		part.Transparency = .12
		table.insert(effect.sparks, { part = part, frame = frame, velocity = velocity, size = size, spin = spin, ring = ring })
	end

	if not shoot then
		local count = if ground then 8 else 5
		for i = 1, count do
			local angle = if ground then (i - 1) * 2 * math.pi / count else (i - 3) * .40
			local heading = base * CFrame.Angles(0, angle, 0)
			local start = heading * CFrame.new(0, if ground then .14 else .25, -r * .32)
			local size = Vector3.new(r * (if ground then .43 else .35), math.max(.08, r * .075), r * .14)
			add("Block", if i % 2 == 0 then light else profile.color, start, heading.LookVector * r * 1.18, size, 0, true)
		end
	end

	local count = if mode == "boss" then 9 else 5
	for i = 1, count do
		local angle = if ground then i * math.pi * 2 / count else rng:NextNumber(-.75, .75)
		local heading = base * CFrame.Angles(0, angle, 0)
		local velocity = heading.LookVector * r * rng:NextNumber(.50, 1.20)
			+ Vector3.yAxis * r * rng:NextNumber(.24, if shoot then .55 else .95)
		local size = math.max(.12, r * rng:NextNumber(.12, .23))
		local dims = if profile.debris == "Cylinder" then Vector3.new(size * .28, size * 1.55, size * 1.55)
			else Vector3.new(size, size * (if profile.debris == "Ball" then 1 else .65), size * 1.22)
		add(profile.debris, if i % 3 == 0 then light else profile.color,
			heading * CFrame.new(0, .15, -r * .23), velocity, dims, rng:NextNumber(-3, 3), false)
	end
	table.insert(active, effect)
end

function Effects.init()
	container = Instance.new("Folder")
	container.Name = "ClientEnemyAttackFX"
	container.Parent = Workspace
	RunService.PreRender:Connect(function()
		local now = os.clock()
		for i = #active, 1, -1 do
			local effect = active[i]
			local t = (now - effect.start) / effect.life
			if t >= 1 then
				release(effect)
				table.remove(active, i)
				continue
			end
			for _, s in effect.sparks do
				local travel = if s.ring then t else 1 - (1 - t) ^ 2
				local offset = s.velocity * travel
				if not s.ring then
					offset -= Vector3.yAxis * (t * t * s.velocity.Y * .92)
				end
				s.part.CFrame = (s.frame + offset) * CFrame.Angles(s.spin * t, 0, s.spin * t * .5)
				local scale = if s.ring then 1 + t * 1.4 else 1 - t * .78
				s.part.Size = s.size * scale
				s.part.Transparency = .12 + t * .88
			end
		end
	end)
end

return Effects
