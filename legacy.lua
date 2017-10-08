local function create_recipe(legacy)
	local items = legacy.items
	local has_items = false
	for _, item in pairs(items) do
		has_items = true
		break
	end
	if not has_items then return end
	local recipe = {method="normal"}
	local stack = ItemStack(legacy.output)
	local output = stack:get_name()
	local nout = stack:get_count()
	recipe.output = {[output] = nout}
	recipe.input = {}
	recipe.returns = legacy.returns
	for _, item in pairs(items) do
		if item ~= "" then
			recipe.input[item] = (recipe.input[item] or 0) + 1
		end
	end
	return recipe
end

-- It's possible to have a recipe with a replacements pair that gives back more than what's being replaced,
-- eg in cottages the straw mat recipe replaces 1 default:stone with 3 farming:seed_wheats.
-- This parses out that possibility
local function get_item_and_quantity(item_string)
	local string_split_list = {}
	for v in string.gmatch(item_string, "%S+") do
		table.insert(string_split_list, v)
	end	
	if #string_split_list == 1 then
		return item_string, 1 -- no number provided
	else
		return string_split_list[1], tonumber(string_split_list[#string_split_list])
	end	
end

local function process_shaped_recipe(recipe)
	local legacy = {items={},returns={},output=recipe.output}
	local count = {}
	for _,row in pairs(recipe.recipe) do
		for _, item in pairs(row) do
			legacy.items[#legacy.items+1] = item
			count[item] = (count[item] or 0) + 1
		end
	end
	if recipe.replacements then
		for _,pair in pairs(recipe.replacements) do
			local item_name, item_quantity = get_item_and_quantity(pair[2])
			legacy.returns[item_name] = count[pair[1]] * item_quantity
		end
	end
	return create_recipe(legacy)
end

local function process_shapeless_recipe(recipe)
	local legacy = {items={},returns={},output=recipe.output}
	if recipe.replacements then
		local count = {}
		for _, item in pairs(recipe.recipe) do
			count[item] = (count[item] or 0) + 1
		end
		for _,pair in pairs(recipe.replacements) do
			local item_name, item_quantity = get_item_and_quantity(pair[2])
			legacy.returns[item_name] = count[pair[1]] * item_quantity
		end
	end
	legacy.items = recipe.recipe
	return create_recipe(legacy)
end

local function process_cooking_recipe(recipe)
	local legacy = {input={},output={}, method="cooking"}
	local output_item, output_quantity = get_item_and_quantity(recipe.output)
	legacy.output[output_item] = output_quantity
	legacy.input[recipe.recipe] = 1
	legacy.cooktime = recipe.cooktime or 3			
	return legacy
end

local function process_fuel_recipe(recipe)
	local legacy = {input={}, method="fuel"}
	legacy.input[recipe.recipe] = 1
	legacy.burntime = recipe.burntime
	if recipe.replacements then
		legacy.returns = {}
		for _,pair in pairs(recipe.replacements) do
			local item_name, item_quantity = get_item_and_quantity(pair[2])
			legacy.returns[item_name] = item_quantity
		end
	end	
	return legacy
end

local already_cleared_processed = {} -- contains recipes suitable for re-registering
-- once we're done initializing, throw these tables away. They're not needed after that.
minetest.after(0, function()
	already_cleared_processed = nil
end)

-- This is necessary because the format of recipes returned by
-- get_all_crafts is completely different from the format required by clear_craft.

-- https://github.com/minetest/minetest/issues/5962
-- https://github.com/minetest/minetest/issues/5790

local function safe_clear_craft(recipe_to_clear, processed_recipe)
	table.insert(already_cleared_processed, processed_recipe)
	
	local parameter_recipe = {}
	if recipe_to_clear.method == "normal" then
		if recipe_to_clear.width == 0 then
			parameter_recipe.type="shapeless"
			parameter_recipe.recipe = recipe_to_clear.items
		elseif recipe_to_clear.width == 1 then
			parameter_recipe.width = 1
			parameter_recipe.recipe = {
				{recipe_to_clear.items[1] or ""},
				{recipe_to_clear.items[2] or ""},
				{recipe_to_clear.items[3] or ""},
			}
		elseif recipe_to_clear.width == 2 then
			parameter_recipe.width = 2
			parameter_recipe.recipe = {
				{recipe_to_clear.items[1] or "", recipe_to_clear.items[2] or ""},
				{recipe_to_clear.items[3] or "", recipe_to_clear.items[4] or ""},
				{recipe_to_clear.items[5] or "", recipe_to_clear.items[6] or ""},
			}
		elseif recipe_to_clear.width == 3 then
			parameter_recipe.width = 3
			parameter_recipe.recipe = {
				{recipe_to_clear.items[1] or "", recipe_to_clear.items[2] or "", recipe_to_clear.items[3] or ""},
				{recipe_to_clear.items[4] or "", recipe_to_clear.items[5] or "", recipe_to_clear.items[6] or ""},
				{recipe_to_clear.items[7] or "", recipe_to_clear.items[8] or "", recipe_to_clear.items[9] or ""},
			}
		end
	elseif recipe_to_clear.method == "cooking" then
		parameter_recipe.type = "cooking"
		parameter_recipe.recipe = recipe_to_clear.items[1]
	else
		minetest.log("error", "[simplecrafting_lib] safe_clear_craft was unable to parse recipe "..dump(recipe_to_clear))
		return false
	end

	-- https://github.com/minetest/minetest/issues/6513
	local success, err = pcall(function() minetest.clear_craft(parameter_recipe) end)
	if not success and err ~= "No crafting specified for input" then
		minetest.log("error", "[simplecrafting_lib] minetest.clear_craft failed with error \"" ..err.. "\" while attempting to clear craft " ..dump(parameter_recipe))
	end
	return true
end

simplecrafting_lib.import_filters = {}

simplecrafting_lib.register_recipe_import_filter = function(filter_function)
	table.insert(simplecrafting_lib.import_filters, filter_function)
end

local function register_legacy_recipe(legacy_method, legacy_recipe)
	local clear_recipe = false
	for _, filter in ipairs(simplecrafting_lib.import_filters) do
		local working_recipe = table.copy(legacy_recipe)
		local craft_type, clear_this = filter(legacy_method, working_recipe)
		if craft_type then
			simplecrafting_lib.register(craft_type, working_recipe)
		end	
		clear_recipe = clear_this or clear_recipe		
	end
	return clear_recipe
end

-- import_legacy_recipes overrides minetest.register_craft so that subsequently registered
-- crafting recipes will be put into this system. If you wish to register a craft
-- the old way without it being put into this system, use this method.
simplecrafting_lib.minetest_register_craft = minetest.register_craft

simplecrafting_lib.import_legacy_recipes = function()
	-- if any recipes have been cleared by previous runs of import_legacy_recipes, let this run have the opportunity to look at them.
	for _, recipe in pairs(already_cleared_processed) do
		register_legacy_recipe(recipe.method, recipe)
	end

	-- This loop goes through all recipes that have already been registered and
	-- converts them
	for item,_ in pairs(minetest.registered_items) do
		local crafts = minetest.get_all_craft_recipes(item)
		if crafts and item ~= "" then
			for _,recipe in pairs(crafts) do
				if recipe.method == "normal" then
					-- get_all_craft_recipes output recipes omit replacements, need to find those experimentally
					-- https://github.com/minetest/minetest/issues/4901
					recipe.returns = {}
					local output, decremented_input = minetest.get_craft_result(recipe)
					-- until https://github.com/minetest/minetest_game/commit/ae7206c0064cbb5c0e5434c19893d4bf3fa2b388
					-- the dye:red + dye:green -> dye:brown recipe was broken here - there were two
					-- red+green recipes, one producing dark grey and one producing brown dye, and when one gets
					-- cleared from the crafting system by safe_clear_craft the other goes too and this craft attempt
					-- fails.
					-- This brokenness manifests by returning their input items and no output, so check if an output
					-- was actually made before counting the returns as actual returns.
					-- This is not an ideal solution since it may result in recipes losing their replacements,
					-- but at this point I'm solving edge cases for edge cases and I need to sleep.
					if output.item:get_count() > 0 then 
						for _, returned_item in pairs(decremented_input.items) do
							if returned_item:get_count() > 0 then
								recipe.returns[returned_item:get_name()] = (recipe.returns[returned_item:get_name()] or 0) + returned_item:get_count()
							end
						end
					end
					local new_recipe = create_recipe(recipe)
					if register_legacy_recipe("normal", new_recipe) then
						safe_clear_craft(recipe, new_recipe)
					end
				elseif recipe.method == "cooking" then
					local new_recipe = {input={},output={},method="cooking"}
					local output_item, output_quantity = get_item_and_quantity(recipe.output)
					new_recipe.output[output_item] = output_quantity
					new_recipe.input[recipe.items[1]] = 1 
					local cooked = minetest.get_craft_result({method = "cooking", width = 1, items = {recipe.items[1]}})
					new_recipe.cooktime = cooked.time
					if register_legacy_recipe("cooking", new_recipe) then
						safe_clear_craft(recipe, new_recipe)
					end
				end
			end
		end
		-- Fuel recipes aren't returned by get_all_craft_recipes, need to find those experimentally
		-- https://github.com/minetest/minetest/issues/5745
		local fuel, afterfuel = minetest.get_craft_result({method="fuel",width=1,items={item}})
		if fuel.time ~= 0 then
			local new_recipe = {}
			new_recipe.method = "fuel"
			new_recipe.input = {}
			new_recipe.input[item] = 1
			new_recipe.burntime = fuel.time
			for _, afteritem in pairs(afterfuel.items) do
				if afteritem:get_count() > 0 then
					new_recipe.returns = new_recipe.returns or {}
					new_recipe.returns[afteritem:get_name()] = (new_recipe.returns[afteritem:get_name()] or 0) + afteritem:get_count()
				end
			end
			if register_legacy_recipe("fuel", new_recipe) then
				minetest.clear_craft({type="fuel", recipe=item})
				table.insert(already_cleared_processed, new_recipe)
			end
		end
	end
	
	-- This replaces the core register_craft method so that any crafts
	-- registered after this one will be added to the new system.
	minetest.register_craft = function(recipe)
		local clear = false
		local new_recipe
		if not recipe.type then
			new_recipe = process_shaped_recipe(recipe)
			clear = register_legacy_recipe("normal", new_recipe)
		elseif recipe.type == "shapeless" then
			new_recipe = process_shapeless_recipe(recipe)
			clear = register_legacy_recipe("normal", new_recipe)
		elseif recipe.type == "cooking" then
			new_recipe = process_cooking_recipe(recipe)
			clear = register_legacy_recipe("cooking", new_recipe)
		elseif recipe.type == "fuel" then
			new_recipe = process_fuel_recipe(recipe)
			clear = register_legacy_recipe("fuel", new_recipe)
		end
		if not clear then
			return simplecrafting_lib.minetest_register_craft(recipe)
		else
			table.insert(already_cleared_processed, new_recipe)
		end
	end
end