# Guide — créer un nouvel ennemi Roblox

Ce guide regroupe trois choses pour toutes tes prochaines créations :
1. le **prompt** à copier,
2. la règle des **codes hexadécimaux** sur chaque part,
3. la règle et le code de base pour **l'animation** (preview et script Roblox).

Références de style : `Enemy_Zombie.html`, `Enemy_GoblinGrunt.html`, `Voxel Ghost v1.html`.

---

## 1. Prompt à copier
Change seulement ce qui est entre [crochets].

```
Crée un ennemi 3D pour mon jeu Roblox : [Enemy_Nom], rôle [Melee / Ranged / Flying],
[description courte : couleur, accessoire 1, accessoire 2], taille [X] studs.
Attaque : [description du mouvement, ex. « coup horizontal de gauche à droite avec une hache »].

Suis exactement GUIDE_NOUVEL_ENNEMI.md :
- même style que Enemy_Zombie / Enemy_GoblinGrunt (gros voxels, tête en dôme,
  yeux noirs 2×2 avec reflet blanc, bouche plate, moufles rondes, peu de détails) ;
- code hex sur chaque part (<part>_<matière>_<HEX>) ;
- juste après le modèle : animations dans la preview + script Luau
  roblox/[Nom]Controller.server.lua + roblox/[NOM].md.
```

---

## 2. Style (à respecter à chaque fois)
- **Voxels** : 1 voxel = 6,5 à 8 cm. Mesh face-culled, sans biseau ni texture.
- **Proportions chibi** : tête en dôme aussi large que le corps (11 × 9 voxels, profil superellipse), corps court, jambes de 2 à 4 voxels.
- **Visage** : 2 yeux noirs 2×2 avec 1 reflet blanc chacun, bouche plate de 5 voxels, 1 dent au maximum. Pas de nez, pas de sourcils, pas de petits détails.
- **Bras** écartés sur les côtés au repos, avec des **moufles rondes** 3×3×3 (coins retirés).
- **1 ou 2 accessoires** d'identité au maximum (marmite, louche, cerveau…). Ils doivent rester lisibles de loin.
- **Palette de 4 à 6 couleurs** mates (roughness 0,45–0,6), léger emissive sur la peau. Rim light #9B5CFF, fond #1A1630.
- **Export** toujours en pose de repos (articulations à 0).

---

## 3. Codes hexadécimaux sur chaque part
- Chaque **matière** s'appelle `<matière>_<HEX>`, par exemple `skin_green_6DBE45`.
- Chaque **mesh** s'appelle `<part>_<matière>_<HEX>`, par exemple `head_skin_green_6DBE45`.
- Parts standard : `head`, `torso`, `arm_L`, `arm_R`, `leg_L`, `leg_R`, plus les accessoires (`pot`, `ladle`, `tail_1`…).
- Le script Roblox lit le hex à la fin du nom et applique `Color3.fromHex`. Matériau : `Metal` pour les gris métal, `Neon` pour #FFFFFF (reflets), `SmoothPlastic` pour le reste.
- Le `.md` contient toujours un tableau **part → matières (hex) → matériau Roblox**, ainsi que les couleurs des VFX.

Couleurs fixes :

| Élément | Hex |
|---|---|
| Yeux | #120C1F (Neon dans la couleur du perso pendant l'attaque) |
| Reflet | #FFFFFF (Neon) |
| Rim light | #9B5CFF |
| Fond de la preview | #1A1630 |

---

## 4. Animation (toujours livrée juste après le modèle)
Livrables pour chaque ennemi :
1. `Enemy_[Nom].html` : preview 3D avec idle ou marche + attaque + VFX, boutons Attack / Auto attack / Walk, et touche Espace.
2. `roblox/[Nom]Controller.server.lua` : recrée la même animation dans Roblox.
3. `roblox/[NOM].md` : parts et hex, import, minutage de l'attaque, pivots.

Règles :
- **Rig** : `rig` → `leg_L`, `leg_R`, `upper` (hanche) → `torso`, `head` (→ accessoire de tête), `arm_L`, `arm_R` (→ arme). Les pivots sont en voxels depuis le sol, au centre des pieds.
- **Timing de l'attaque** : armé 0,35–0,4 s → frappe 0,12–0,15 s → tenue 0,25 s → retour 0,55 s. Les yeux passent en Neon pendant l'attaque.
- **VFX en cubes néon** : traînée sur l'arme, étoiles et éclats à l'impact, anneau qui s'agrandit, petit flash (portée courte, il ne doit pas éclairer tout le perso), léger tremblement de caméra.
- **Vérifications** : aucun membre ni arme ne traverse le corps ou la tête (rotation Y d'un bras ≤ 1,5 rad), et l'impact se produit devant le perso.
- **Attributs Roblox** : `Walking`, `AutoAttack`, `AttackEvery`, `Damage`, `HitRadius`, `Height`. Déclencheur : `model:SetAttribute("Attack", os.clock())`.

### Code de base du script Roblox
```lua
--!strict
local RunService = game:GetService("RunService")
local model = script.Parent :: Model
for k, v in { Walking = true, AutoAttack = true, AttackEvery = 2.4, Damage = 15, HitRadius = 4, Height = 4.5 } do
	if model:GetAttribute(k) == nil then model:SetAttribute(k, v) end
end

-- 1) parts groupées par préfixe + couleur lue dans le hex du nom
local PREFIXES = { "leg_L", "leg_R", "torso", "head", "arm_L", "arm_R" } -- + accessoires
local groups: { [string]: { BasePart } } = {}
for _, n in PREFIXES do groups[n] = {} end
for _, d in model:GetDescendants() do
	if d:IsA("BasePart") then
		d.Anchored, d.CanCollide = true, false
		local hex = d.Name:match("_(%x%x%x%x%x%x)$")
		if hex then d.Color = Color3.fromHex(hex) end
		for _, n in PREFIXES do
			if d.Name:sub(1, #n + 1) == n .. "_" then table.insert(groups[n], d) break end
		end
	end
end

-- 2) échelle + repère (U = studs par voxel, rootCF = sol au centre des pieds)
-- 3) pivots en voxels : P = { hip = CFrame.new(0, 3*U, 0), armR = CFrame.new(4.5*U, 6.5*U, 0), ... }
local function around(piv: CFrame, rx: number, ry: number, rz: number)
	return piv * CFrame.Angles(rx, ry, rz) * piv:Inverse()
end
-- place("arm_R", upper * around(P.armR, ax, 0, az)) → p.CFrame = rootCF * xf * restOf[p]

-- 4) boucle : marche (sinus) + courbe d'attaque (armé → frappe → tenue → retour) + VFX + dégâts
RunService.Heartbeat:Connect(function(dt)
	-- même valeurs que la preview (copier les nombres du .html)
end)
```
Scripts complets à reprendre comme modèles : `roblox/ZombieController.server.lua` et `roblox/GoblinController.server.lua`.
