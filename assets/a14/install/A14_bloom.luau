--!nocheck
-- A14 : Bloom de Lighting pour les effets v2 (dossier 12, section 15). À lancer avec execute_luau (mode
-- édition) sur COHUE. Accord du coordinateur le 5 nov. : A01 est à l'arrêt et Clément a validé la direction
-- « effets en lumière ». S'il existe déjà un BloomEffect dans Lighting, on le règle au lieu d'en ajouter un.
-- Réglages : Intensity 0,6 ; Size 24 ; Threshold 0,95 (seules les parties très claires, comme les effets
-- et le Neon, débordent).
local Lighting = game:GetService("Lighting")
local found = {}
for _, d in Lighting:GetChildren() do
	if d:IsA("BloomEffect") then
		table.insert(found, d)
	end
end
local before = nil
local bloom = found[1]
if bloom then
	before = { name = bloom.Name, enabled = bloom.Enabled, intensity = bloom.Intensity, size = bloom.Size, threshold = bloom.Threshold }
else
	bloom = Instance.new("BloomEffect") -- effet de post-traitement, pas un objet du décor
	bloom.Name = "Bloom"
	bloom.Parent = Lighting
end
bloom.Enabled = true
bloom.Intensity = 0.6
bloom.Size = 24
bloom.Threshold = 0.95
bloom:SetAttribute("A14", "effets v2, dossier 12 §15")
return { existing = #found, before = before, technology = Lighting.Technology.Name }
