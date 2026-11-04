--!strict
-- Binary snapshot format for enemies (doc 12.2).
--
-- Chunk = header (7 bytes) + count * record (7 bytes), never more than Balance.ChunkMaxBytes.
--   header: tick u32 | chunkIndex u8 | chunkCount u8 | count u8
--   record: id u16 | x i16 | z i16 | flags u8 (kind: low 5 bits, state: high 3 bits)
-- Unreliable packets arrive out of order: the client drops chunks older than the newest tick seen.

local Balance = require(script.Parent.Config.Balance)

local HEADER = 7
local RECORD = 7
local PER_CHUNK = (Balance.ChunkMaxBytes - HEADER) // RECORD
local SCALE = Balance.PositionScale
local MAX_I16 = 32767

assert(PER_CHUNK >= 1 and PER_CHUNK <= 255, "ChunkMaxBytes gives an invalid records-per-chunk count")

export type Header = {
	tick: number,
	chunkIndex: number,
	chunkCount: number,
	count: number,
}

local Codec = {}
Codec.PerChunk = PER_CHUNK

local function quantize(v: number): number
	return math.clamp(math.round(v * SCALE), -MAX_I16, MAX_I16)
end

function Codec.packFlags(kind: number, state: number): number
	return bit32.bor(bit32.band(kind, 31), bit32.lshift(bit32.band(state, 7), 5))
end

function Codec.unpackFlags(flags: number): (number, number)
	return bit32.band(flags, 31), bit32.rshift(flags, 5)
end

-- Encodes n records from parallel arrays into one or more chunks.
-- n = 0 still yields one empty chunk so the client knows the tick happened.
function Codec.encode(
	tick: number,
	ids: { number },
	xs: { number },
	zs: { number },
	flags: { number },
	n: number
): { buffer }
	local chunkCount = math.max(1, math.ceil(n / PER_CHUNK))
	assert(chunkCount <= 255, "too many chunks")
	local out: { buffer } = table.create(chunkCount)
	for c = 0, chunkCount - 1 do
		local first = c * PER_CHUNK + 1
		local last = math.min(n, first + PER_CHUNK - 1)
		local count = math.max(0, last - first + 1)
		local b = buffer.create(HEADER + count * RECORD)
		buffer.writeu32(b, 0, tick)
		buffer.writeu8(b, 4, c)
		buffer.writeu8(b, 5, chunkCount)
		buffer.writeu8(b, 6, count)
		local o = HEADER
		for i = first, last do
			buffer.writeu16(b, o, ids[i])
			buffer.writei16(b, o + 2, quantize(xs[i]))
			buffer.writei16(b, o + 4, quantize(zs[i]))
			buffer.writeu8(b, o + 6, flags[i])
			o += RECORD
		end
		out[c + 1] = b
	end
	return out
end

-- Returns nil for anything malformed (never trust packet sizes).
function Codec.readHeader(b: buffer): Header?
	local len = buffer.len(b)
	if len < HEADER then
		return nil
	end
	local count = buffer.readu8(b, 6)
	if len ~= HEADER + count * RECORD then
		return nil
	end
	return {
		tick = buffer.readu32(b, 0),
		chunkIndex = buffer.readu8(b, 4),
		chunkCount = buffer.readu8(b, 5),
		count = count,
	}
end

function Codec.forEach(b: buffer, count: number, fn: (id: number, x: number, z: number, flags: number) -> ())
	local o = HEADER
	for _ = 1, count do
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
--   header: spawnCount u16 | removedCount u16
--   spawn:  id u16 | x f32 | y f32 | z f32 | angle f32 | speed f32 | life f32 | radius f32 | t0 f64 | color u8 u8 u8
--   removed: id u16
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
	color: Color3,
}

local P_HEADER = 4
local P_SPAWN = 2 + 4 * 7 + 8 + 3

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
		buffer.writeu8(b, o + 38, math.floor(p.color.R * 255 + 0.5))
		buffer.writeu8(b, o + 39, math.floor(p.color.G * 255 + 0.5))
		buffer.writeu8(b, o + 40, math.floor(p.color.B * 255 + 0.5))
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
			color = Color3.fromRGB(buffer.readu8(b, o + 38), buffer.readu8(b, o + 39), buffer.readu8(b, o + 40)),
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

return Codec
