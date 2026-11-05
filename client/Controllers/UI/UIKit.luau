--!strict
-- UIKit (A08, v3 « vraies briques ») : relie les scripts aux gabarits d'UI posés dans la place
-- (StarterGui et ReplicatedStorage.Assets.UI, montés par tools/ui/build-ui-v3.luau).
-- Règle de Clément : le code ne fabrique rien de visible. Il retrouve les objets par leur nom,
-- change leurs propriétés, les clone (listes) et les anime. Un gabarit absent est signalé dans la
-- sortie, jamais recréé.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIKit = {}

local LOCAL = Players.LocalPlayer
local warned: { [string]: boolean } = {}

local function warnOnce(key: string, msg: string)
	if not warned[key] then
		warned[key] = true
		warn("[UIKit] " .. msg)
	end
end

-- Palette COHUE 16 et ses tons (.l clair, .d ombre, .dd ombre profonde), comme le script de montage.
local PAL: { [string]: string } = {
	Ink = "1C1726", Cream = "FFE8B8", Tomato = "E63946", Leaf = "3DBE4A", Gold = "FFC21A",
	Royal = "2D6BE6", Sky = "3FD0F5", Grape = "8C52E0", Ember = "FF7A1A", Bubblegum = "FF5FB0",
	Stone = "9C9488", Steel = "8EA6C2", Bark = "6E4227", Leather = "B5713A", Plum = "4B3866", Lime = "8FD13F",
}
local LIGHT = Color3.fromHex("FFF4D8")
local SHADOW = Color3.fromHex("2A1C3D")

function UIKit.tone(key: string): Color3
	local name, suffix = string.match(key, "^(%a+)%.?(%a*)$")
	local hex = name and PAL[name]
	if not hex then
		return Color3.new(1, 1, 1)
	end
	local c = Color3.fromHex(hex)
	if suffix == "l" then
		return c:Lerp(LIGHT, 0.35)
	elseif suffix == "d" then
		return c:Lerp(SHADOW, 0.35)
	elseif suffix == "dd" then
		return c:Lerp(SHADOW, 0.6)
	end
	return c
end

-- Rôles de jeu -> couleur de brique (Go vert, Danger rouge, Premium or, Info bleu...).
UIKit.Roles = {
	Go = "Leaf",
	Primary = "Royal",
	Premium = "Gold",
	Danger = "Tomato",
	Neutral = "Stone",
	Info = "Sky",
	Capture = "Bubblegum",
	Xp = "Sky",
	Ko = "Gold",
	Downed = "Tomato",
	Ghost = "Plum",
	Revive = "Leaf",
	PanelLight = "Plum",
}

-- Recolore une brique, une étiquette ou un remplissage (racine = lèvre, Face/objet = biseau + couleur).
function UIKit.tint(obj: Instance?, colorKey: string)
	if not obj then
		return
	end
	local key = (UIKit.Roles :: any)[colorKey] or colorKey
	local base = UIKit.tone(key)
	local light = UIKit.tone(key .. ".l")
	-- lihfolk-ignore: findfirstchild-chain -- fwjelaa-ignore: findfirstchild-chain (nil-checked)
	local face = obj:FindFirstChild("Face")
	local target = face or obj
	if face and obj:IsA("GuiObject") then
		obj.BackgroundColor3 = UIKit.tone(key .. ".dd")
	end
	local grad = target:FindFirstChild("Bevel")
	if grad and grad:IsA("UIGradient") then
		local kp = grad.Color.Keypoints
		local b = if #kp >= 2 then kp[2].Time else 0.08
		grad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, light),
			ColorSequenceKeypoint.new(b, light),
			ColorSequenceKeypoint.new(math.min(b + 0.001, 0.999), base),
			ColorSequenceKeypoint.new(1, base),
		})
	elseif target:IsA("GuiObject") then
		target.BackgroundColor3 = base
	end
	obj:SetAttribute("Color", key)
end

-- ScreenGui posé dans StarterGui (Roblox le copie dans PlayerGui). Nil s'il manque.
function UIKit.screen(name: string): ScreenGui?
	local pg = LOCAL:WaitForChild("PlayerGui")
	local gui = pg:WaitForChild(name, 10)
	if not gui then
		warnOnce(name, "gabarit manquant : StarterGui." .. name .. " (lancer tools/ui/build-ui-v3.luau dans Studio)")
		return nil
	end
	return gui :: ScreenGui
end

-- Descendant par chemin « A.B.C ». Nil (et un avertissement) s'il manque.
function UIKit.find(root: Instance?, path: string): any
	if not root then
		return nil
	end
	local node: Instance? = root
	for part in string.gmatch(path, "[^%.]+") do
		node = node and node:FindFirstChild(part)
		if not node then
			warnOnce(root.Name .. "." .. path, "objet manquant : " .. root:GetFullName() .. "." .. path)
			return nil
		end
	end
	return node
end

-- Pièce réutilisée de ReplicatedStorage.Assets.UI, clonée.
function UIKit.clone(name: string): any
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local ui = assets and assets:FindFirstChild("UI")
	local t = ui and ui:FindFirstChild(name)
	if not t then
		warnOnce("kit." .. name, "pièce manquante : ReplicatedStorage.Assets.UI." .. name)
		return nil
	end
	return t:Clone()
end

export type Bar = { frame: Frame, set: (number) -> () }

-- Piste posée (Track > Fill) -> petit objet { frame, set(frac) }.
function UIKit.bar(track: Frame?): Bar
	-- lihfolk-ignore: findfirstchild-chain -- fwjelaa-ignore: findfirstchild-chain (fill is nil-checked in set)
	local fill = if track then track:FindFirstChild("Fill") :: Frame? else nil
	return {
		frame = track :: Frame,
		set = function(frac: number)
			if fill then
				local f = math.clamp(frac, 0, 1)
				fill.Size = UDim2.fromScale(f, 1)
				fill.Visible = f > 0.003
			end
		end,
	}
end

export type Tag = { frame: Frame, label: TextLabel, setTone: (string) -> () }

-- Étiquette posée (Tag > Label) -> { frame, label, setTone(rôle ou couleur) }.
function UIKit.tag(frame: Frame?): Tag
	-- lihfolk-ignore: findfirstchild-chain -- fwjelaa-ignore: findfirstchild-chain (label may be nil; callers guard)
	local label = if frame then frame:FindFirstChild("Label") :: TextLabel? else nil
	return {
		frame = frame :: Frame,
		label = label :: TextLabel,
		setTone = function(t: string)
			UIKit.tint(frame, t)
		end,
	}
end

-- Image d'une icône (shared/Config/UIAssets). Vide si pas encore téléversée.
local assetsModule: any = nil
function UIKit.icon(key: string?): string
	if not assetsModule then
		local ok, mod = pcall(function()
			return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("UIAssets") :: any)
		end)
		assetsModule = if ok then mod else { icon = function()
			return ""
		end }
	end
	return assetsModule.icon(key)
end

return UIKit
