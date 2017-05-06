crafting = {}
crafting.type = {}
crafting.fuel = {}

local modpath = minetest.get_modpath(minetest.get_current_modname()) 

dofile(modpath .. "/config.lua")
dofile(modpath .. "/util.lua")
dofile(modpath .. "/guide.lua")
dofile(modpath .. "/legacy.lua")

dofile(modpath .. "/table.lua")
dofile(modpath .. "/furnace.lua")

if crafting.config.import_default_recipes then

	crafting.get_legacy_type = function(legacy_method, legacy_recipe)
		if legacy_method == "normal" then
			return "table"
		elseif legacy_method == "cooking" then
			return "furnace"
		end
		minetest.log("error", "get_legacy_type encountered unknown legacy method "..legacy_method)
		return nil
	end

	crafting.import_legacy_recipes(crafting.config.clear_default_crafting)
end

if crafting.config.clear_default_crafting then
	-- If we've cleared all native crafting recipes, add the table back
	-- in to the native crafting system so that the player can
	-- build that and access everything else through it
	crafting.minetest_register_craft({
		output = "crafting:table",
		recipe = {
			{"group:tree","group:tree",""},
			{"group:tree","group:tree",""},
			{"","",""},
		},
	})
end
