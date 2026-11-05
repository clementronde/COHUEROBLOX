-- Charge dans la place ouverte tous les scripts servis par tools/studio-serve.sh.
-- À lancer avec execute_luau (datamodel Edit) sur la place COHUE uniquement.
-- Sauvegarde d'abord les anciens scripts dans ServerStorage (ils n'y tournent pas),
-- puis crée ou remplace chaque script ; ne supprime jamais un script absent du disque.
local PORT = 8787
local HttpService = game:GetService("HttpService")
local SES = game:GetService("ScriptEditorService")
local roots = {
	shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared"),
	server = game:GetService("ServerScriptService"):WaitForChild("Server"),
	client = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"):WaitForChild("Client"),
}
local base = "http://127.0.0.1:" .. PORT .. "/"

local backup = Instance.new("Folder")
backup.Name = "COHUE_Backup_" .. os.date("!%Y%m%d_%H%M%S")
for key, root in roots do
	local c = root:Clone()
	c.Name = key
	c.Parent = backup
end
backup.Parent = game:GetService("ServerStorage")

local list = HttpService:GetAsync(base .. ".studio-files.txt", true)
local updated, created, failed = 0, 0, {}
local i = 0
for path in list:gmatch("[^\r\n]+") do
	i += 1
	local ok, err = pcall(function()
		local src = HttpService:GetAsync(base .. path, true)
		local parts = string.split(path, "/")
		local parent = roots[parts[1]]
		for j = 2, #parts - 1 do
			local f = parent:FindFirstChild(parts[j])
			if not f then
				f = Instance.new("Folder")
				f.Name = parts[j]
				f.Parent = parent
			end
			parent = f
		end
		local file = parts[#parts]
		local class, name = "ModuleScript", (file:gsub("%.luau$", ""))
		if file:match("%.legacy%.luau$") then
			class, name = "Script", (file:gsub("%.legacy%.luau$", ""))
		elseif file:match("%.local%.luau$") then
			class, name = "LocalScript", (file:gsub("%.local%.luau$", ""))
		elseif file:match("%.server%.luau$") then
			class, name = "Script", (file:gsub("%.server%.luau$", ""))
		elseif file:match("%.client%.luau$") then
			class, name = "LocalScript", (file:gsub("%.client%.luau$", ""))
		end
		local inst = parent:FindFirstChild(name)
		if inst and inst.ClassName ~= class then
			inst:Destroy()
			inst = nil
		end
		if inst then
			updated += 1
		else
			inst = Instance.new(class)
			inst.Name = name
			inst.Parent = parent
			created += 1
		end
		SES:UpdateSourceAsync(inst, function()
			return src
		end)
	end)
	if not ok then
		table.insert(failed, path .. ": " .. tostring(err))
	end
	if i % 10 == 0 then
		task.wait()
	end
end
return { backup = backup.Name, updated = updated, created = created, failed = failed }
