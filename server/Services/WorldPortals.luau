--!strict
-- Portails entre mondes et transition (docs/dossier/21-tuiles-assemblage.md section 7, A02-08).
-- Module simple (pas un service démarré) : StageService l'appelle pour poser les portails,
-- RunManager pour la transition. Les portails sont des gabarits de Clément, clonés ici :
--   Assets.Worlds.<WorldId>.<nom>  (version propre au monde, prioritaire)
--   Assets.Props.<nom>             (version commune)
-- avec <nom> = Tiles.PortalTemplates.NextWorld / CashOut. Un gabarit manquant est signalé.
-- Transition : attributs de Workspace lus par client/Controllers/WorldTransition (fondu au noir).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Tiles = require(Config:WaitForChild("Tiles"))

export type Kind = "NextWorld" | "CashOut"

local WorldPortals = {}

local ATTR = "CohueTransition"
local ATTR_WORLD = "CohueTransitionWorld"
local ATTR_END = "CohueTransitionEnd"

local current: { [string]: Model } = {}
local transitionToken = 0
local warned: { [string]: boolean } = {}

local function findTemplate(kind: Kind, worldId: string?): Model?
	local name = Tiles.PortalTemplates[kind]
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end
	if worldId then
		local worlds = assets:FindFirstChild("Worlds")
		local folder = worlds and worlds:FindFirstChild(worldId)
		local own = folder and folder:FindFirstChild(name)
		if own and own:IsA("Model") then
			return own
		end
	end
	local props = assets:FindFirstChild("Props")
	local common = props and props:FindFirstChild(name)
	if common and common:IsA("Model") then
		return common
	end
	return nil
end

function WorldPortals.hasTemplate(kind: Kind, worldId: string?): boolean
	return findTemplate(kind, worldId) ~= nil
end

-- Clone le gabarit au sol en `position`, tourné (−Z) vers `facing`. Écrit `title` dans les
-- TextLabel nommés Title. Renvoie nil (et le signale une fois) si le gabarit manque.
function WorldPortals.show(kind: Kind, position: Vector3, parent: Instance, worldId: string?, title: string?, facing: Vector3?): Model?
	local existing = current[kind]
	if existing and existing.Parent then
		return existing
	end
	local template = findTemplate(kind, worldId)
	if not template then
		local name = Tiles.PortalTemplates[kind]
		if not warned[name] then
			warned[name] = true
			warn(`[WorldPortals] gabarit {name} absent (ReplicatedStorage.Assets.Props ou Assets.Worlds.<monde>)`)
		end
		return nil
	end
	local model = template:Clone()
	local look = facing and Vector3.new(facing.X, position.Y, facing.Z)
	local cf = if look and (look - position).Magnitude > 0.5 then CFrame.lookAt(position, look) else CFrame.new(position)
	model:PivotTo(cf)
	if title then
		for _, d in model:GetDescendants() do
			if d:IsA("TextLabel") and d.Name == "Title" then
				d.Text = title
			end
		end
	end
	model.Parent = parent
	current[kind] = model
	return model
end

-- Fait éclater les ParticleEmitter du portail qui portent l'attribut Burst (nombre de particules).
function WorldPortals.burst(kind: Kind)
	local model = current[kind]
	if not model then
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			local n = d:GetAttribute("Burst")
			if type(n) == "number" and n > 0 then
				d:Emit(math.floor(n))
			end
		end
	end
end

-- Début du fondu vers le monde suivant. Renvoie la durée (s) avant de construire ce monde.
function WorldPortals.beginTransition(nextWorldId: string): number
	local seconds = Tiles.TransitionSeconds
	transitionToken += 1
	local token = transitionToken
	WorldPortals.burst("NextWorld")
	Workspace:SetAttribute(ATTR_WORLD, nextWorldId)
	Workspace:SetAttribute(ATTR_END, Workspace:GetServerTimeNow() + seconds)
	Workspace:SetAttribute(ATTR, "NextWorld")
	-- Filet de sécurité : si le monde suivant n'arrive jamais (fin de run), on rouvre l'image.
	task.delay(seconds + 5, function()
		if token == transitionToken then
			WorldPortals.endTransition()
		end
	end)
	return seconds
end

-- Fin du fondu (le nouveau monde est publié).
function WorldPortals.endTransition()
	transitionToken += 1
	if Workspace:GetAttribute(ATTR) ~= "" then
		Workspace:SetAttribute(ATTR, "")
	end
end

-- Oublie les portails posés (leur dossier de stage les détruit).
function WorldPortals.clear()
	table.clear(current)
end

WorldPortals.Attribute = ATTR
WorldPortals.AttributeWorld = ATTR_WORLD
WorldPortals.AttributeEnd = ATTR_END

return WorldPortals
