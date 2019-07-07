simplecrafting_lib = {}
simplecrafting_lib.type = {}

simplecrafting_lib.pre_craft = {}
simplecrafting_lib.post_craft = {}

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
	
	minetest.after(1, function()
		-- Wait until all mods are loaded, in case default mod is loaded after simplecrafting_lib.
		if minetest.registered_craftitems["default:book_written"] == nil then
			-- If default:book_written doesn't exist, don't register these callbacks.
			return
		end
	
		simplecrafting_lib.register_pre_craft(function(craft_type, recipe, output_stack, source_item_list)
			-- screen for the recipe we care about. Note that you can't simply compare `recipe` to the
			-- registered recipe, since pre_craft may be called on a modified copy of the registered original
			if craft_type ~= "player" or recipe.output == nil or recipe.output:get_name() ~= "default:book_written" then
				return
			end
			-- find the first written book in the source inventory
			for k, source_item in ipairs(source_item_list) do
				if source_item:get_name() == "default:book_written" then
					-- the output book will have the same metadata as the source book
					local copymeta = source_item:get_meta():to_table()
					output_stack:get_meta():from_table(copymeta)
					return
				end
			end
		end)		
		simplecrafting_lib.register_post_craft(function(craft_type, recipe, output_stack, source_inv, source_listname, destination_inv, destination_listname)
			-- screen for the recipes we care about
			if craft_type ~= "player" or recipe.output == nil or recipe.output:get_name() ~= "default:book_written" then
				return
			end
			-- add an additional copy of the book into the destination inventory
			destination_inv:add_item(destination_listname, output_stack)
		end)
	end)

	simplecrafting_lib.register_player_craft_type("player")
end