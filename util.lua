--------------------------------------------------------------------------------------------------------------------
-- Local functions

-- Turns an item list (as returned by inv:get_list) into a form more easily used by crafting functions
local function itemlist_to_countlist(itemlist)
	local count_list = {}
	for _, stack in ipairs(itemlist) do
		if not stack:is_empty() then
			local name = stack:get_name()
			count_list[name] = (count_list[name] or 0) + stack:get_count()
			-- alias its groups to the item
			if minetest.registered_items[name] then
				for group, _ in pairs(minetest.registered_items[name].groups or {}) do
					if not count_list[group] then count_list[group] = {} end
					count_list[group][name] = true -- using names as keys makes this act as a set
				end
			end
		end
	end
	return count_list
end

-- splits a string into an array of substrings based on a delimiter
local function split(str, delimiter)
    local result = {}
    for match in (str..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match)
    end
    return result
end

-- I apologise for this function.
-- From the items in groupset, checks input_list to find the item 
-- with the highest count and adds it to required_input
local function get_highest_count_item_for_group(groupset, input_list, required_input, count)
	local highest_item_name
	local highest_item_count = 0
	for group_item, _ in pairs(groupset) do
		if input_list[group_item] > highest_item_count then
			highest_item_count = input_list[group_item]
			highest_item_name = group_item
		end
	end
	if highest_item_count == 0 then
		return false
	end			
	required_input[highest_item_name] = (required_input[highest_item_name] or 0) + count
	return true
end

-- returns the number of times the recipe can be crafted from the given input_list,
-- and also a copy of the recipe with groups substituted for the most common item
-- in the input_list that matches them
local function get_craft_count(input_list, recipe)
	-- Recipe without groups (most common node in group instead)
	local work_recipe = table.copy(recipe)
	work_recipe.input = {}
	local required_input = work_recipe.input
	for item, count in pairs(recipe.input) do
		if string.find(item, ",") then -- special syntax used to require an item that belongs to multiple groups
			local groups = split(item, ",")

			-- This unfortunate block of code builds up an intersection
			-- of the items belonging to each group in the list of groups
			-- that this recipe item slot requires.
			local multigroup_itemset
			for _, group in pairs(groups) do
				if not input_list[group] then
					return 0
				end
				if not multigroup_itemset then
					multigroup_itemset = {}
					for multigroup_item, _ in pairs(input_list[group]) do
						multigroup_itemset[multigroup_item] = true
					end				
				else
					local intersect = {}
					for multigroup_item, _ in pairs(input_list[group]) do
						if multigroup_itemset[multigroup_item] then
							intersect[multigroup_item] = true
						end
					end
					multigroup_itemset = intersect
				end				
			end
			
			if not get_highest_count_item_for_group(multigroup_itemset, input_list, required_input, count) then
				return 0
			end
		else
			if not input_list[item] then
				return 0
			end
			-- Groups are a string alias to most common member item
			if type(input_list[item]) == "table" then
				-- find group item with highest count
				if not get_highest_count_item_for_group(input_list[item], input_list, required_input, count) then
					return 0
				end
			else
				required_input[item] = (required_input[item] or 0) + count
			end
		end
	end
	local number = math.huge
	for ingredient, count in pairs(required_input) do
		local max = input_list[ingredient] / count
		if max < 1 then
			return 0
		elseif max < number then
			number = max
		end
	end
	-- Return number of possible crafts as integer
	return math.floor(number), work_recipe
end

-- Used for alphabetizing an array of itemstacks by description
local function compare_stacks_by_desc(stack1, stack2)
	local item1 = stack1:get_name()
	local item2 = stack2:get_name()
	local def1 = minetest.registered_items[item1]
	local def2 = minetest.registered_items[item2]
	return def1.description < def2.description
end

--------------------------------------------------------------------------------------------------------------------
-- Public API

simplecrafting_lib.get_crafting_info = function(craft_type)
	-- ensure the destination tables exist
	simplecrafting_lib.type[craft_type] = simplecrafting_lib.type[craft_type] or {}
	simplecrafting_lib.type[craft_type].recipes = simplecrafting_lib.type[craft_type].recipes or {}
	simplecrafting_lib.type[craft_type].recipes_by_out = simplecrafting_lib.type[craft_type].recipes_by_out or {}
	simplecrafting_lib.type[craft_type].recipes_by_in = simplecrafting_lib.type[craft_type].recipes_by_in or {}

	return simplecrafting_lib.type[craft_type]
end

-- returns a fuel definition for the item if it is fuel, nil otherwise
-- note: will always return the last-registered definition for a particular item
-- or group.
simplecrafting_lib.is_fuel = function(craft_type, item)
	local fuels = simplecrafting_lib.get_crafting_info(craft_type).recipes_by_in
	
	-- First check if the item has been explicitly registered as fuel
	if fuels[item] then
		return fuels[item][#fuels[item]]
	end

	-- Failing that, check its groups.
	local def = minetest.registered_items[item]
	if def and def.groups then
		local max = -1
		local fuel_group
		for group, _ in pairs(def.groups) do
			if fuels[group] then
				local last_fuel_def = fuels[group][#fuels[group]]
				if last_fuel_def.burntime > max then
					fuel_group = last_fuel_def -- track whichever is the longest-burning group
					max = fuel_group.burntime
				end
			end
		end
		if fuel_group then
			return fuel_group
		end
	end
	return nil
end

-- Returns a list of all fuel recipes whose ingredients can be satisfied by the item_list
simplecrafting_lib.get_fuels = function(craft_type, item_list)
	local count_list = itemlist_to_countlist(item_list)
	local burnable = {}
	for item, count in pairs(count_list) do
		local recipe = simplecrafting_lib.is_fuel(craft_type, item)
		if recipe then
			table.insert(burnable, recipe)
		end
	end
	return burnable
end

-- Returns a list of all recipes whose ingredients can be satisfied by the item_list
simplecrafting_lib.get_craftable_recipes = function(craft_type, item_list)
	local count_list = itemlist_to_countlist(item_list)
	local craftable = {}
	local recipes = simplecrafting_lib.type[craft_type].recipes	
	for i = 1, #recipes do
		local number, recipe = get_craft_count(count_list, recipes[i])
		if number > 0 then
			table.insert(craftable, recipe)
		end
	end
	return craftable
end

-- Returns a list of all the possible item stacks that could be crafted from the provided item list
-- if max_craftable is true the returned stacks will have as many items in them as possible to craft,
-- if max_craftable is false or nil the returned stacks will have only the minimum output
-- if alphabetize is true then the items will be sorted alphabetically by description
-- if alphabetize is false or nil the items will be left in default order
simplecrafting_lib.get_craftable_items = function(craft_type, item_list, max_craftable, alphabetize)
	local count_list = itemlist_to_countlist(item_list)
	local craftable_count_list = {}
	local craftable_stacks = {}
	local chosen_recipe = {}
	local recipes = simplecrafting_lib.type[craft_type].recipes	
	for i = 1, #recipes do
		local number, recipe = get_craft_count(count_list, recipes[i])
		if number > 0 then
			if not max_craftable then number = 1 end
			for item, count in pairs(recipe.output) do
				if craftable_count_list[item] and count*number > craftable_count_list[item] then
					craftable_count_list[item] = count*number
					chosen_recipe[item] = recipe
				elseif not craftable_count_list[item] and count*number > 0 then
					craftable_count_list[item] = count*number
					chosen_recipe[item] = recipe
				end
			end
		end
	end
	-- Limit stacks to stack limit
	for item, count in pairs(craftable_count_list) do
		local stack = ItemStack(item)
		local max = stack:get_stack_max()
		if count > max then
			count = max - max % chosen_recipe[item].output[item]
		end
		stack:set_count(count)
		table.insert(craftable_stacks, stack)
	end
	if alphabetize then
		table.sort(craftable_stacks, compare_stacks_by_desc)
	end
	return craftable_stacks
end

-- Returns true if the item name is an input for at least one
-- recipe belonging to the given craft type
simplecrafting_lib.is_possible_input = function(craft_type, item_name)
	local recipes = simplecrafting_lib.type[craft_type].recipes
	local item_def = minetest.registered_items[item_name]
	local groups = item_def.groups or {}
	for i = 1, #recipes do
		if recipes[i].input[item_name] then
			return true
		end
		-- TODO: this group check doesn't handle the dual-group flower/dye thing
		for group, _ in pairs(groups) do
			if recipes[i].input[group] then
				return true
			end
		end
	end
	return false
end

-- Returns true if the item is a possible output for at least
-- one recipe belonging to the given craft type
simplecrafting_lib.is_possible_output = function(craft_type, item_name)
	return simplecrafting_lib.type[craft_type].recipes_by_out[item_name] ~= nil
end

-- adds two count lists together, returns a new count list with the sum of the parameters' contents
simplecrafting_lib.count_list_add = function(list1, list2)
	local out_list = {}
	for item, count in pairs(list1) do
		out_list[item] = count
	end
	for item, count in pairs(list2) do
		if type(count) == "table" then
			-- item is actually a group name, it has a set of items associated with it.
			-- Perform a union with existing set.
			out_list[item] = out_list[item] or {}			
			for group_item, _ in pairs(count) do
				out_list[item][group_item] = true
			end
		else
			out_list[item] = (out_list[item] or 0) + count
		end
	end
	return out_list
end

-- Returns a recipe with the inputs and outputs multiplied to match the requested
-- quantity of ouput items in the crafted stack. Note that the output could
-- actually be larger than crafted_stack if an exactly matching recipe can't be found.
-- returns nil if crafting is impossible with the given source inventory
simplecrafting_lib.get_crafting_result = function(crafting_type, input_list, request_stack)
	local input_count = itemlist_to_countlist(input_list)
	local request_name = request_stack:get_name()
	local request_count = request_stack:get_count()
		
	local recipes = simplecrafting_lib.type[crafting_type].recipes_by_out[request_name]
	local smallest_remainder = math.huge
	local smallest_remainder_output_count = 0
	local smallest_remainder_recipe = nil
	for i = 1, #recipes do
		local number, recipe = get_craft_count(input_count, recipes[i])
		if number > 0 then
			local output_count = recipe.output[request_name]
			if (request_count % output_count) <= smallest_remainder and output_count > smallest_remainder_output_count then
				smallest_remainder = request_count % output_count
				smallest_remainder_output_count = output_count
				smallest_remainder_recipe = recipe
			end			
		end
	end

	if smallest_remainder_recipe then
		local multiple = math.ceil(request_count / smallest_remainder_recipe.output[request_name])
		for input_item, quantity in pairs(smallest_remainder_recipe.input) do
			smallest_remainder_recipe.input[input_item] = multiple * quantity
		end
		for output_item, quantity in pairs(smallest_remainder_recipe.output) do
			smallest_remainder_recipe.output[output_item] = multiple * quantity
		end
		if smallest_remainder_recipe.returns then
			for returned_item, quantity in pairs(smallest_remainder_recipe.returns) do
				smallest_remainder_recipe.returns[returned_item] = multiple * quantity
			end
		end
		return smallest_remainder_recipe
	end
	return nil
end

----------------------------------------------------------------------------------------
-- Run-once code, post server initialization, that purges all uncraftable recipes from the
-- crafting system data.

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
			return false
		end
	end
	if recipe.output then
		for item, count in pairs(recipe.output) do
			if not minetest.registered_items[item] then
				return false
			end
		end
	end
	if recipe.returns then
		for item, count in pairs(recipe.returns) do
			if not minetest.registered_items[item] then
				return false
			end
		end
	end
	return true
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
			if validate_inputs_and_outputs(recs[i]) then
				i = i + 1
			else
				minetest.log("info", "Uncraftable recipe purged from [crafting] mod:\n"..dump(recs[i]))
				table.remove(recs, i)
			end
		end
		for output, _ in pairs(simplecrafting_lib.type[craft_type].recipes_by_out) do
			i = 1
			local outs = simplecrafting_lib.type[craft_type].recipes_by_out[output]
			while i <= #outs do
				if validate_inputs_and_outputs(outs[i]) then
					i = i + 1
				else
					table.remove(outs, i)
				end
			end		
		end
		for input, _ in pairs(simplecrafting_lib.type[craft_type].recipes_by_in) do
			i = 1
			local ins = simplecrafting_lib.type[craft_type].recipes_by_in[input]
			while i <= #ins do
				if validate_inputs_and_outputs(ins[i]) then
					i = i + 1
				else
					table.remove(ins, i)
				end
			end		
		end
	end
	
	group_examples = nil -- don't need this any more.
end

minetest.after(0, purge_uncraftable_recipes)