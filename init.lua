crafting = {}

crafting.register = function(typeof,def)
	if typeof == "table" then
		return crafting.table.register(def)
	end
end

local modpath = minetest.get_modpath("crafting") 

dofile(modpath .. "/table.lua")
dofile(modpath .. "/recipe.lua")
dofile(modpath .. "/legacy.lua")
