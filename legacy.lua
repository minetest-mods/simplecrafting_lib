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

-- This is a default implementation, other mods should override this if they wish to distribute
-- recipes to other crafting types. Note that fuel recipes are special and won't be filtered
-- by this method, they all go into the fuel registry.
-- If this method returns nil the recipe will not be imported.
crafting.get_legacy_type = function(legacy_method, legacy_recipe)
	if legacy_method == "normal" then
		return "table"
	elseif legacy_method == "cooking" then
		return "furnace"
	end
	minetest.log("error", "get_legacy_type encountered unknown legacy method "..legacy_method)
	return nil
end

-- import_legacy_recipes overrides minetest.register_craft so that subsequently registered
-- crafting recipes will be put into this system. If you wish to register a craft
-- the old way without it being put into this system, use this method.
crafting.minetest_register_craft = minetest.register_craft

crafting.import_legacy_recipes = function(clear_default_crafting)
	-- This loop goes through all recipes that have already been registered and
	-- converts them
	for item,_ in pairs(minetest.registered_items) do
		local crafts = minetest.get_all_craft_recipes(item)
		if crafts and item ~= "" then
			local added = false
			for _,recipe in pairs(crafts) do
				if recipe.method == "normal" then
					if recipe.replacements then
						recipe.returns = {}
						local count = {}
						for _, item in pairs(recipe.items) do
							count[item] = (count[item] or 0) + 1
						end
						for _,pair in pairs(recipe.replacements) do
							recipe.returns[pair[2]] = count[pair[1]]
						end
					end
					local new_recipe = create_recipe(recipe)
					local new_type = crafting.get_legacy_type("normal", new_recipe)
					if new_type then
						crafting.register(new_type, new_recipe)
						added = true
					end
				elseif recipe.method == "cooking" then
					local legacy = {input={},output={}}
					legacy.output[recipe.output] = 1
					legacy.input[recipe.items[1]] = 1 
					local cooked = minetest.get_craft_result({method = "cooking", width = 1, items = {recipe.items[1]}})
					legacy.time = cooked.time
					
					legacy.fuel_grade = {}
					legacy.fuel_grade.min = 0
					legacy.fuel_grade.max = math.huge
					local new_type = crafting.get_legacy_type("cooking",legacy)
					if new_type then
						crafting.register(new_type, legacy)
						added = true
					end
				end
			end
			if clear_default_crafting and added then
				minetest.clear_craft({output=item})
			end
		end
		local fuel, afterfuel = minetest.get_craft_result({method="fuel",width=1,items={item}})
		if fuel.time ~= 0 then
			local legacy = {}
			legacy.name = item
			legacy.burntime = fuel.time
			legacy.grade = 1
			for _, afteritem in pairs(afterfuel.items) do
				if afteritem:get_count() > 0 then
					legacy.returns = legacy.returns or {}
					legacy.returns[afteritem:get_name()] = (legacy.returns[afteritem:get_name()] or 0) + afteritem:get_count()
				end
			end
			crafting.register_fuel(legacy)
			if clear_default_crafting then
				minetest.clear_craft({type="fuel", recipe=item})
			end
		end
	end
	
	-- This replaces the core register_craft method so that any crafts
	-- registered after this one will be added to the new system.
	minetest.register_craft = function(recipe)
		local added = false
		if not recipe.type then
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
			local new_recipe = create_recipe(legacy)
			local new_type = crafting.get_legacy_type("normal", new_recipe)
			if new_type then
				crafting.register(new_type, new_recipe)
				added = true
			end
		elseif recipe.type == "shapeless" then
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
			local new_recipe = create_recipe(legacy)
			local new_type = crafting.get_legacy_type("normal", new_recipe)
			if new_type then
				crafting.register(new_type, new_recipe)
				added = true
			end
		elseif recipe.type == "cooking" then
			local legacy = {input={},output={}}
			legacy.output[recipe.output] = 1
			legacy.input[recipe.recipe] = 1
			legacy.time = recipe.cooktime or 3
			
			-- TODO: may make more sense to leave this nil and have these defaults on the util side
			legacy.fuel_grade = {}
			legacy.fuel_grade.min = 0
			legacy.fuel_grade.max = math.huge
			
			local new_type = crafting.get_legacy_type("cooking",legacy)
			if new_type then
				crafting.register(new_type, legacy)
				added = true
			end
		elseif recipe.type == "fuel" then
			local legacy = {}
			legacy.name = recipe.recipe
			legacy.burntime = recipe.burntime
			legacy.grade = 1
			if recipe.replacements then
				legacy.returns = {}
				for _,pair in pairs(recipe.replacements) do
					legacy.returns[pair[2]] = 1
				end
			end	
			crafting.register_fuel(legacy)
			added = true
		end
		if (not clear_default_crafting) or (not added) then
			return crafting.minetest_register_craft(recipe)
		end
	end
end