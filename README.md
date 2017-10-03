Note: this is a utility mod that is intended for use by other mods, it does not do anything if installed by itself.

This mod adds a new crafting system, either in parallel to the default grid-based crafting system or as complete replacement to it.

The new crafting system doesn't care about the arrangement of raw materials, only the relative proportions of them. Effectively, every recipe is now "shapeless".

You can continue to use minetest.register_craft to register crafts as normal, this mod hooks into it and can reinterpret recipes registered via it to use with the new crafting system as well.

Alternately, use the "simplecrafting_lib.register" method to register recipes for the new
system exclusively. Examples are given below:

	-- Crafting Table

	simplecrafting_lib.register("table",{
		input = {
			["group:stone"] = 1,
			["default:lava_source"] = 1,
		},
		output = {
			["default:obsidian"] = 2,
		},
		-- Items which the crafting recipe produces, but is not
		-- formally used to make, e.g. returning an empty bucket
		-- from a recipe using a water bucket
		returns = {
			["default:stone"] = 1,
		},
	})

	-- Furnace

	simplecrafting_lib.register("furnace",{
		input = {
			["default:stone"] = 1,
		},
		output = {
			["default:obsidian"] = 2,
		},
		cooktime = 5.6,
	})

	-- Fuel

	simplecrafting_lib.register("fuel",{
		-- Group names are allowed
		-- If there is not an item specific recipe then it will take the
		-- definition of its longest burning group
		input = {
			["default:tree"] = 1
		},
		burntime = 25.4,
	})

The following example code used in a mod that depends on simplecrafting_lib to import existing recipes from Minetest's native crafting system. In this particular case the mod it is from adds the concept of "fuel grade," which the mod's furnace node can take into account when determining whether a given fuel is hot enough to catalyze a given reaction. This shows how import filters can modify imported recipes however it likes and how simplecrafting recipes can include arbitrary metadata beyond the standard parameters shown above. It could also choose to place the recipes into categories based on other properties of the recipe - for example, it could place "cooking" recipes involving ore into a different crafting type than "cooking" recipes involving food items.

	simplecrafting_lib.register_recipe_import_filter(function(legacy_method, legacy_recipe)
		if legacy_method == "normal" then
			return "table", true
		elseif legacy_method == "cooking" then
			legacy_recipe.fuel_grade = {}
			legacy_recipe.fuel_grade.min = 0
			legacy_recipe.fuel_grade.max = math.huge
			return "furnace", true
		elseif legacy_method == "fuel" then
			legacy_recipe.grade = 1
			return "fuel", true
		end
		minetest.log("error", "get_legacy_type encountered unknown legacy method: "..legacy_method)
	end)
	simplecrafting_lib.import_legacy_recipes()


To create a standard crafting table that would be able to make use of the "table" craft_type populated by the above recipe import filter, there's a convenience function that provides pre-generated functions for use with a crafting table node definition. The following code shows an example:

	local table_functions = simplecrafting_lib.generate_table_functions("table", show_guides, alphabetize_items)

	local table_def = {
		description = S("Crafting Table"),
		drawtype = "normal",
		tiles = {"crafting.table_top.png", "default_chest_top.png",
			"crafting.table_front.png", "crafting.table_front.png",
			"crafting.table_side.png", "crafting.table_side.png"},
		sounds = default.node_sound_wood_defaults(),
		paramtype2 = "facedir",
		is_ground_content = false,
		groups = {oddly_breakable_by_hand = 1, choppy=3},
	}
	for k, v in pairs(table_functions) do
		table_def[k] = v
	end

	minetest.register_node("crafting:table", table_def)
	
This produces a crafting table with a formspec similar to the following:

![Crafting table formspec](screenshot.png)

[See api.md for more information about how to use this mod's API.](api.md)

This library is released under the MIT license.