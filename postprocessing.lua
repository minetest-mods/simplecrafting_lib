local get_invalid_items = function(recipe)
	local invalid_items = {}
			
	for item, _ in pairs(recipe.input) do
		if minetest.registered_items[item] == nil and string.find(item, ":") ~= nil then
			table.insert(invalid_items, item)
		end
	end
	for item, _ in pairs(recipe.output) do
		if minetest.registered_items[item] == nil then
			table.insert(invalid_items, item)
		end
	end
	for item, _ in pairs(recipe.returns) do
		if minetest.registered_items[item] == nil then
			table.insert(invalid_items, item)
		end
	end
	
	return invalid_items
end

local validate = function()
	for craft_type, contents in pairs(simplecrafting_lib.type) do
		for i = #contents.recipes, 1, -1 do
			local invalid_items = get_invalid_items(contents.recipes[i])
			if #invalid_items > 0 then
				minetest.log("error", "[simplecrafting_lib] recipe " .. dump(contents.recipes[i])
					.. "\nof type " .. craft_type .. " contains invalid items: "
					.. table.concat(invalid_items, " ") .. "\nRecipe removed. This could be due to an error in the mod that defined this recipe, rather than an error in simplecrafting_lib itself.")
				table.remove(contents.recipes, i)
			end			
		end
		for out_item, recipes in pairs(contents.recipes_by_out) do
			for i = #recipes, 1, -1 do
				local invalid_items = get_invalid_items(recipes[i])
				if #invalid_items > 0 then
					table.remove(recipes, i)
				end			
			end			
			if #contents.recipes_by_out[out_item] == 0 or minetest.registered_items[out_item] == nil then
				contents.recipes_by_out[out_item] = nil
			end
		end
		for in_item, recipes in pairs(contents.recipes_by_in) do
			for i = #recipes, 1, -1 do
				local invalid_items = get_invalid_items(recipes[i])
				if #invalid_items > 0 then
					table.remove(recipes, i)
				end			
			end
			if #contents.recipes_by_in[in_item] == 0 or minetest.registered_items[in_item] == nil then
				contents.recipes_by_in[in_item] = nil
			end			
		end
	end
end

-- Note that a circular table reference will result in a crash, TODO: guard against that.
-- Unlikely to be needed, though - it'd take a lot of work for users to get into this bit of trouble.
local function deep_copy(recipe_in)
	local recipe_out = {}
	
	for index, value in pairs(recipe_in) do
		if type(value) == "table" then
			recipe_out[index] = deep_copy(value)
		else
			recipe_out[index] = value
		end
	end
	return recipe_out
end

-- Tests for recipies that don't actually do anything (A => A)
-- and for recipes that pointlessly consume input without giving new output
local operative_recipe = function(recipe)
	local has_an_effect = false
	for in_item, in_count in pairs(recipe.input) do
		local out_count = recipe.output[in_item] or 0
		local returns_count = recipe.returns[in_item] or 0
		if out_count + returns_count ~= in_count then
			has_an_effect = true
			break
		end
	end
	if not has_an_effect then
		return false
	end

	local new_output
	for out_item, out_count in pairs(recipe.output) do
		if not recipe.input[out_item] or recipe.input[out_item] < out_count then
			-- produces something that's not in the input, or produces more of the input item than there was intially.
			return true
		end	
	end	
	return false
end

-- This method goes through all of the recipes in a craft type and finds ones that "feed into" each other, creating new recipes that skip those unnecessary intermediate steps.
-- So for example if there's a recipe that goes A + B => C, and a recipe that goes C + D => E, this method will detect that and create an additional recipe that goes A + B + D => E.
local disintermediate = function(craft_type, contents)
	local disintermediating_recipes = {}
	for _, recipe in pairs(contents.recipes) do
		for in_item, in_count in pairs(recipe.input) do
			-- check if there's recipes in this crafting type that produces the input item
			if contents.recipes_by_out[in_item] then
				-- find a recipe whose output divides evenly into the input
				for _, recipe_producing_in_item in pairs(contents.recipes_by_out[in_item]) do
					if in_count % recipe_producing_in_item.output[in_item] == 0 then
						local multiplier = in_count / recipe_producing_in_item.output[in_item]
						local working_recipe = deep_copy(recipe)
						working_recipe.input[in_item] = nil -- clear the input from the working recipe (soon to be our newly created disintermediated recipe)
						-- add the inputs and outputs of the disintermediating recipe
						for new_in_item, new_in_count in pairs(recipe_producing_in_item.input) do
							if not working_recipe.input[new_in_item] then
								working_recipe.input[new_in_item] = new_in_count * multiplier
							else
								working_recipe.input[new_in_item] = working_recipe.input[new_in_item] + new_in_count * multiplier
							end						
						end
						for new_out_item, new_out_count in pairs(recipe_producing_in_item.output) do
							if new_out_item ~= in_item then -- this output is what's replacing the input we deleted, so don't add it.
								if not working_recipe.output[new_out_item] then
									working_recipe.output[new_out_item] = new_out_count * multiplier
								else
									working_recipe.output[new_out_item] = working_recipe.output[new_out_item] + new_out_count * multiplier
								end
							end
						end
						for new_returns_item, new_returns_count in pairs(recipe_producing_in_item.returns) do
							if not working_recipe.returns[new_returns_item] then
								working_recipe.returns[new_returns_item] = new_returns_count * multiplier
							else
								working_recipe.returns[new_returns_item] = working_recipe.returns[new_returns_item] + new_returns_count * multiplier
							end						
						end
						
						if operative_recipe(working_recipe) then
							table.insert(disintermediating_recipes, working_recipe)
						end
					end
				end				
			end
		end
	end
	
	local count = 0
	for _, new_recipe in pairs(disintermediating_recipes) do
		if simplecrafting_lib.register(craft_type, new_recipe) then
			count = count + 1
		end
	end
	return count
end

local postprocess = function()
	validate()
	
	for craft_type, contents in pairs(simplecrafting_lib.type) do
		local cycles = contents.disintermediation_cycles or 0
		local previous_count = 0
		while cycles > 0 do
			local new_count = disintermediate(craft_type, contents)
			if new_count == 0 then
				minetest.log("info", "[simplecrafting_lib] disintermediation loop for crafting type " .. craft_type
					.. " exited early due to no need for additional disintermediation recipes.")
				cycles = 0
				break
			elseif previous_count > 0 and new_count > previous_count then
				minetest.log("error", "[simplecrafting_lib] potential disintermediation problem: crafting type \""
					.. craft_type .. "\" added " .. previous_count .. " disintermediation recipes on the previous cycle "
					.. "and " .. new_count .. " disintermediation recipes on the current cycle. This growing recipe "
					.. "addition rate could indicate that there's a unbalanced \"loop\" in the recipes defined for "
					.. "this craft type, resulting in an ever-increasing number of ways of producing a particular "
					.. "output. Examine the recipes for this craft type to see if you can identify the culprit, "
					.. "or reduce the value of this craft type's disintermediation_cycles property to prevent "
					.. "the recipe growth from getting too bad.")
			end
			cycles = cycles - 1
		end	
	end
end

minetest.after(0, postprocess)