crafting = {}
crafting.type = {}
crafting.fuel = {}

local modpath = minetest.get_modpath("crafting") 

dofile(modpath .. "/config.lua")
dofile(modpath .. "/util.lua")
dofile(modpath .. "/legacy.lua")
dofile(modpath .. "/table.lua")
dofile(modpath .. "/furnace.lua")


-- Hopper compatibility
if minetest.get_modpath("hopper") and hopper ~= nil and hopper.add_container ~= nil then
	hopper:add_container({
		{"top", "crafting:furnace", "dst"},
		{"bottom", "crafting:furnace", "src"},
		{"side", "crafting:furnace", "fuel"},

		{"top", "crafting:furnace_active", "dst"},
		{"bottom", "crafting:furnace_active", "src"},
		{"side", "crafting:furnace_active", "fuel"},

		{"top", "crafting:table", "store"},
		{"bottom", "crafting:table", "store"},
		{"side", "crafting:table", "store"},
	})
end
