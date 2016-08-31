-- Crafting Table
--[[
crafting.register("table",{
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
	ret = {
		["default:stone"] = 1,
	},
})

for i=1,100 do
	crafting.register("table",{
		input = {
			["default:dirt_with_grass"] = 1,
		},
		output = {
			["invalid:thing" .. tostring(i)] = 1,
		},
	})
end
--]]

-- Furnace
--[[
crafting.register("furnace",{
	input = {
		-- Must only have one input type, or will be ignored by furnace
		-- Recipes cannot be distinguished by the no of input, only
		-- Fuel grades and name of input
		["default:stone"] = 1,

		-- If an item is in multiple groups with valid recipes, output
		-- will be first valid recipe found (essentially random)
	},
	output = {
		-- Must only have one input type, or will be ignored by furnace
		["default:obsidian"] = 2,
	},
	time = 5.6,
	-- This is the quality of the fuel allowed
	-- Grades are as follows:
	-- 0 - How does this even burn? 
	-- 1 - Very poor - saplings,shrubs etc.
	-- 2 - poor - dry shrubs etc.
	-- 3 - ok - wood etc.
	-- 4 - average - dry wood etc.
	-- 5 - good - coal etc.
	-- 6 - very good - charcoal, lava etc.
	-- 7 - excellent - non-magical better fuels added by mods
	-- 8+ - magical grades added by mods

	-- If a more specific recipe is defined later, it will re-define
	-- the range of this recipe
	fuel_grade = {
		-- Defaults to 0 if left nil
		min = 1,
		-- Defaults to math.huge if left nil
		max = 3,
	},
})

crafting.register("fuel",{
	-- Group names are allowed
	-- If there is not an item specific recipe then it will take the
	-- definition of it's longest burning group
	name = "default:tree",
	burntime = 25.4,
	grade = 3,
})
--]]
