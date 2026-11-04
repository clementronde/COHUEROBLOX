--!strict
-- Late-bound access between services (server) or controllers (client).
-- Main registers every module before init; modules call Registry.get("Name") inside
-- functions (never at require time), so require cycles cannot happen.
-- Server and client each have their own copy (separate Luau VMs).

local Registry = {}

local modules: { [string]: any } = {}

function Registry.register(name: string, module: any)
	modules[name] = module
end

-- Errors if the module is missing: use for hard dependencies.
function Registry.get(name: string): any
	local module = modules[name]
	if module == nil then
		error(`Registry: "{name}" is not loaded`, 2)
	end
	return module
end

-- Returns nil if missing: use for optional dependencies.
function Registry.find(name: string): any?
	return modules[name]
end

return Registry
