--!strict
-- Binary loot snapshots (docs/dossier/30-butin-autels.md section 8), same idea as EnemyCodec.
--
-- Chunk = header (8 bytes) + count * record (7 bytes), never more than Balance.ChunkMaxBytes.
--   header: tick u32 | chunkIndex u8 | chunkCount u8 | count u8 | mode u8 (0 delta, 1 full)
--   record: id u16 | x i16 | z i16 | flags u8 (kind: low 4 bits, state: high 4 bits)
-- Delta chunks carry spawns, updates and removals; full chunks list every live item in range
-- (the client prunes what a complete full set no longer contains: lost deltas get repaired).

local Balance = require(script.Parent.Config.Balance)

local HEADER = 8
local RECORD = 7
local PER_CHUNK = math.min(255, (Balance.ChunkMaxBytes - HEADER) // RECORD)
local SCALE = Balance.PositionScale
local MAX_I16 = 32767

assert(PER_CHUNK >= 1, "ChunkMaxBytes gives an invalid records-per-chunk count")

local Codec = {}
Codec.PerChunk = PER_CHUNK

Codec.Mode = { Delta = 0, Full = 1 }

-- Kind ids (4 bits, 1..15)
Codec.Kind = {
	GemSmall = 1,
	GemMedium = 2,
	GemLarge = 3,
	GemHuge = 4,
	Coin = 5,
	CoinPile = 6,
	Pot = 7,
	ChestNormal = 8,
	ChestElite = 9,
	ChestBoss = 10,
	ChestShrine = 11,
	Merchant = 12,
}

-- State bits (4 bits)
Codec.State = {
	Collected = 1, -- fly to the nearest player, then pop and remove
	Removed = 2, -- pop in place and remove (pot broken, chest opened)
	Paid = 4, -- chest costs coins: show the prompt
}

Codec.ChestKindOf = {
	Normal = Codec.Kind.ChestNormal,
	Elite = Codec.Kind.ChestElite,
	Boss = Codec.Kind.ChestBoss,
	Shrine = Codec.Kind.ChestShrine,
} :: { [string]: number }

export type Header = {
	tick: number,
	chunkIndex: number,
	chunkCount: number,
	count: number,
	mode: number,
}

local function quantize(v: number): number
	return math.clamp(math.round(v * SCALE), -MAX_I16, MAX_I16)
end

function Codec.packFlags(kind: number, state: number): number
	return bit32.bor(bit32.band(kind, 15), bit32.lshift(bit32.band(state, 15), 4))
end

function Codec.unpackFlags(flags: number): (number, number)
	return bit32.band(flags, 15), bit32.rshift(flags, 4)
end

-- Encodes n records from parallel arrays. n = 0 yields one empty chunk (full mode uses it to
-- tell the client "nothing in range").
function Codec.encode(
	tick: number,
	mode: number,
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
		buffer.writeu8(b, 7, mode)
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
	local chunkIndex, chunkCount = buffer.readu8(b, 4), buffer.readu8(b, 5)
	if chunkCount == 0 or chunkIndex >= chunkCount then
		return nil
	end
	return {
		tick = buffer.readu32(b, 0),
		chunkIndex = chunkIndex,
		chunkCount = chunkCount,
		count = count,
		mode = buffer.readu8(b, 7),
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

return Codec
