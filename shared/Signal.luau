--!strict
-- Minimal in-VM signal. Each handler runs in its own thread so one error cannot break others.

export type Connection = {
	disconnect: () -> (),
}

export type Signal = {
	connect: (self: Signal, handler: (...any) -> ()) -> Connection,
	fire: (self: Signal, ...any) -> (),
}

local Signal = {}

function Signal.new(): Signal
	local handlers: { (...any) -> () } = {}
	local self = {}

	function self.connect(_: any, handler: (...any) -> ()): Connection
		table.insert(handlers, handler)
		return {
			disconnect = function()
				local i = table.find(handlers, handler)
				if i then
					table.remove(handlers, i)
				end
			end,
		}
	end

	function self.fire(_: any, ...: any)
		for _, handler in table.clone(handlers) do
			task.spawn(handler, ...)
		end
	end

	return (self :: any) :: Signal
end

return Signal
