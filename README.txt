Note: this is a utility mod that is intended for use by other mods,
it does not do anything if installed by itself.

This mod adds a new crafting system, either in parallel to the default grid-based
crafting system or as complete replacement to it.

The new crafting system doesn't care about the arrangement of raw materials, only
the relative proportions of them. Effectively, every recipe is now "shapeless".

You can continue to use minetest.register_craft to register crafts as normal,
this mod hooks into it and will reinterpret recipes registered via it to use
with the new crafting system as well.

Alternately, use the "crafting.register" method to register recipes for the new
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

See api.txt for more information.
