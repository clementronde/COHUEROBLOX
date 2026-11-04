--!strict
-- Round north-up radar (world -Z = up), 120 studs, 10 Hz, pooled markers.
-- Design: docs/dossier/60-ui-ux.md section 6. Vault: "Minimap and World Map UI" (projection, -Z up).
-- Listens: ShrineState, RunState, BossState, PlayerVitals (team), PingBroadcast.
-- Long press (0.5 s) on the map opens the ping wheel at the pressed point (PingUI.openWheel).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Registry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Registry"))
local UITheme = require(script.Parent:WaitForChild("UITheme"))

local Config = UITheme.Config
local MC = Config.Minimap
local LOCAL = Players.LocalPlayer

local Minimap = {}

type Marker = { frame: Frame, corner: UICorner, stroke: UIStroke, label: TextLabel }
type Chevron = { holder: Frame, bars: { Frame }, cross: TextLabel }

local gui: ScreenGui
local zone: Frame
local disc: TextButton
local markers: { Marker } = {}
local allies: { Chevron } = {}
local selfArrow: Chevron
local used = 0

local shrines: { any } = {}
local bossPos: Vector3? = nil
local bossSeen = -math.huge
local downedIds: { [number]: boolean } = {}
local pings: { { kind: string, position: Vector3, untilT: number } } = {}

local function sizeFor(): number
	return (MC.Size :: any)[UITheme.device()] or MC.Size.phone
end

---------------------------------------------------------------------------- pools

local function newMarker(): Marker
	local f = UITheme.new("Frame", {
		Size = UDim2.fromOffset(8, 8),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 3,
	}, disc)
	local corner = UITheme.corner(f, 2)
	local stroke = UITheme.stroke(f, 1, "Outline")
	local label = UITheme.label(f, { size = UDim2.fromScale(1, 1), role = "Tiny", font = "display", z = 4 })
	label.Text = ""
	return { frame = f, corner = corner, stroke = stroke, label = label }
end

local function newChevron(token: string): Chevron
	local holder = UITheme.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(14, 14),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = 5,
	}, disc)
	local bars = {}
	for i, x in { -2.5, 2.5 } do
		local bar = UITheme.new("Frame", {
			Size = UDim2.fromOffset(9, 4),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, x, 0.5, 0),
			Rotation = if i == 1 then -55 else 55,
			BorderSizePixel = 0,
			ZIndex = 5,
		}, holder)
		UITheme.paint(bar, "BackgroundColor3", token)
		UITheme.stroke(bar, 1, "Outline")
		table.insert(bars, bar)
	end
	local cross = UITheme.label(holder, {
		size = UDim2.fromScale(1.4, 1.4),
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		role = "Body",
		font = "display",
		color = token,
		outline = true,
		text = "+",
		z = 6,
	})
	cross.Visible = false
	return { holder = holder, bars = bars, cross = cross }
end

-- shape: "circle" | "square" | "diamond" | "ring"
local function place(x: number, y: number, size: number, shape: string, token: string, glyph: string?)
	used += 1
	local m = markers[used]
	if not m then
		return
	end
	local f = m.frame
	f.Visible = true
	f.Position = UDim2.new(0.5, x, 0.5, y)
	f.Size = UDim2.fromOffset(size, size)
	f.Rotation = if shape == "diamond" then 45 else 0
	m.corner.CornerRadius = if shape == "circle" or shape == "ring" then UDim.new(0.5, 0) else UDim.new(0, 2)
	UITheme.paint(f, "BackgroundColor3", token)
	f.BackgroundTransparency = if shape == "ring" then 1 else 0
	UITheme.paint(m.stroke, "Color", if shape == "ring" then token else "Outline")
	m.stroke.Thickness = if shape == "ring" then 2 else 1
	m.label.Text = glyph or ""
end

---------------------------------------------------------------------------- projection

local function project(me: Vector3, pos: Vector3, radius: number, clampEdge: boolean): (number?, number?)
	local dx = (pos.X - me.X) / MC.RangeStuds * radius
	local dy = (pos.Z - me.Z) / MC.RangeStuds * radius -- +Z is down on a north-up map
	local d = math.sqrt(dx * dx + dy * dy)
	local maxR = radius - 6
	if d > maxR then
		if not clampEdge then
			return nil, nil
		end
		dx, dy = dx / d * maxR, dy / d * maxR
	end
	return dx, dy
end

local function heading(look: Vector3): number
	return math.deg(math.atan2(look.X, -look.Z))
end

---------------------------------------------------------------------------- update

local function chestList(): { Vector3 }
	local out = {}
	local loot = Registry.find("LootRenderer")
	if loot and type(loot.getChests) == "function" then
		local ok, list = pcall(loot.getChests)
		if ok and type(list) == "table" then
			for _, c in list do
				if typeof(c) == "Vector3" then
					table.insert(out, c)
				elseif type(c) == "table" then
					if typeof(c.position) == "Vector3" then
						table.insert(out, c.position)
					elseif type(c.x) == "number" and type(c.z) == "number" then
						table.insert(out, Vector3.new(c.x, 0, c.z))
					end
				end
			end
		end
	end
	return out
end

local function update()
	local character = LOCAL.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local me = root.Position
	local radius = sizeFor() / 2
	used = 0

	for _, s in shrines do
		if type(s) == "table" and typeof(s.position) == "Vector3" then
			local x, y = project(me, s.position, radius, false)
			if x and y then
				local done = s.state == "Done" or s.state == "Failed"
				place(x, y, 8, if done then "ring" else "diamond", "MapShrine")
			end
		end
	end
	for _, c in chestList() do
		local x, y = project(me, c, radius, false)
		if x and y then
			place(x, y, 7, "square", "MapChest")
		end
	end
	local now = os.clock()
	for i = #pings, 1, -1 do
		local p = pings[i]
		if now > p.untilT then
			table.remove(pings, i)
		else
			local x, y = project(me, p.position, radius, true)
			if x and y then
				local def = (Config.Ping.Defs :: any)[p.kind]
				place(x, y, 12, "ring", if def then def.color else "Text")
			end
		end
	end
	if bossPos and (now - bossSeen < 5 or UITheme.phase() == "Boss") then
		local x, y = project(me, bossPos, radius, true)
		if x and y then
			place(x, y, 14, "circle", "MapBoss", "!")
		end
	end
	for i = used + 1, #markers do
		if markers[i].frame.Visible then
			markers[i].frame.Visible = false
		end
	end

	local n = 0
	for _, player in Players:GetPlayers() do
		if player ~= LOCAL and n < #allies then
			local ch = player.Character
			local r = ch and ch:FindFirstChild("HumanoidRootPart")
			if r and r:IsA("BasePart") then
				local x, y = project(me, r.Position, radius, true)
				if x and y then
					n += 1
					local a = allies[n]
					a.holder.Visible = true
					a.holder.Position = UDim2.new(0.5, x, 0.5, y)
					local downed = downedIds[player.UserId] == true
					a.cross.Visible = downed
					for _, b in a.bars do
						b.Visible = not downed
					end
					a.holder.Rotation = if downed then 0 else heading(r.CFrame.LookVector)
				end
			end
		end
	end
	for i = n + 1, #allies do
		allies[i].holder.Visible = false
	end

	local camera = Workspace.CurrentCamera
	selfArrow.holder.Visible = true
	selfArrow.holder.Position = UDim2.fromScale(0.5, 0.5)
	selfArrow.holder.Rotation = heading(if camera then camera.CFrame.LookVector else root.CFrame.LookVector)
end

---------------------------------------------------------------------------- long press -> ping wheel

local function worldAt(screen: Vector2): Vector3?
	local character = LOCAL.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local center = disc.AbsolutePosition + disc.AbsoluteSize / 2
	local half = disc.AbsoluteSize.X / 2
	if half <= 0 then
		return nil
	end
	local rel = (screen - center) / half
	if rel.Magnitude > 1 then
		rel = rel.Unit
	end
	local x = root.Position.X + rel.X * MC.RangeStuds
	local z = root.Position.Z + rel.Y * MC.RangeStuds
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character :: Instance }
	local hit = Workspace:Raycast(Vector3.new(x, root.Position.Y + 200, z), Vector3.new(0, -400, 0), params)
	return if hit then hit.Position else Vector3.new(x, root.Position.Y, z)
end

local function hookLongPress()
	local pressId = 0
	disc.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1 then
			return
		end
		pressId += 1
		local id = pressId
		local startPos = Vector2.new(input.Position.X, input.Position.Y)
		local lastPos = startPos
		local moveConn = input.Changed:Connect(function()
			lastPos = Vector2.new(input.Position.X, input.Position.Y)
		end)
		local endConn: RBXScriptConnection
		endConn = disc.InputEnded:Connect(function(ended)
			if ended == input or ended.UserInputType == t then
				pressId += 1
				moveConn:Disconnect()
				endConn:Disconnect()
			end
		end)
		task.delay(MC.LongPress, function()
			if pressId ~= id then
				return
			end
			moveConn:Disconnect()
			endConn:Disconnect()
			if (lastPos - startPos).Magnitude > 20 then
				return
			end
			local pos = worldAt(lastPos)
			local pingUI = Registry.find("PingUI")
			if pos and pingUI and type(pingUI.openWheel) == "function" then
				pingUI.openWheel(pos)
			end
		end)
	end)
end

---------------------------------------------------------------------------- lifecycle

local function layout()
	local s = sizeFor()
	zone.Size = UDim2.fromOffset(s, s)
end

function Minimap.getBottom(): number
	-- Bottom edge of the map in screen offset (inside the core UI safe area), for SettingsUI.
	return Config.Margin + sizeFor() * UITheme.scale()
end

function Minimap.start()
	gui = UITheme.screen("COHUE_Minimap", 11)
	zone = UITheme.zone(gui, "Minimap", Vector2.new(1, 0), UDim2.new(1, -Config.Margin, 0, Config.Margin), UDim2.fromOffset(112, 112))
	disc = Instance.new("TextButton")
	disc.Name = "Disc"
	disc.Text = ""
	disc.AutoButtonColor = false
	disc.Size = UDim2.fromScale(1, 1)
	disc.BorderSizePixel = 0
	disc.Parent = zone
	UITheme.paint(disc, "BackgroundColor3", "Panel")
	UITheme.back(disc, 0.25)
	UITheme.round(disc)
	UITheme.stroke(disc, 2, "PanelLight")
	-- Range ring at half distance.
	local ring = UITheme.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.5),
	}, disc)
	UITheme.round(ring)
	UITheme.stroke(ring, 1, "PanelLight").Transparency = 0.5
	UITheme.label(disc, {
		size = UDim2.fromOffset(14, 14),
		position = UDim2.new(0.5, 0, 0, 1),
		anchor = Vector2.new(0.5, 0),
		role = "Tiny",
		color = "TextDim",
		text = "N",
	})
	for _ = 1, MC.MaxMarkers do
		table.insert(markers, newMarker())
	end
	for _ = 1, Config.Hud.TeamMax do
		table.insert(allies, newChevron("MapAlly"))
	end
	selfArrow = newChevron("MapSelf")
	layout()
	hookLongPress()
	gui.Enabled = UITheme.inRun()

	UITheme.changed:connect(function(reason: string)
		if reason == "device" then
			layout()
		elseif reason == "phase" then
			gui.Enabled = UITheme.inRun()
		end
	end)
	UITheme.watch("ShrineState", function(p)
		if type(p) == "table" and type(p.shrines) == "table" then
			shrines = p.shrines
		end
	end)
	UITheme.watch("RunState", function(p)
		if type(p) ~= "table" then
			return
		end
		if p.bossRevealed and typeof(p.bossPosition) == "Vector3" then
			bossPos = p.bossPosition
			bossSeen = os.clock()
		elseif not p.bossRevealed and p.phase ~= "Boss" then
			bossPos = nil
		end
	end)
	UITheme.watch("BossState", function(p)
		if type(p) == "table" and typeof(p.position) == "Vector3" then
			bossPos = p.position
			bossSeen = os.clock()
		end
	end)
	UITheme.watch("PlayerVitals", function(p)
		if type(p) == "table" and type(p.team) == "table" then
			for key, info in p.team do
				local id = tonumber(key)
				if id and type(info) == "table" then
					downedIds[id] = info.downed == true
				end
			end
		end
	end)
	UITheme.watch("PingBroadcast", function(p)
		if type(p) == "table" and typeof(p.position) == "Vector3" and type(p.kind) == "string" then
			local def = (Config.Ping.Defs :: any)[p.kind]
			table.insert(pings, { kind = p.kind, position = p.position, untilT = os.clock() + (if def then def.life else 6) })
		end
	end)

	local period = 1 / MC.Hz
	while true do
		task.wait(period)
		if gui.Enabled then
			update()
		end
	end
end

return Minimap
