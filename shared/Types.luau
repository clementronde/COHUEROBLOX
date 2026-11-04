--!strict
-- Shared types.

export type EnemyDef = {
	id: number,
	name: string,
	hp: number,
	speed: number, -- studs per second
	radius: number,
	height: number,
	color: Color3,
}

-- Every service/controller module returns this shape. init: no yielding. start: may yield.
export type System = {
	init: (() -> ())?,
	start: (() -> ())?,
}

return nil
