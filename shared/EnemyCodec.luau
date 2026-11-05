--!strict
-- Binary snapshot format for enemies (doc 12.2).
--
-- Chunk = header (8 bytes) + removed * 2 + count * record (7 bytes), never more than
-- Balance.ChunkMaxBytes (900).
--   header:  tick u32 | chunkIndex u8 | chunkCount u8 | count u8 | removedCount u8
--   removed: id u16 (chunk 0 only) : enemies gone since the last tick (dead, cleared). The client
--            drops them at once instead of waiting for ClientStaleTicks (A03-v3, PERF-01).
--   record:  id u16 | x i16 | z i16 | flags u8 (kind: low 5 bits, state: high 3 bits)
-- Unreliable packets arrive out of order: the client drops chunks older than the newest tick seen.
-- Since PERF-01 the server does not send every enemy every tick (EnemyService.send) : the client
-- interpolates over the real gap between two samples of one enemy.
--
-- Buffers are reused by size (PERF-04) : a buffer returned by encode is only valid until the next
-- encode call. FireClient serialises it at once, so this is safe for the snapshot loop.

local Balance = require(script.Parent.Config.Balance)

local HEADER = 8
local RECORD = 7
local MAX_BYTES = Balance.ChunkMaxBytes
local PER_CHUNK = (MAX_BYTES - HEADER) // RECORD
local SCALE = Balance.PositionScale
local MAX_I16 = 32767

assert(PER_CHUNK >= 1 and PER_CHUNK <= 255, "ChunkMaxBytes gives an invalid records-per-chunk count")

-- At most this many removed ids per tick (the rest waits for the next tick). Keeps chunk 0 useful.
local MAX_REMOVED = 100

export type Header = {
	tick: number,
	chunkIndex: number,
	chunkCount: number,
	count: number,
	removed: number,
}

local Codec = {}
Codec.PerChunk = PER_CHUNK
Codec.MaxRemoved = MAX_REMOVED
Codec.HeaderBytes = HEADER
Codec.RecordBytes = RECORD

local function quantize(v: number): number
	return math.clamp(math.round(v * SCALE), -MAX_I16, MAX_I16)
end

function Codec.packFlags(kind: number, state: number): number
	return bit32.bor(bit32.band(kind, 31), bit32.lshift(bit32.band(state, 7), 5))
end

function Codec.unpackFlags(flags: number): (number, number)
	return bit32.band(flags, 31), bit32.rshift(flags, 5)
end

local bufCache: { [number]: buffer } = {}
local outChunks: { buffer } = {}

local function takeBuffer(len: number): buffer
	local b = bufCache[len]
	if not b then
		b = buffer.create(len)
		bufCache[len] = b
	end
	return b
end

-- Encodes n records from parallel arrays into one or more chunks, plus `nr` removed ids in chunk 0.
-- n = 0 still yields one chunk so the client knows the tick happened.
-- The returned table and buffers are reused by the next call.
function Codec.encode(
	tick: number,
	ids: { number },
	xs: { number },
	zs: { number },
	flags: { number },
	n: number,
	removed: { number }?,
	nr: number?
): { buffer }
	local removedN = math.clamp(nr or 0, 0, MAX_REMOVED)
	local first0 = (MAX_BYTES - HEADER - removedN * 2) // RECORD -- records that fit in chunk 0
	local rest = math.max(0, n - first0)
	local chunkCount = 1 + math.ceil(rest / PER_CHUNK)
	assert(chunkCount <= 255, "too many chunks")
	table.clear(outChunks)
	local first = 1
	for c = 0, chunkCount - 1 do
		local cap = if c == 0 then first0 else PER_CHUNK
		local last = math.min(n, first + cap - 1)
		local count = math.max(0, last - first + 1)
		local nrem = if c == 0 then removedN else 0
		local b = takeBuffer(HEADER + nrem * 2 + count * RECORD)
		buffer.writeu32(b, 0, tick)
		buffer.writeu8(b, 4, c)
		buffer.writeu8(b, 5, chunkCount)
		buffer.writeu8(b, 6, count)
		buffer.writeu8(b, 7, nrem)
		local o = HEADER
		if nrem > 0 and removed then
			for k = 1, nrem do
				buffer.writeu16(b, o, removed[k])
				o += 2
			end
		end
		for i = first, last do
			buffer.writeu16(b, o, ids[i])
			buffer.writei16(b, o + 2, quantize(xs[i]))
			buffer.writei16(b, o + 4, quantize(zs[i]))
			buffer.writeu8(b, o + 6, flags[i])
			o += RECORD
		end
		outChunks[c + 1] = b
		first = last + 1
	end
	return outChunks
end

-- Returns nil for anything malformed (never trust packet sizes).
function Codec.readHeader(b: buffer): Header?
	local len = buffer.len(b)
	if len < HEADER then
		return nil
	end
	local count = buffer.readu8(b, 6)
	local removed = buffer.readu8(b, 7)
	if len ~= HEADER + removed * 2 + count * RECORD then
		return nil
	end
	return {
		tick = buffer.readu32(b, 0),
		chunkIndex = buffer.readu8(b, 4),
		chunkCount = buffer.readu8(b, 5),
		count = count,
		removed = removed,
	}
end

function Codec.forEachRemoved(b: buffer, header: Header, fn: (id: number) -> ())
	local o = HEADER
	for _ = 1, header.removed do
		fn(buffer.readu16(b, o))
		o += 2
	end
end

function Codec.forEach(b: buffer, header: Header, fn: (id: number, x: number, z: number, flags: number) -> ())
	local o = HEADER + header.removed * 2
	for _ = 1, header.count do
		fn(
			buffer.readu16(b, o),
			buffer.readi16(b, o + 2) / SCALE,
			buffer.readi16(b, o + 4) / SCALE,
			buffer.readu8(b, o + 6)
		)
		o += RECORD
	end
end

-- Enemy projectiles (dossier 20 section 4.5), reliable remote, one buffer per server tick:
--   header:  spawnCount u16 | removedCount u16
--   spawn:   id u16 | x f32 | y f32 | z f32 | angle f32 | speed f32 | life f32 | radius f32 | t0 f64 | style u8
--   removed: id u16
-- style (dossier 13 §9.3, contract request 4) = kind of the shooter (low 5 bits) | attack slot << 5
-- (index of the boss attack in Bosses.List[].attacks, 0 for an ordinary enemy). The client picks
-- the projectile object from it (Arrow, Feather, Bone...). Replaces the 3 colour bytes of v1.
-- The client replays motion in closed form: pos = origin + dir * speed * (serverNow - t0).
export type Projectile = {
	id: number,
	x: number,
	y: number,
	z: number,
	angle: number,
	speed: number,
	life: number,
	radius: number,
	t0: number,
	style: number,
}

local P_HEADER = 4
local P_SPAWN = 2 + 4 * 7 + 8 + 1

function Codec.packStyle(kind: number, slot: number?): number
	return bit32.bor(bit32.band(kind, 31), bit32.lshift(bit32.band(slot or 0, 7), 5))
end

function Codec.unpackStyle(style: number): (number, number)
	return bit32.band(style, 31), bit32.rshift(style, 5)
end

function Codec.encodeProjectiles(spawns: { Projectile }, removed: { number }): buffer
	local b = buffer.create(P_HEADER + #spawns * P_SPAWN + #removed * 2)
	buffer.writeu16(b, 0, #spawns)
	buffer.writeu16(b, 2, #removed)
	local o = P_HEADER
	for _, p in spawns do
		buffer.writeu16(b, o, p.id)
		buffer.writef32(b, o + 2, p.x)
		buffer.writef32(b, o + 6, p.y)
		buffer.writef32(b, o + 10, p.z)
		buffer.writef32(b, o + 14, p.angle)
		buffer.writef32(b, o + 18, p.speed)
		buffer.writef32(b, o + 22, p.life)
		buffer.writef32(b, o + 26, p.radius)
		buffer.writef64(b, o + 30, p.t0)
		buffer.writeu8(b, o + 38, p.style)
		o += P_SPAWN
	end
	for _, id in removed do
		buffer.writeu16(b, o, id)
		o += 2
	end
	return b
end

-- Returns nil for anything malformed.
function Codec.decodeProjectiles(b: buffer): ({ Projectile }?, { number }?)
	local len = buffer.len(b)
	if len < P_HEADER then
		return nil, nil
	end
	local ns, nr = buffer.readu16(b, 0), buffer.readu16(b, 2)
	if len ~= P_HEADER + ns * P_SPAWN + nr * 2 then
		return nil, nil
	end
	local spawns: { Projectile } = table.create(ns)
	local o = P_HEADER
	for k = 1, ns do
		spawns[k] = {
			id = buffer.readu16(b, o),
			x = buffer.readf32(b, o + 2),
			y = buffer.readf32(b, o + 6),
			z = buffer.readf32(b, o + 10),
			angle = buffer.readf32(b, o + 14),
			speed = buffer.readf32(b, o + 18),
			life = buffer.readf32(b, o + 22),
			radius = buffer.readf32(b, o + 26),
			t0 = buffer.readf64(b, o + 30),
			style = buffer.readu8(b, o + 38),
		}
		o += P_SPAWN
	end
	local removed: { number } = table.create(nr)
	for k = 1, nr do
		removed[k] = buffer.readu16(b, o)
		o += 2
	end
	return spawns, removed
end

-- Attack cues (EnemyAttackVisual, unreliable, PERF-07) : 14 bytes instead of two strings and two
-- Vector3. Sent only to the players close enough to see them.
--   id u16 | kind u8 | mode u8 | x i16 | y i16 | z i16 | dirX i8 | dirZ i8 | radius u8 (1/4 stud) | reserved u8
-- id 0 = no entity (puddle left by a dead Bloater).
-- "slam" : télégraphe d'une attaque de mini-boss (forme, rayon intérieur, durée lus dans Config/Enemies).
Codec.AttackModes = { "contact", "aim", "shot", "land", "boss", "aura", "explode", "puddle", "slam" } :: { string }
local MODE_CODE: { [string]: number } = {}
for code, name in Codec.AttackModes do
	MODE_CODE[name] = code
end

local A_BYTES = 14

function Codec.encodeAttack(id: number, kind: number, mode: string, x: number, y: number, z: number, dx: number, dz: number, radius: number): buffer?
	local code = MODE_CODE[mode]
	if not code then
		return nil
	end
	local b = buffer.create(A_BYTES)
	local d = math.sqrt(dx * dx + dz * dz)
	if d > 1e-4 and d == d then
		dx, dz = dx / d, dz / d
	else
		dx, dz = 0, 0
	end
	buffer.writeu16(b, 0, math.clamp(id, 0, 65535))
	buffer.writeu8(b, 2, math.clamp(kind, 0, 255))
	buffer.writeu8(b, 3, code)
	buffer.writei16(b, 4, quantize(x))
	buffer.writei16(b, 6, quantize(y))
	buffer.writei16(b, 8, quantize(z))
	buffer.writei8(b, 10, math.clamp(math.round(dx * 127), -127, 127))
	buffer.writei8(b, 11, math.clamp(math.round(dz * 127), -127, 127))
	buffer.writeu8(b, 12, math.clamp(math.round((if radius == radius then radius else 0) * 4), 0, 255))
	buffer.writeu8(b, 13, 0)
	return b
end

export type Attack = { id: number, kind: number, mode: string, position: Vector3, direction: Vector3, radius: number }

-- Returns nil for anything malformed.
function Codec.decodeAttack(b: buffer): Attack?
	if buffer.len(b) ~= A_BYTES then
		return nil
	end
	local mode = Codec.AttackModes[buffer.readu8(b, 3)]
	if not mode then
		return nil
	end
	return {
		id = buffer.readu16(b, 0),
		kind = buffer.readu8(b, 2),
		mode = mode,
		position = Vector3.new(buffer.readi16(b, 4) / SCALE, buffer.readi16(b, 6) / SCALE, buffer.readi16(b, 8) / SCALE),
		direction = Vector3.new(buffer.readi8(b, 10) / 127, 0, buffer.readi8(b, 11) / 127),
		radius = buffer.readu8(b, 12) / 4,
	}
end

return Codec
