--!strict
-- Binary format for weapon visual events (dossier 10, section 10). Cosmetic only: losing a packet
-- changes nothing in the game. Sent on the WeaponFx UnreliableRemoteEvent.
--
-- Chunk  = header (6 bytes) + count * record (14 bytes), never more than Balance.ChunkMaxBytes.
--   header: version u8 | tick u32 | count u8
--   record: head u8 (kind: low 3 bits, sizeStep: high 5 bits) | visual u8 | a u16 | x i16 | z i16
--           | p1 i16 | p2 i16 | p3 u8 | p4 u8
-- Positions quantized to 1/4 stud (Balance.PositionScale).
--
-- Kinds and their fields:
--   Projectile: a = projectile id, p1/p2 = velocity x/z (1/4 stud/s), p3 = life (0.1 s), p4 = owner FxSlot
--   End:        a = projectile id (projectile removed early: hit, caught)
--   Area:       p1 = radius (1/4 stud), p2 = direction (0.01 rad), p3 = half cone angle (deg, 0 = circle),
--               p4 = delay before impact (0.1 s; 0 = now)
--   Segment:    p1/p2 = end x/z (1/4 stud)
--   Attach:     a = owner FxSlot, p1 = radius (1/4 stud), p2 = duration (0.01 s), p3 = count,
--               p4 = spin (0.05 rad/s). Replaces the owner's previous attach of the same visual,
--               unless p3 >= 128: fixed at (x, z) (turrets), count = p3 - 128, never replaced.
-- sizeStep: visual scale = 0.5 + 0.1 * step (0.5 .. 3.6).
-- visual: weapon index 1..16 (Config.Weapons), or one of Codec.Visual (passives / items).

local Balance = require(script.Parent.Config.Balance)

local VERSION = 1
local HEADER = 6
local RECORD = 14
local PER_CHUNK = (Balance.ChunkMaxBytes - HEADER) // RECORD
local SCALE = Balance.PositionScale
local MAX_I16 = 32767

assert(PER_CHUNK >= 1 and PER_CHUNK <= 255, "ChunkMaxBytes gives an invalid records-per-chunk count")

local Codec = {}

Codec.Version = VERSION
Codec.PerChunk = PER_CHUNK

Codec.Kind = {
	Projectile = 1,
	End = 2,
	Area = 3,
	Segment = 4,
	Attach = 5,
}

-- Ids visuels au-dessus des 16 armes (passifs de classe et objets)
Codec.Visual = {
	FusionFlag = 0, -- réservé
	Parry = 20, -- Knight / Valor : parade
	Blessing = 21, -- Cleric / Blessing (réservé au soin visible)
	Ghost = 22,
	Whistle = 23,
	Megaphone = 24,
	Thorns = 25,
	Shadowstep = 26, -- Rogue : glissade intouchable
	ChainBolt = 27, -- arcs de critique (chainOnCrit)
	MiniBomb = 28,
}

-- Event queue in struct-of-arrays form, reused every tick (no per-event tables).
export type Queue = {
	n: number,
	head: { number },
	visual: { number },
	a: { number },
	x: { number },
	z: { number },
	p1: { number },
	p2: { number },
	p3: { number },
	p4: { number },
}

export type Header = { version: number, tick: number, count: number }

function Codec.newQueue(): Queue
	return { n = 0, head = {}, visual = {}, a = {}, x = {}, z = {}, p1 = {}, p2 = {}, p3 = {}, p4 = {} }
end

local function q16(v: number): number
	return math.clamp(math.round(v), -MAX_I16, MAX_I16)
end

local function u8(v: number): number
	return math.clamp(math.round(v), 0, 255)
end

function Codec.sizeStep(scale: number): number
	return math.clamp(math.round((scale - 0.5) * 10), 0, 31)
end

function Codec.scaleOf(step: number): number
	return 0.5 + step * 0.1
end

-- Appends one event. Values are in game units; quantization happens here.
function Codec.push(
	q: Queue,
	kind: number,
	visual: number,
	scale: number,
	a: number,
	x: number,
	z: number,
	p1: number,
	p2: number,
	p3: number,
	p4: number
)
	local n = q.n + 1
	q.n = n
	q.head[n] = bit32.bor(bit32.band(kind, 7), bit32.lshift(Codec.sizeStep(scale), 3))
	q.visual[n] = u8(visual)
	q.a[n] = bit32.band(math.round(a), 0xFFFF)
	q.x[n] = q16(x * SCALE)
	q.z[n] = q16(z * SCALE)
	q.p1[n] = q16(p1)
	q.p2[n] = q16(p2)
	q.p3[n] = u8(p3)
	q.p4[n] = u8(p4)
end

function Codec.clear(q: Queue)
	q.n = 0
end

-- Encodes the events whose queue indices are listed in idx[1..n] into chunks.
function Codec.encode(tick: number, q: Queue, idx: { number }, n: number): { buffer }
	local chunkCount = math.max(1, math.ceil(n / PER_CHUNK))
	local out: { buffer } = table.create(chunkCount)
	for c = 0, chunkCount - 1 do
		local first = c * PER_CHUNK + 1
		local last = math.min(n, first + PER_CHUNK - 1)
		local count = math.max(0, last - first + 1)
		local b = buffer.create(HEADER + count * RECORD)
		buffer.writeu8(b, 0, VERSION)
		buffer.writeu32(b, 1, tick)
		buffer.writeu8(b, 5, count)
		local o = HEADER
		for k = first, last do
			local i = idx[k]
			buffer.writeu8(b, o, q.head[i])
			buffer.writeu8(b, o + 1, q.visual[i])
			buffer.writeu16(b, o + 2, q.a[i])
			buffer.writei16(b, o + 4, q.x[i])
			buffer.writei16(b, o + 6, q.z[i])
			buffer.writei16(b, o + 8, q.p1[i])
			buffer.writei16(b, o + 10, q.p2[i])
			buffer.writeu8(b, o + 12, q.p3[i])
			buffer.writeu8(b, o + 13, q.p4[i])
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
	local version = buffer.readu8(b, 0)
	local count = buffer.readu8(b, 5)
	if version ~= VERSION or len ~= HEADER + count * RECORD then
		return nil
	end
	return { version = version, tick = buffer.readu32(b, 1), count = count }
end

-- Calls fn for each record with raw quantized fields converted back to game units where obvious:
-- x, z in studs; p1..p4 raw (the caller interprets them per kind, see the header comment).
function Codec.forEach(
	b: buffer,
	count: number,
	fn: (kind: number, scale: number, visual: number, a: number, x: number, z: number, p1: number, p2: number, p3: number, p4: number) -> ()
)
	local o = HEADER
	for _ = 1, count do
		local head = buffer.readu8(b, o)
		fn(
			bit32.band(head, 7),
			Codec.scaleOf(bit32.rshift(head, 3)),
			buffer.readu8(b, o + 1),
			buffer.readu16(b, o + 2),
			buffer.readi16(b, o + 4) / SCALE,
			buffer.readi16(b, o + 6) / SCALE,
			buffer.readi16(b, o + 8),
			buffer.readi16(b, o + 10),
			buffer.readu8(b, o + 12),
			buffer.readu8(b, o + 13)
		)
		o += RECORD
	end
end

Codec.Scale = SCALE

return Codec
