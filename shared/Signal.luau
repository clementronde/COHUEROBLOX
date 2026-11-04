--!strict
-- Minimal in-VM signal (EnemyKilled can fire hundreds of times a second).
-- Each handler runs in its own thread (task.spawn): errors and yields stay isolated, because some
-- handlers yield (DataStore, waits). Copy-on-write: connect/disconnect replace the handler array,
-- so fire() iterates without cloning. TODO(perf): once every handler is verified non-yielding,
-- switch hot events to synchronous pcall calls (review finding 7).

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
		local copy = table.clone(handlers)
		table.insert(copy, handler)
		handlers = copy
		return {
			disconnect = function()
				local i = table.find(handlers, handler)
				if i then
					local next = table.clone(handlers)
					table.remove(next, i)
					handlers = next
				end
			end,
		}
	end

	function self.fire(_: any, ...: any)
		local list = handlers
		for i = 1, #list do
			task.spawn(list[i], ...)
		end
	end

	return (self :: any) :: Signal
end

return Signal
