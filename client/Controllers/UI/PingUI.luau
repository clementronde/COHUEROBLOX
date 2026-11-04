--!strict
-- The 6 team pings: quick contextual ping, ping wheel, world markers, off-screen edge arrows, feed.
-- Design: docs/dossier/60-ui-ux.md section 7. Listens: PingBroadcast. Sends: Ping(kind, position).
-- Input: InputController action "Ping" (tap = quick, hold 0.3 s = wheel); Minimap long press calls
-- PingUI.openWheel(worldPos); the mobile Ping button is bound to the same action.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Registry = require(Shared:WaitForChild("Registry"))
local UITheme = require(script.Parent:WaitForChild("UITheme"))
local UIInput = require(script.Parent:WaitForChild("UIInput"))

local Config = UITheme.Config
local PC = Config.Ping
local LOCAL = Players.LocalPlayer

local PingUI = {}

type Slot = {
	part: Part,
	billboard: BillboardGui,
	badge: Frame,
	glyph: TextLabel,
	text: TextLabel,
	who: TextLabel,
	arrow: Frame,
	arrowGlyph: TextLabel,
	untilT: number,
	active: boolean,
}

local slots: { Slot } = {}
local edgeGui: ScreenGui
local wheelGui: ScreenGui
local wheelButtons: { TextButton } = {}
local wheelPos: Vector3? = nil
local wheelToken = 0
local renderConn: RBXScriptConnection? = nil
local lastSent = 0

local shrines: { any } = {}
local bossPos: Vector3? = nil

---------------------------------------------------------------------------- aim / context

local function rootPart(): BasePart?
	local character = LOCAL.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function aimPoint(): Vector3?
	local root = rootPart()
	local camera = Workspace.CurrentCamera
	if not root or not camera then
		return nil
	end
	local screen: Vector2
	if UITheme.inputName() == "KeyboardAndMouse" then
		screen = UserInputService:GetMouseLocation()
	else
		screen = camera.ViewportSize / 2
	end
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { LOCAL.Character :: Instance }
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 400, params)
	local point = if hit then hit.Position else ray.Origin + ray.Direction * 120
	local offset = point - root.Position
	if offset.Magnitude > PC.ClientRange then
		point = root.Position + offset.Unit * PC.ClientRange
	end
	return point
end

local function nearestWithin(list: { Vector3 }, pos: Vector3, radius: number): boolean
	for _, p in list do
		if (p - pos).Magnitude <= radius then
			return true
		end
	end
	return false
end

local function contextKind(pos: Vector3): string
	if bossPos and (bossPos - pos).Magnitude <= PC.Context.Boss then
		return "Boss"
	end
	local shrinePositions = {}
	for _, s in shrines do
		if type(s) == "table" and typeof(s.position) == "Vector3" then
			table.insert(shrinePositions, s.position)
		end
	end
	if nearestWithin(shrinePositions, pos, PC.Context.Shrine) then
		return "Shrine"
	end
	local loot = Registry.find("LootRenderer")
	if loot and type(loot.getChests) == "function" then
		local ok, list = pcall(loot.getChests)
		if ok and type(list) == "table" then
			local chests = {}
			for _, c in list do
				if typeof(c) == "Vector3" then
					table.insert(chests, c)
				elseif type(c) == "table" and typeof(c.position) == "Vector3" then
					table.insert(chests, c.position)
				end
			end
			if nearestWithin(chests, pos, PC.Context.Chest) then
				return "Chest"
			end
		end
	end
	return "Regroup"
end

---------------------------------------------------------------------------- send

function PingUI.send(kind: string, position: Vector3)
	if not (PC.Defs :: any)[kind] or not UITheme.inRun() then
		return
	end
	local now = os.clock()
	if now - lastSent < 0.4 then
		return
	end
	lastSent = now
	if kind == "Thanks" then
		local root = rootPart()
		if root then
			position = root.Position
		end
	end
	Net.event("Ping"):FireServer(kind, position)
end

function PingUI.quickPing()
	local pos = aimPoint()
	if pos then
		PingUI.send(contextKind(pos), pos)
	end
end

---------------------------------------------------------------------------- wheel

local function closeWheel()
	wheelGui.Enabled = false
	wheelPos = nil
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(wheelGui) then
		GuiService.SelectedObject = nil
	end
end

function PingUI.openWheel(position: Vector3?)
	if not UITheme.inRun() then
		return
	end
	wheelPos = position or aimPoint()
	if not wheelPos then
		return
	end
	wheelGui.Enabled = true
	if UITheme.inputName() == "Gamepad" then
		GuiService.SelectedObject = wheelButtons[1]
	end
	wheelToken += 1
	local token = wheelToken
	task.delay(PC.WheelTimeout, function()
		if token == wheelToken and wheelGui.Enabled then
			closeWheel()
		end
	end)
end

local function buildWheel()
	wheelGui = UITheme.screen("COHUE_PingWheel", 35)
	wheelGui.Enabled = false
	local zone = UITheme.zone(wheelGui, "Wheel", Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(280, 260))
	local radius = 96
	for i, kind in PC.Kinds do
		local def = (PC.Defs :: any)[kind]
		local angle = math.rad((i - 1) * 60 - 90)
		local b = UITheme.button(zone, {
			name = kind,
			size = UDim2.fromOffset(96, 52),
			anchor = Vector2.new(0.5, 0.5),
			position = UDim2.new(0.5, math.cos(angle) * radius, 0.5, math.sin(angle) * radius),
			role = "Small",
			wrap = true,
			text = def.label,
			fill = "Panel",
		})
		UITheme.stroke(b, 3, def.color)
		b.SelectionGroup = true
		b.Activated:Connect(function()
			local pos = wheelPos
			closeWheel()
			if pos then
				PingUI.send(kind, pos)
			end
		end)
		wheelButtons[i] = b
	end
	local cancel = UITheme.button(zone, {
		name = "Cancel",
		size = UDim2.fromOffset(52, 52),
		anchor = Vector2.new(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		role = "Title",
		font = "display",
		text = "X",
	})
	UITheme.round(cancel)
	cancel.Activated:Connect(closeWheel)
	-- B / Escape closes (vault: Gamepad and Console UX).
	UserInputService.InputBegan:Connect(function(input)
		if wheelGui.Enabled and (input.KeyCode == Enum.KeyCode.ButtonB or input.KeyCode == Enum.KeyCode.Escape) then
			closeWheel()
		end
	end)
end

---------------------------------------------------------------------------- markers

local function buildSlot(folder: Instance, playerGui: Instance, i: number): Slot
	local part = Instance.new("Part")
	part.Name = "PingAnchor" .. i
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Parent = folder

	local bb = Instance.new("BillboardGui")
	bb.Name = "Ping" .. i
	bb.Adornee = part
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Size = UDim2.fromOffset(130, 64)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.MaxDistance = 600
	bb.ResetOnSpawn = false
	bb.AutoLocalize = false
	bb.Enabled = false
	bb.Parent = playerGui

	local badge = UITheme.new("Frame", {
		Size = UDim2.fromOffset(30, 30),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		BorderSizePixel = 0,
	}, bb)
	UITheme.round(badge)
	UITheme.stroke(badge, 2, "Outline")
	local glyph = UITheme.label(badge, { size = UDim2.fromScale(1, 1), role = "Title", font = "display", outline = true })
	local text = UITheme.label(bb, { size = UDim2.new(1, 0, 0, 18), position = UDim2.fromOffset(0, 31), role = "Small", outline = true })
	local who = UITheme.label(bb, {
		size = UDim2.new(1, 0, 0, 14),
		position = UDim2.fromOffset(0, 48),
		role = "Tiny",
		color = "TextDim",
		outline = true,
	})

	local arrow = UITheme.new("Frame", {
		Size = UDim2.fromOffset(34, 34),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BorderSizePixel = 0,
		Visible = false,
	}, edgeGui)
	UITheme.round(arrow)
	UITheme.stroke(arrow, 2, "Outline")
	local arrowGlyph = UITheme.label(arrow, { size = UDim2.fromScale(1, 1), role = "Body", font = "display", outline = true })

	return {
		part = part,
		billboard = bb,
		badge = badge,
		glyph = glyph,
		text = text,
		who = who,
		arrow = arrow,
		arrowGlyph = arrowGlyph,
		untilT = 0,
		active = false,
	}
end

local function edgeStep()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local now = os.clock()
	local vp = camera.ViewportSize
	local margin = 36
	local any = false
	for _, s in slots do
		if s.active then
			if now > s.untilT then
				s.active = false
				s.billboard.Enabled = false
				s.arrow.Visible = false
			else
				any = true
				local p, onScreen = camera:WorldToViewportPoint(s.part.Position)
				if onScreen and p.X > margin and p.X < vp.X - margin and p.Y > margin and p.Y < vp.Y - margin then
					s.arrow.Visible = false
				else
					-- Direction from screen centre; flip when the point is behind the camera.
					local dx, dy = p.X - vp.X / 2, p.Y - vp.Y / 2
					if p.Z < 0 then
						dx, dy = -dx, -dy
					end
					local len = math.max(1e-3, math.sqrt(dx * dx + dy * dy))
					local hx, hy = vp.X / 2 - margin, vp.Y / 2 - margin
					local k = math.min(hx / math.max(math.abs(dx), 1e-3), hy / math.max(math.abs(dy), 1e-3))
					if k * len < 1 then
						k = 1 / len
					end
					s.arrow.Position = UDim2.fromOffset(vp.X / 2 + dx * k, vp.Y / 2 + dy * k)
					s.arrow.Visible = true
				end
			end
		end
	end
	if not any and renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
end

local function show(userId: number, kind: string, position: Vector3)
	local def = (PC.Defs :: any)[kind]
	if not def then
		return
	end
	local slot: Slot? = nil
	local oldest = math.huge
	for _, s in slots do
		if not s.active then
			slot = s
			break
		end
		if s.untilT < oldest then
			oldest = s.untilT
			slot = s
		end
	end
	if not slot then
		return
	end
	local s = slot :: Slot
	local player = Players:GetPlayerByUserId(userId)
	local name = if player then player.DisplayName else "?"
	s.part.Position = position
	UITheme.paint(s.badge, "BackgroundColor3", def.color)
	UITheme.paint(s.arrow, "BackgroundColor3", def.color)
	s.glyph.Text = def.glyph
	s.arrowGlyph.Text = def.glyph
	UITheme.setText(s.text, def.label)
	s.who.Text = name
	s.untilT = os.clock() + def.life
	s.active = true
	s.billboard.Enabled = true
	UITheme.pop(s.badge, 0.6)
	if not renderConn then
		renderConn = RunService.RenderStepped:Connect(edgeStep)
	end
	local hud = Registry.find("HUD")
	if hud and type(hud.feed) == "function" then
		hud.feed(Config.Strings.PingFeed, { name = name, ping = UITheme.format(def.label) })
	end
end

---------------------------------------------------------------------------- lifecycle

function PingUI.start()
	local playerGui = LOCAL:WaitForChild("PlayerGui")
	edgeGui = UITheme.screen("COHUE_PingWorld", 12, Enum.ScreenInsets.None) -- non-interactive, viewport space
	local folder = Instance.new("Folder")
	folder.Name = "COHUE_PingAnchors"
	folder.Parent = Workspace
	for i = 1, PC.PoolSize do
		slots[i] = buildSlot(folder, playerGui, i)
	end
	buildWheel()

	local pressedAt = 0
	local pressId = 0
	UIInput.onAction("Ping", function(pressed: boolean)
		if not UITheme.inRun() then
			return
		end
		if pressed then
			pressId += 1
			local id = pressId
			pressedAt = os.clock()
			task.delay(PC.HoldForWheel, function()
				if pressId == id and pressedAt > 0 then
					pressedAt = 0
					PingUI.openWheel(nil)
				end
			end)
		elseif pressedAt > 0 then
			pressedAt = 0
			pressId += 1
			if not wheelGui.Enabled then
				PingUI.quickPing()
			end
		end
	end)

	UITheme.changed:connect(function(reason: string)
		if reason == "phase" and not UITheme.inRun() then
			closeWheel()
			for _, s in slots do
				s.active = false
				s.billboard.Enabled = false
				s.arrow.Visible = false
			end
		end
	end)
	UITheme.watch("ShrineState", function(p)
		if type(p) == "table" and type(p.shrines) == "table" then
			shrines = p.shrines
		end
	end)
	UITheme.watch("RunState", function(p)
		if type(p) == "table" then
			bossPos = if p.bossRevealed and typeof(p.bossPosition) == "Vector3" then p.bossPosition else bossPos
		end
	end)
	UITheme.watch("BossState", function(p)
		if type(p) == "table" and typeof(p.position) == "Vector3" then
			bossPos = p.position
		end
	end)
	UITheme.watch("PingBroadcast", function(p)
		if type(p) == "table" and typeof(p.position) == "Vector3" and type(p.kind) == "string" then
			show(tonumber(p.userId) or 0, p.kind, p.position)
		end
	end)
end

return PingUI
