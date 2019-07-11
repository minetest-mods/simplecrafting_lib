local registered_callbacks = {}

simplecrafting_lib.register_postprocessing_callback = function(callback)
	table.insert(registered_callbacks, callback)
end

----------------------------------------------------------------------------------------
-- Run-once code, post server initialization, that purges all uncraftable recipes from the
-- crafting system data.

-- splits a string into an array of substrings based on a delimiter
local function split(str, delimiter)
    local result = {}
    for match in (str..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match)
    end
    return result
end

local group_examples = {}

local function input_exists(input_item)
	if minetest.registered_items[input_item] then
		return true
	end

	if group_examples[input_item] then
		return true
	end

	if not string.match(input_item, ",") then
		return false
	end
	
	local target_groups = split(input_item, ",")

	for item, def in pairs(minetest.registered_items) do
		local overall_found = true
		for _, target_group in pairs(target_groups) do
			local one_group_found = false
			for group, _ in pairs(def.groups) do
				if group == target_group then
					one_group_found = true
					break
				end
			end
			if not one_group_found then
				overall_found = false
				break
			end
		end
		if overall_found then
			group_examples[input_item] = item
			return true
		end
	end
	return false
end

local function validate_inputs_and_outputs(recipe)
	for item, count in pairs(recipe.input) do
		if not input_exists(item) then
			return item
		end
	end
	if recipe.output then
		local output_name = ItemStack(recipe.output):get_name()
		if not minetest.registered_items[output_name] then
			return output_name
		end
	end
	if recipe.returns then
		for item, count in pairs(recipe.returns) do
			if not minetest.registered_items[item] then
				return item
			end
		end
	end
	return true
end

local log_removals = minetest.settings:get_bool("simplecrafting_lib_log_invalid_recipe_removal")

local recipe_to_string = function(recipe)
	local out = "{\n"
	for k, v in pairs(recipe) do
		if k == "output" then
			out = out .. "output = \"" .. ItemStack(v):to_string() .."\",\n"
		else
			out = out .. k .. " = " .. dump(v) .. ",\n"
		end
	end
	out = out .. "}"

	return out
end

local purge_uncraftable_recipes = function()
	for item, def in pairs(minetest.registered_items) do
		for group, _ in pairs(def.groups) do
			group_examples[group] = item
		end
	end

	for craft_type, _  in pairs(simplecrafting_lib.type) do
		local i = 1
		local recs = simplecrafting_lib.type[craft_type].recipes
		while i <= #simplecrafting_lib.type[craft_type].recipes do
			local validation_result = validate_inputs_and_outputs(recs[i])
			if validation_result == true then
				i = i + 1
			else
				if log_removals then
					if string.match(validation_result, ":") then
						minetest.log("error", "[simplecrafting_lib] Uncraftable recipe purged due to the nonexistent item " .. validation_result .. "\n"..recipe_to_string(recs[i]) .. "\nThis could be due to an error in the mod that defined this recipe, rather than an error in simplecrafting_lib itself.")
					else
						minetest.log("error", "[simplecrafting_lib] Uncraftable recipe purged due to no registered items matching the group requirement " .. validation_result .. "\n"..recipe_to_string(recs[i]) .. "\nThis could be due to an error in the mod that defined this recipe, rather than an error in simplecrafting_lib itself.")
					end
				end
				table.remove(recs, i)
			end
		end
		for output, outs in pairs(simplecrafting_lib.type[craft_type].recipes_by_out) do
			i = 1
			while i <= #outs do
				if validate_inputs_and_outputs(outs[i]) == true then
					i = i + 1
				else
					table.remove(outs, i)
				end
			end
			if #outs == 0 then
				if log_removals then
					minetest.log("error", "[simplecrafting_lib] All recipes that had an output of " .. output
						.. " have been purged as uncraftable, this item can not be made by the player.")
				end
				simplecrafting_lib.type[craft_type].recipes_by_out[output] = nil
			end
		end
		for input, ins in pairs(simplecrafting_lib.type[craft_type].recipes_by_in) do
			i = 1
			while i <= #ins do
				if validate_inputs_and_outputs(ins[i]) == true then
					i = i + 1
				else
					table.remove(ins, i)
				end
			end
			if #ins == 0 then
				simplecrafting_lib.type[craft_type].recipes_by_in[input] = nil				
			end
		end
	end
	
	group_examples = nil -- don't need this any more.
end

-- Note that a circular table reference will result in a crash, TODO: guard against that.
-- Unlikely to be needed, though - it'd take a lot of work for users to get into this bit of trouble.
local function deep_copy(recipe_in)
	local recipe_out = {}
	
	for index, value in pairs(recipe_in) do
		if type(value) == "table" then
			recipe_out[index] = deep_copy(value)
		elseif type(value) == "userdata" and index == "output" then
			recipe_out[index] = ItemStack(value)
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
		local returns_count = 0
		if recipe.returns then returns_count = recipe.returns[in_item] or 0 end
		if out_count + returns_count ~= in_count then
			has_an_effect = true
			break
		end
	end
	if not has_an_effect then
		return false
	end

	local new_output
	local out_item = recipe.output:get_name()
	local out_count = recipe.output:get_count()
	if not recipe.input[out_item] or recipe.input[out_item] < out_count then
		-- produces something that's not in the input, or produces more of the input item than there was intially.
		return true
	end	
	return false
end

-- This method goes through all of the recipes in a craft type and finds ones that "feed into" each other, creating new recipes that skip those unnecessary intermediate steps.
-- So for example if there's a recipe that goes A + B => C, and a recipe that goes C + D => E, this method will detect that and create an additional recipe that goes A + B + D => E.
local disintermediate = function(craft_type, contents)
	local disintermediating_recipes = {}
	for _, recipe in pairs(contents.recipes) do
		if not recipe.do_not_disintermediate then
			for in_item, in_count in pairs(recipe.input) do
				-- check if there's recipes in this crafting type that produces the input item
				if contents.recipes_by_out[in_item] then
					-- find a recipe whose output divides evenly into the input
					for _, recipe_producing_in_item in pairs(contents.recipes_by_out[in_item]) do
						if not recipe_producing_in_item.do_not_use_for_disintermediation and
								(in_count % recipe_producing_in_item.output:get_count() == 0 or recipe_producing_in_item.output:get_count() % in_count == 0) then
								
							local multiplier = in_count / recipe_producing_in_item.output:get_count()

							local working_recipe = deep_copy(recipe)
							working_recipe.input[in_item] = nil -- clear the input from the working recipe (soon to be our newly created disintermediated recipe)
							
							if multiplier < 1 then
								-- the recipe_producing_in_item produces more than the working recipe requires by a whole multiplier.
								-- eg, 1A + 1B => 2C, 1C + 1D => 1E.
								-- Multiply working recipe by the inverse of multiplier and then set multiplier to 1.
								-- That will get us 1A + 1B + 2D => 2E
								local inverse = 1/multiplier
								multiplier = 1
								
								for item, count in pairs(working_recipe.input) do
									working_recipe.input[item] = count * inverse
								end
								working_recipe.output:set_count(working_recipe.output:get_count() * inverse)
								if working_recipe.returns then
									for item, count in pairs(working_recipe.returns) do
										working_recipe.returns[item] = count * inverse
									end
								end
								
							end
							
							-- add the inputs and outputs of the disintermediating recipe
							for new_in_item, new_in_count in pairs(recipe_producing_in_item.input) do
								if not working_recipe.input[new_in_item] then
									working_recipe.input[new_in_item] = new_in_count * multiplier
								else
									working_recipe.input[new_in_item] = working_recipe.input[new_in_item] + new_in_count * multiplier
								end						
							end
							
							local new_out_item = recipe_producing_in_item.output:get_name()
							local new_out_count = recipe_producing_in_item.output:get_count()
							if new_out_item ~= in_item then -- this output is what's replacing the input we deleted, so don't add it.
								if not working_recipe.output:get_name() == new_out_item then
									working_recipe.output = ItemStack(new_out_item .. " " .. tostring(new_out_count * multiplier))
								else
									working_recipe.output:set_count(working_recipe.output:get_count() + new_out_count * multiplier)
								end
							end
							
							if recipe_producing_in_item.returns then
								for new_returns_item, new_returns_count in pairs(recipe_producing_in_item.returns) do
									working_recipe.returns = working_recipe.returns or {}
									if not working_recipe.returns[new_returns_item] then
										working_recipe.returns[new_returns_item] = new_returns_count * multiplier
									else
										working_recipe.returns[new_returns_item] = working_recipe.returns[new_returns_item] + new_returns_count * multiplier
									end						
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
	purge_uncraftable_recipes()
	
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
			previous_count = new_count
			cycles = cycles - 1
		end	
	end
	
	for _, callback in ipairs(registered_callbacks) do
		callback()
	end
	registered_callbacks = nil
end

minetest.after(0, postprocess)