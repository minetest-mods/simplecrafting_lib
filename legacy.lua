local function create_recipe(legacy)
	local items = legacy.items
	local has_items = false
	for _, item in pairs(items) do
		has_items = true
		break
	end
	if not has_items then return end
	local recipe = {}
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
			legacy.returns[pair[2]] = count[pair[1]]
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
			legacy.returns[pair[2]] = count[pair[1]]
		end
	end
	legacy.items = recipe.recipe
	return create_recipe(legacy)
end

local function process_cooking_recipe(recipe)
	local legacy = {input={},output={}}
	legacy.output[recipe.output] = 1
	legacy.input[recipe.recipe] = 1
	legacy.cooktime = recipe.cooktime or 3			
	return legacy
end

local function process_fuel_recipe(recipe)
	local legacy = {input={}}
	legacy.input[recipe.recipe] = 1
	legacy.burntime = recipe.burntime
	if recipe.replacements then
		legacy.returns = {}
		for _,pair in pairs(recipe.replacements) do
			legacy.returns[pair[2]] = 1
		end
	end	
	return legacy
end

local already_cleared = {}
-- once we're done initializing, throw this table away. It's not needed after that.
minetest.after(0, function()
	already_cleared = nil
end)

local function compare_recipe_to_clear(recipe1, recipe2)
	if recipe1.method ~= recipe2.method then
		return false
	end	
	if recipe1.width ~= recipe2.width then
		return false
	end
	for i = 1,9 do
		if recipe1.items[i] ~= recipe2.items[i] then
			return false
		end			
	end
	return true
end

-- This is necessary because it's possible to register multiple crafts
-- with the same input, but if you clear one then all of them are cleared
-- and if you try clearing the second Minetest will crash (because you're
-- clearing a "nonexistent" recipe). Also, the format of recipes returned by
-- get_all_crafts is completely different from the format required by clear_craft.
-- Minetest is... quirky sometimes, let's put it diplomatically.
local function safe_clear_craft(recipe_to_clear)
	for _, recipe in pairs(already_cleared) do
		if compare_recipe_to_clear(recipe, recipe_to_clear) then
			return
		end
	end
	table.insert(already_cleared, recipe_to_clear)
	
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
		minetest.log("error", "safe_clear_craft was unable to parse recipe "..dump(recipe_to_clear))
		return
	end
	minetest.clear_craft(parameter_recipe)
end

crafting_lib.import_filters = {}

crafting_lib.register_recipe_import_filter = function(filter_function)
	table.insert(crafting_lib.import_filters, filter_function)
end

local function register_legacy_recipe(legacy_method, legacy_recipe)
	local clear_recipe = false
	for _, filter in ipairs(crafting_lib.import_filters) do
		local working_recipe = table.copy(legacy_recipe)
		local craft_type, clear_this = filter(legacy_method, working_recipe)
		if craft_type then
			crafting_lib.register(craft_type, working_recipe)
		end	
		clear_recipe = clear_this or clear_recipe		
	end
	return clear_recipe
end

-- import_legacy_recipes overrides minetest.register_craft so that subsequently registered
-- crafting recipes will be put into this system. If you wish to register a craft
-- the old way without it being put into this system, use this method.
crafting_lib.minetest_register_craft = minetest.register_craft

crafting_lib.import_legacy_recipes = function()
	-- This loop goes through all recipes that have already been registered and
	-- converts them
	for item,_ in pairs(minetest.registered_items) do
		local crafts = minetest.get_all_craft_recipes(item)
		if crafts and item ~= "" then
			for _,recipe in pairs(crafts) do
				if recipe.method == "normal" then
					-- get_all_craft_recipes output recipes omit replacements, need to find those experimentally
					recipe.returns = {}
					local output, decremented_input = minetest.get_craft_result(recipe)
					-- some recipes are broken (eg, the dye:red + dye:green -> dye:brown recipe - there's two
					-- red+green recipes, one producing dark grey and one producing brown dye, and when one gets
					-- cleared from the crafting system by safe_clear_craft the other goes too and this craft attempt
					-- fails).
					-- This brokenness manifests by returning their input items and no output, so check if an output
					-- was actually made before counting the returns as actual returns.
					if output.item:get_count() > 0 then 
						for _, returned_item in pairs(decremented_input.items) do
							if returned_item:get_count() > 0 then
								recipe.returns[returned_item:get_name()] = (recipe.returns[returned_item:get_name()] or 0) + returned_item:get_count()
							end
						end
					end
					local new_recipe = create_recipe(recipe)
					if register_legacy_recipe("normal", new_recipe) then
						safe_clear_craft(recipe)
					end
				elseif recipe.method == "cooking" then
					local legacy = {input={},output={}}
					legacy.output[recipe.output] = 1
					legacy.input[recipe.items[1]] = 1 
					local cooked = minetest.get_craft_result({method = "cooking", width = 1, items = {recipe.items[1]}})
					legacy.cooktime = cooked.time
					if register_legacy_recipe("cooking", legacy) then
						safe_clear_craft(recipe)
					end
				end
			end
		end
		-- Fuel recipes aren't returned by get_all_craft_recipes, need to find those experimentally
		local fuel, afterfuel = minetest.get_craft_result({method="fuel",width=1,items={item}})
		if fuel.time ~= 0 then
			local legacy = {}
			legacy.input = {}
			legacy.input[item] = 1
			legacy.burntime = fuel.time
			for _, afteritem in pairs(afterfuel.items) do
				if afteritem:get_count() > 0 then
					legacy.returns = legacy.returns or {}
					legacy.returns[afteritem:get_name()] = (legacy.returns[afteritem:get_name()] or 0) + afteritem:get_count()
				end
			end
			if register_legacy_recipe("fuel", legacy) then
				minetest.clear_craft({type="fuel", recipe=item})
			end
		end
	end
	
	-- This replaces the core register_craft method so that any crafts
	-- registered after this one will be added to the new system.
	minetest.register_craft = function(recipe)
		local clear = false
		if not recipe.type then
			local new_recipe = process_shaped_recipe(recipe)
			clear = register_legacy_recipe("normal", new_recipe)
		elseif recipe.type == "shapeless" then
			local new_recipe = process_shapeless_recipe(recipe)
			clear = register_legacy_recipe("normal", new_recipe)
		elseif recipe.type == "cooking" then
			local new_recipe = process_cooking_recipe(recipe)
			clear = register_legacy_recipe("cooking", new_recipe)
		elseif recipe.type == "fuel" then
			local new_recipe = process_fuel_recipe(recipe)
			clear = register_legacy_recipe("fuel", new_recipe)
		end
		if not clear then
			return crafting_lib.minetest_register_craft(recipe)
		end
	end
end