--!strict
-- Traversal (A06-07, domaine avatar) : objets de verticalité posés par le level design — tremplins, geysers,
-- tyroliennes. Relevé et géométrie partagés par le client (TraversalController, qui applique le lancer) et le
-- serveur (TraversalGuard, qui exempte MovementGuard). Fiche pour A02 : docs/dossier/50-classes-avatar-mouvement.md §11.
--
-- Rien n'est construit ici (01-decisions-v2 §12) : on lit des objets existants.
--   Tremplin : BasePart (ou Model avec PrimaryPart) tagué CohueLaunchPad, ou enfant de Workspace.CohueTraversal.LaunchPads.
--   Geyser   : idem, tag CohueGeyser, dossier Geysers.
--   Tyrolienne : Model / Folder tagué CohueZipline (ou enfant de Ziplines) avec deux enfants Start et End
--                (BasePart ou Attachment).
-- Seules les instances vues par le serveur comptent pour l'exemption : un objet ajouté par un client n'exempte rien.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Movement = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Movement"))
local T = Movement.Traversal

export type Pad = { inst: Instance, top: Vector3, radius: number, height: number, forward: Vector3 }
export type Geyser = { inst: Instance, top: Vector3, radius: number, height: number, period: number, active: number, offset: number }
export type Zipline = { inst: Instance, a: Vector3, b: Vector3, dir: Vector3, length: number, speed: number }
export type Set = { pads: { Pad }, geysers: { Geyser }, ziplines: { Zipline } }

local Traversal = {}

local cache: Set = { pads = {}, geysers = {}, ziplines = {} }
local scannedAt = -math.huge

local function num(inst: Instance, name: string, default: number, lo: number, hi: number): number
	local v = inst:GetAttribute(name)
	if type(v) ~= "number" or v ~= v then
		return default
	end
	return math.clamp(v, lo, hi)
end

local function basePart(inst: Instance): BasePart?
	if inst:IsA("BasePart") then
		return inst
	elseif inst:IsA("Model") then
		return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")
	end
	return nil
end

-- Dessus de la pièce (centre) et rayon horizontal de la zone de déclenchement.
local function zoneOf(part: BasePart, inst: Instance): (Vector3, number)
	local cf, size = part.CFrame, part.Size
	-- Hauteur projetée sur l'axe vertical du monde (pièce posée à plat, éventuellement tournée en Y).
	local halfY = (math.abs(cf.RightVector.Y) * size.X + math.abs(cf.UpVector.Y) * size.Y + math.abs(cf.LookVector.Y) * size.Z) / 2
	local radius = num(inst, "Radius", math.max(size.X, size.Z) / 2, 1, 30)
	return cf.Position + Vector3.new(0, halfY, 0), radius
end

local function pointOf(inst: Instance?): Vector3?
	if not inst then
		return nil
	elseif inst:IsA("Attachment") then
		return inst.WorldPosition
	elseif inst:IsA("BasePart") then
		return inst.Position
	end
	return nil
end

local function collect(tag: string, folderName: string): { Instance }
	local list: { Instance } = {}
	local seen: { [Instance]: boolean } = {}
	for _, inst in CollectionService:GetTagged(tag) do
		if inst:IsDescendantOf(Workspace) and not seen[inst] then
			seen[inst] = true
			table.insert(list, inst)
		end
	end
	local root = Workspace:FindFirstChild(T.Folder)
	local folder = root and root:FindFirstChild(folderName)
	if folder then
		for _, inst in folder:GetChildren() do
			if not seen[inst] then
				seen[inst] = true
				table.insert(list, inst)
			end
		end
	end
	return list
end

local function rescan()
	local set: Set = { pads = {}, geysers = {}, ziplines = {} }
	for _, inst in collect(T.PadTag, "LaunchPads") do
		local part = basePart(inst)
		if part then
			local top, radius = zoneOf(part, inst)
			local look = part.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			local speed = num(inst, "LaunchForward", T.PadForward, 0, T.PadMaxForward)
			table.insert(set.pads, {
				inst = inst,
				top = top,
				radius = radius,
				height = num(inst, "LaunchHeight", T.PadHeight, T.ZoneHeight + 3, T.PadMaxHeight), -- assez pour sortir de la zone
				forward = if flat.Magnitude > 1e-3 and speed > 0 then flat.Unit * speed else Vector3.zero,
			})
		end
	end
	for _, inst in collect(T.GeyserTag, "Geysers") do
		local part = basePart(inst)
		if part then
			local top, radius = zoneOf(part, inst)
			local period = num(inst, "Period", T.GeyserPeriod, T.GeyserMinPeriod, 120)
			table.insert(set.geysers, {
				inst = inst,
				top = top,
				radius = radius,
				height = num(inst, "Height", T.GeyserHeight, 2, T.GeyserMaxHeight),
				period = period,
				active = num(inst, "Active", T.GeyserActive, 0.2, period - 0.2),
				offset = num(inst, "Offset", 0, -1e6, 1e6),
			})
		end
	end
	for _, inst in collect(T.ZiplineTag, "Ziplines") do
		local a, b = pointOf(inst:FindFirstChild("Start", true)), pointOf(inst:FindFirstChild("End", true))
		if a and b and (b - a).Magnitude > 4 then
			table.insert(set.ziplines, {
				inst = inst,
				a = a,
				b = b,
				dir = (b - a).Unit,
				length = (b - a).Magnitude,
				speed = num(inst, "Speed", T.ZiplineSpeed, 4, T.ZiplineMaxSpeed),
			})
		end
	end
	cache = set
end

-- Objets de verticalité du monde courant (relevés au plus toutes les RescanEvery secondes).
function Traversal.get(): Set
	local now = os.clock()
	if now - scannedAt >= T.RescanEvery then
		scannedAt = now
		rescan()
	end
	return cache
end

-- Le HumanoidRootPart est-il dans la zone de déclenchement (cylindre au-dessus du dessus de l'objet) ?
function Traversal.inZone(pos: Vector3, top: Vector3, radius: number, extraRadius: number, extraHeight: number): boolean
	local dy = pos.Y - top.Y
	if dy < -T.ZoneBelow - extraHeight * 0.5 or dy > T.ZoneHeight + extraHeight then
		return false
	end
	local dx, dz = pos.X - top.X, pos.Z - top.Z
	local r = radius + extraRadius
	return dx * dx + dz * dz <= r * r
end

-- Éruption en cours (temps serveur partagé), son numéro, et le temps écoulé depuis son début.
function Traversal.eruption(g: Geyser, serverNow: number): (boolean, number, number)
	local t = serverNow + g.offset
	local index = math.floor(t / g.period)
	local phase = t - index * g.period
	return phase < g.active, index, phase
end

-- Point du câble le plus proche (paramètre 0..1) et distance au câble.
function Traversal.project(z: Zipline, pos: Vector3): (number, number)
	local t = math.clamp((pos - z.a):Dot(z.dir) / z.length, 0, 1)
	return t, (z.a + (z.b - z.a) * t - pos).Magnitude
end

-- Durée d'un lancer à cette hauteur (montée + descente au même niveau), sans marge.
function Traversal.flightTime(height: number, gravity: number): number
	local g = math.max(gravity, 1)
	return 2 * math.sqrt(2 * height / g)
end

return Traversal
