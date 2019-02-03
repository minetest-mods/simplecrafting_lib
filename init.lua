simplecrafting_lib = {}
simplecrafting_lib.type = {}

local modpath = minetest.get_modpath(minetest.get_current_modname())

dofile(modpath .. "/util.lua")
dofile(modpath .. "/register.lua")
dofile(modpath .. "/craft.lua")
dofile(modpath .. "/inventory.lua")
dofile(modpath .. "/legacy.lua")

dofile(modpath .. "/templates/guide.lua")
dofile(modpath .. "/templates/table.lua")
dofile(modpath .. "/templates/multifurnace.lua")
dofile(modpath .. "/templates/autocraft.lua")
dofile(modpath .. "/templates/craftingtool.lua")
dofile(modpath .. "/templates/player.lua")

dofile(modpath .. "/postprocessing.lua")

if minetest.settings:get_bool("simplecrafting_lib_enable_developer_commands") then
	dofile(modpath .. "/saveload/saveload.lua")
end

if minetest.settings:get_bool("simplecrafting_lib_override_default_player_crafting") then
	simplecrafting_lib.register_recipe_import_filter(function(legacy_recipe)
		if legacy_recipe.input["simplecrafting_lib:heat"] then
			return nil, false
		elseif legacy_recipe.output and legacy_recipe.output:get_name() == "simplecrafting_lib:heat" then
			return nil, false
		else
			return "player", true
		end
	end)

	simplecrafting_lib.register_player_craft_type("player")
end