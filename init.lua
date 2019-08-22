simplecrafting_lib = {}
simplecrafting_lib.type = {}

local modpath = minetest.get_modpath(minetest.get_current_modname())

dofile(modpath .. "/util.lua")
dofile(modpath .. "/register.lua")
dofile(modpath .. "/craft.lua")
dofile(modpath .. "/inventory.lua")
dofile(modpath .. "/legacy.lua")
dofile(modpath .. "/postprocessing.lua")

dofile(modpath .. "/templates/guide.lua")
dofile(modpath .. "/templates/table.lua")
dofile(modpath .. "/templates/multifurnace.lua")
dofile(modpath .. "/templates/autocraft.lua")
dofile(modpath .. "/templates/craftingtool.lua")
dofile(modpath .. "/templates/player.lua")

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
	
	simplecrafting_lib.register_postprocessing_callback(function()
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
	
	simplecrafting_lib.guide.guide_def["player"] = {
		-- This matches the filtering done by the "craftguide" mod
		is_recipe_included = function(recipe, player_name)
			if minetest.get_item_group(recipe.output:get_name(), "not_in_creative_inventory") > 0 or
				minetest.get_item_group(recipe.output:get_name(), "not_in_craft_guide") > 0 then
				return false
			end
			return true
		end,
	}
end

if minetest.get_modpath("awards") then
	simplecrafting_lib.award_crafting = function(player, stack)
		-- The API changed at some point.
		if awards.players then
			awards.increment_item_counter(awards.players[player:get_player_name()], "craft", ItemStack(stack):get_name(), ItemStack(stack):get_count()) 
		elseif awards.notify_craft then
			awards.notify_craft(player, stack:get_name(), stack:get_count())
		end
	end
end