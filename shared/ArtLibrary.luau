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

-- Équipement de classe (A01, docs/dossier/80-direction-artistique.md section 7).
-- Assets/Equipment contient un Accessory par pièce : Handle = MeshPart voxel (couleurs par sommet,
-- Color blanc) avec une Attachment au nom de l'attache R15 visée. Le Handle porte les attributs
-- RefPartName (partie du corps de référence) et RefPartSize (sa taille sur l'avatar R15 par défaut),
-- ce qui permet d'adapter la pièce à l'avatar réel du joueur (Rthro, corps fins...).
-- Les pièces se cumulent : palier 1 = niveau 10, palier 2 = niveau 20, palier 3 = niveau 30.
ArtLibrary.ClassGear = {
	Knight = { { "Knight_Helm" }, { "Knight_Pauldron_R", "Knight_Pauldron_L" }, { "Knight_Cape" } },
	Archer = { { "Archer_Hood" }, { "Archer_Bracer" }, { "Archer_Quiver" } },
	Mage = { { "Mage_Hat" }, { "Mage_Orb" }, { "Mage_Cape" } },
} :: { [string]: { { string } } }

local GEAR_TAG = "COHUE_ClassGear"

local function scaleHandle(handle: BasePart, character: Model)
	local partName = handle:GetAttribute("RefPartName")
	local refSize = handle:GetAttribute("RefPartSize")
	if typeof(partName) ~= "string" or typeof(refSize) ~= "Vector3" then
		return
	end
	local part = character:FindFirstChild(partName)
	if not part or not part:IsA("BasePart") then
		return
	end
	-- Échelle uniforme (les voxels restent des cubes), bornée pour éviter les cas extrêmes.
	local k = math.clamp((part.Size.X / refSize.X + part.Size.Y / refSize.Y + part.Size.Z / refSize.Z) / 3, 0.5, 2)
	if math.abs(k - 1) < 0.02 then
		return
	end
	handle.Size *= k
	for _, d in handle:GetChildren() do
		if d:IsA("Attachment") then
			d.Position *= k
		elseif d:IsA("BasePart") then -- cœur Neon de l'orbe : Weld (Part0 = Handle) porté par la pièce
			d.Size *= k
			local weld = d:FindFirstChildOfClass("Weld")
			if weld then
				weld.C0 = CFrame.new(weld.C0.Position * k) * weld.C0.Rotation
			end
		end
	end
end

-- Ajoute une pièce à un personnage (serveur ou client). Retourne l'Accessory, ou nil si la pièce ou
-- le Humanoid manque. Ne yield pas.
function ArtLibrary.equipAccessory(character: Model, name: string): Accessory?
	local template = ArtLibrary.find(name)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not template or not template:IsA("Accessory") or not humanoid then
		return nil
	end
	local acc = template:Clone()
	local handle = acc:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		scaleHandle(handle, character)
		handle.Anchored = false
		handle.Massless = true
		handle.CanCollide = false
		handle.CanQuery = false
		handle.CanTouch = false
	end
	acc:SetAttribute(GEAR_TAG, true)
	humanoid:AddAccessory(acc)
	return acc
end

-- Met l'équipement d'une classe au palier voulu (0 à 3) : retire l'ancien, pose les pièces cumulées.
function ArtLibrary.equipClassTier(character: Model, classId: string, tier: number): number
	ArtLibrary.clearClassGear(character)
	local gear = ArtLibrary.ClassGear[classId]
	if not gear then
		return 0
	end
	local count = 0
	for t = 1, math.clamp(tier, 0, #gear) do
		for _, name in gear[t] do
			if ArtLibrary.equipAccessory(character, name) then
				count += 1
			end
		end
	end
	return count
end

function ArtLibrary.clearClassGear(character: Model)
	for _, d in character:GetChildren() do
		if d:IsA("Accessory") and d:GetAttribute(GEAR_TAG) then
			d:Destroy()
		end
	end
end

-- Marqueur de capture (variante capturable) : anneau au sol + cage flottante, Neon Bubblegum.
-- Retourne les pièces et leurs décalages depuis le pied de l'ennemi (comme cloneParts), prêts pour
-- BulkMoveTo. `height` = hauteur dessinée de l'ennemi (la cage flotte 1,6 stud au-dessus).
local CAPTURE_PINK = Color3.fromRGB(255, 95, 176)

function ArtLibrary.cloneCaptureMarker(height: number, radius: number?): ({ BasePart }?, { CFrame }?)
	local ring = ArtLibrary.clonePart("FX_CaptureRing")
	local icon = ArtLibrary.clonePart("FX_CaptureIcon")
	if not ring or not icon then
		return nil, nil
	end
	if radius and radius > 0 then
		ring.Size *= (radius * 2) / ring.Size.X
	end
	for _, p in { ring, icon } do
		p.Material = Enum.Material.Neon
		p.Color = CAPTURE_PINK
	end
	return { ring, icon }, {
		CFrame.new(0, ring.Size.Y / 2 + 0.02, 0),
		CFrame.new(0, height + 1.6 + icon.Size.Y / 2, 0),
	}
end

return ArtLibrary
