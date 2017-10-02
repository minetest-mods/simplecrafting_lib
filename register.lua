--------------------------------------------------------------------------------------------------------------------
-- Local functions

-- Finds the greatest common divisor of the two input parameters
local function greatest_common_divisor(a, b)
    local temp
    while(b > 0) do
        temp = b
        b = a % b
        a = temp
    end
    return a
end

-- Finds the greatest common divisor of an arbitrarily long list of numbers
local function gcd_list(list)
	if #list == 1 then
		return list[1]
	end
	local gcd = list[1]
	for i=2, #list do
        gcd = greatest_common_divisor(gcd, list[i])
	end
    return gcd
end

-- divides input, output and returns values by their greatest common divisor
-- does *not* modify time or any other values
local function reduce_recipe(def)
	local list = {}
	for _, count in pairs(def.input) do
		table.insert(list, count)
	end
	if def.output then
		for _, count in pairs(def.output) do
			table.insert(list, count)
		end
	end
	if def.returns then
		for _, count in pairs(def.returns) do
			table.insert(list, count)
		end
	end
	local gcd = gcd_list(list)
	if gcd ~= 1 then	
		for item, count in pairs(def.input) do
			def.input[item] = count/gcd
		end
		if def.output then
			for item, count in pairs(def.output) do
				def.output[item] = count/gcd
			end
		end
		if def.returns then
			for item, count in pairs(def.returns) do
				def.returns[item] = count/gcd
			end
		end
	end
end

-- Strip group: from group names to simplify comparison later
local function strip_groups(def)
	local groups = {}
	for item, count in pairs(def.input) do
		local group = string.match(item, "^group:(%S+)$")
		if group then
			groups[group] = count
		end
	end
	-- must be done in two steps like this in case the recipe has more than one group item
	-- doing it in the first loop could invalidate the pairs iterator and miss one
	for group, count in pairs(groups) do
		def.input[group] = count
		def.input["group:"..group] = nil
	end
	
	return def
end

-- Deep equals, used to check for duplicate recipes during registration
local function deep_equals(test1, test2)
	if test1 == test2 then
		return true
	end
	if type(test1) ~= "table" or type(test2) ~= "table" then
		return false
	end
	local value2
	for key, value1 in pairs(test1) do
		value2 = test2[key]
		if value1 ~= value2 and not deep_equals(value1, test2[key]) then
			return false
		end
	end
	for key, _ in pairs(test2) do
		if test1[key] == nil then
			return false
		end
	end
	return true
end

--------------------------------------------------------------------------------------------------------------------
-- Public API

simplecrafting_lib.register = function(craft_type, def)
	def.input = def.input or {}
	def.output = def.output or {}
	def.returns = def.returns or {}

	reduce_recipe(def)
	strip_groups(def)

	local crafting_info = simplecrafting_lib.get_crafting_info(craft_type)
	
	-- Check if this recipe has already been registered. Many different old-style recipes
	-- can reduce down to equivalent recipes in this system, so this is a useful step
	-- to keep things tidy and efficient.
	for _, existing_recipe in pairs(crafting_info.recipes) do
		if deep_equals(def, existing_recipe) then
			return false
		end
	end

	table.insert(crafting_info.recipes, def)
	
	if def.output then
		local recipes_by_out = crafting_info.recipes_by_out
		for item, _ in pairs(def.output) do
			recipes_by_out[item] = recipes_by_out[item] or {} 
			recipes_by_out[item][#recipes_by_out[item]+1] = def
		end
	end

	local recipes_by_in = crafting_info.recipes_by_in
	for item, _ in pairs(def.input) do
		recipes_by_in[item] = recipes_by_in[item] or {} 
		recipes_by_in[item][#recipes_by_in[item]+1] = def
	end
	
	return true
end

-- Registers the provided crafting recipe, and also
-- automatically creates and registers a "reverse" craft of the same type.
-- This should generally only be done with craft that turns one type of item into
-- one other type of item (for example, metal ingots <-> metal blocks), but
-- it will still work if there are multiple inputs.
-- If there's more than one input type it will use "returns" to give them to the
-- player in the reverse craft.
-- Don't use a recipe that has a "group:" input with this, because obviously that
-- can't be turned into an output. The mod will assert if you try to do this.
simplecrafting_lib.register_reversible = function(typeof, forward_def)
	local reverse_def = table.copy(forward_def) -- copy before registering, registration messes with "group:" prefixes
	simplecrafting_lib.register(typeof, forward_def)

	local forward_in = reverse_def.input
	reverse_def.input = simplecrafting_lib.count_list_add(reverse_def.output, reverse_def.returns)
	
	local most_common_in_name = ""
	local most_common_in_count = 0
	for item, count in pairs(forward_in) do
		assert(string.sub(item, 1, 6) ~= "group:")
		if count > most_common_in_count then
			most_common_in_name = item
			most_common_in_count = count
		end
	end
	reverse_def.output = {[most_common_in_name]=most_common_in_count}
	forward_in[most_common_in_name] = nil
	reverse_def.returns = forward_in
	
	simplecrafting_lib.register(typeof, reverse_def)
end