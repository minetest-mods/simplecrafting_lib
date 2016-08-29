crafting = {}

crafting.register = function(typeof,def)
	if typeof == "table" then
		return crafting.table.register(def)
	elseif typeof == "furnace" then
		return crafting.furnace.register(def)
	elseif typeof == "fuel" then
		return crafting.furnace.register_fuel(def)
	end
end

local modpath = minetest.get_modpath("crafting") 

dofile(modpath .. "/table.lua")
dofile(modpath .. "/furnace.lua")
dofile(modpath .. "/recipe.lua")
dofile(modpath .. "/legacy.lua")
