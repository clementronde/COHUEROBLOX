--!strict
-- Art templates (lead). ReplicatedStorage.Assets holds ready-made meshes:
--   Assets/Creatures  enemies, bosses, companions generated in Studio (ids in assets/creatures.csv)
--   Assets/Pack       models imported from the LihFolk Asset Pack (assets/pack-manifest.csv)
-- Renderers ask for a template by name and fall back to their procedural parts when it is
-- missing, so the game always runs (Studio test place, live place, or no assets at all).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArtLibrary = {}

local cache: { [string]: Instance | false } = {}

local function root(): Instance?
	return ReplicatedStorage:FindFirstChild("Assets")
end

-- Template by exact name (searched once, then cached). Never returns the template itself to
-- callers that intend to modify it: use clonePart / cloneModel.
function ArtLibrary.find(name: string): Instance?
	local hit = cache[name]
	if hit ~= nil then
		return if hit then hit else nil
	end
	local assets = root()
	local found = if assets then assets:FindFirstChild(name, true) else nil
	cache[name] = found or false
	return found
end

function ArtLibrary.has(name: string): boolean
	return ArtLibrary.find(name) ~= nil
end

local function prep(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

-- Single-mesh clone scaled uniformly so its height equals `height` (studs).
-- Returns the part and its size after scaling, or nil if the template is missing or not a part.
function ArtLibrary.clonePart(name: string, height: number?): (BasePart?, Vector3?)
	local template = ArtLibrary.find(name)
	local source: BasePart? = nil
	if template and template:IsA("BasePart") then
		source = template
	elseif template and template:IsA("Model") then
		source = template:FindFirstChildWhichIsA("BasePart", true)
	end
	if not source then
		return nil, nil
	end
	local part = source:Clone()
	part:ClearAllChildren()
	prep(part)
	if height and height > 0 and part.Size.Y > 0 then
		part.Size = part.Size * (height / part.Size.Y)
	end
	return part, part.Size
end

-- Multi-part model clone (pack imports), scaled so its height equals `height`.
-- Returns the parts and their offsets from the model's bottom centre, ready for BulkMoveTo.
function ArtLibrary.cloneParts(name: string, height: number?): ({ BasePart }?, { CFrame }?, number?)
	local template = ArtLibrary.find(name)
	if not template then
		return nil, nil, nil
	end
	if template:IsA("BasePart") then
		local part, size = ArtLibrary.clonePart(name, height)
		if not part or not size then
			return nil, nil, nil
		end
		return { part }, { CFrame.new(0, size.Y / 2, 0) }, size.Y
	end
	if not template:IsA("Model") then
		return nil, nil, nil
	end
	local model = template:Clone()
	local cf, size = model:GetBoundingBox()
	local scale = if height and height > 0 and size.Y > 0 then height / size.Y else 1
	if scale ~= 1 then
		model:ScaleTo(model:GetScale() * scale)
		cf, size = model:GetBoundingBox()
	end
	local bottom = CFrame.new(cf.Position - Vector3.new(0, size.Y / 2, 0))
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			prep(d)
			table.insert(parts, d)
			table.insert(offsets, bottom:ToObjectSpace(d.CFrame))
		end
	end
	for _, p in parts do
		p.Parent = nil
	end
	model:Destroy()
	return parts, offsets, size.Y
end

return ArtLibrary
