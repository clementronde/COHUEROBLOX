--!strict
-- Ground height lookup shared by server and client.
-- Phase 0: flat ground (default Baseplate top is Y = 0).
-- Later (doc 12.2): a precomputed height grid per stage, never one raycast per enemy per tick.

local GROUND_Y = 0

local Heightmap = {}

function Heightmap.getY(_x: number, _z: number): number
	return GROUND_Y
end

return Heightmap
