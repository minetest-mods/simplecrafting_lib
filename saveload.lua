--[[
Ordered table iterator
From http://lua-users.org/wiki/SortedIteration
]]

function __genOrderedIndex( t )
    local orderedIndex = {}
    for key in pairs(t) do
        table.insert( orderedIndex, key )
    end
    table.sort( orderedIndex )
    return orderedIndex
end

function orderedNext(t, state)
    -- Equivalent of the next function, but returns the keys in the alphabetic
    -- order. We use a temporary ordered key table that is stored in the
    -- table being iterated.

    local key = nil
    --print("orderedNext: state = "..tostring(state) )
    if state == nil then
        -- the first time, generate the index
        t.__orderedIndex = __genOrderedIndex( t )
        key = t.__orderedIndex[1]
    else
        -- fetch the next value
        for i = 1,table.getn(t.__orderedIndex) do
            if t.__orderedIndex[i] == state then
                key = t.__orderedIndex[i+1]
            end
        end
    end

    if key then
        return key, t[key]
    end

    -- no more value to return, cleanup
    t.__orderedIndex = nil
    return
end

function orderedPairs(t)
    -- Equivalent of the pairs() function on tables. Allows to iterate
    -- in order
    return orderedNext, t, nil
end

-- Writes a single recipe to a table in the output file
local write_recipe = function(file, recipe)
	file:write("\t{\n")
	for key, val in orderedPairs(recipe) do
		file:write("\t\t"..key.." = ")
		if key == "output" then
			file:write("\t\"" .. ItemStack(val):to_string() .."\",\n")
		elseif type(val) == "table" then
			file:write("\t{")
			for kk, vv in orderedPairs(val) do
				if type(vv) == "string" then
					file:write("[\"" .. kk .. "\"] = \"" .. tostring(vv) .. "\", ")
				else
					file:write("[\"" .. kk .. "\"] = " .. tostring(vv) .. ", ")
				end
			end
			file:write("},\n")
		elseif type(val) == "string" then
			file:write("\t\"" .. tostring(val) .. "\",\n")
		else
			file:write("\t" .. tostring(val) .. ",\n")
		end			
	end
	file:write("\t},\n")
end

-- Dumps all recipes from the existing crafting system into a file that can be used to recreate them.
local save_recipes = function(param)
	local path = minetest.get_worldpath()
	local filename = path .. "/" .. param .. ".lua"
	local file, err = io.open(filename, "w")
	if err ~= nil then
		minetest.log("error", "[simplecrafting_lib] Could not save recipes to \"" .. filename .. "\"")
		return false
	end
	
	file:write("return {\n")
	for craft_type, recipe_list in orderedPairs(simplecrafting_lib.type) do	
		file:write("-- Craft Type " .. craft_type .. "--------------------------------------------------------\n[\"" .. craft_type .. "\"] = {\n")
		for out, recipe_list in orderedPairs(recipe_list.recipes_by_out) do
			file:write("-- Output: " .. out .. "\n")
			for _, recipe in ipairs(recipe_list) do
				write_recipe(file, recipe)
			end
		end
		file:write("},\n")
	end
	file:write("}\n")

	file:flush()
	file:close()
	return true
end


-- GraphML
---------------------------------------------------------------------------------

local output_edge = '<data key="edge_type">output</data>'
local input_edge = '<data key="edge_type">input</data>'
local returns_edge = '<data key="edge_type">returns</data>'

local item_node = '<data key="node_type">item</data>'
local recipe_node = '<data key="node_type">recipe</data>'

local graphml_header = 	'<?xml version="1.0" encoding="UTF-8"?>\n'
	..'<graphml xmlns="http://graphml.graphdrawing.org/xmlns" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://graphml.graphdrawing.org/xmlns http://graphml.graphdrawing.org/xmlns/1.0/graphml.xsd">\n'
	..'<key id="quantity" for="edge" attr.name="quantity" attr.type="int"/>\n'
	..'<key id="edge_type" for="edge" attr.name="edge_type" attr.type="string"/>\n'
	..'<key id="node_type" for="node" attr.name="node_type" attr.type="string"/>\n'
	..'<key id="craft_type" for="node" attr.name="craft_type" attr.type="string"/>\n'
	..'<key id="recipe_extra_data" for="node" attr.name="recipe_extra_data" attr.type="string"/>\n'
	..'<key id="item" for="node" attr.name="item" attr.type="string"/>\n'
	..'<key id="mod" for="node" attr.name="mod" attr.type="string"/>\n'

local write_data_graphml = function(file, datatype, data)
	file:write('<data key="'..datatype..'">'..data..'</data>')
end

local nodes_written
local write_item_graphml = function(file, craft_type, item)
	local node_id = item .. "_" .. craft_type
	if not nodes_written[node_id] then
		file:write('<node id="'..node_id..'">' .. item_node)
		write_data_graphml(file, "item", item)
		
		local colon_index = string.find(item, ":")
		if colon_index ~= nil then
			write_data_graphml(file, "mod", string.sub(item, 1, colon_index-1))
		end
		
		file:write('</node>\n')
		nodes_written[node_id] = true
	end
end

local edge_id = 0
local write_edge_graphml = function(file, source, target, edgetype, quantity)
	edge_id = edge_id + 1
	file:write('<edge id="e_'..tostring(edge_id).. '" source="' .. source .. '" target="' .. target ..'">')
	file:write(edgetype)
	file:write('<data key="quantity">'..tostring(quantity)..'</data>')
	file:write('</edge>\n')
end

local write_recipe_graphml = function(file, craft_type, id, recipe)
	local recipe_id = "recipe_"..craft_type.."_"..tostring(id)
	
	local extra_data = {}
	local has_extra_data = false
	for k, v in pairs(recipe) do
		if k ~= "output" and k ~= "input" and k ~= "returns" then
			extra_data[k] = v
			has_extra_data = true
		end
	end
	if has_extra_data then
		file:write('<node id="'..recipe_id..'">'..recipe_node..
			'<data key="craft_type">'..craft_type..'</data>'..
			'<data key="recipe_extra_data">'..minetest.serialize(extra_data)..'</data></node>\n') -- recipe node
	else
		file:write('<node id="'..recipe_id..'">'..recipe_node..
			'<data key="craft_type">'..craft_type..'</data>'..
			'</node>\n') -- recipe node
	end

	if recipe.output then
		local outitem = ItemStack(recipe.output)
		write_item_graphml(file, craft_type, outitem:get_name())
		write_edge_graphml(file, recipe_id, outitem:get_name().."_"..craft_type, output_edge, outitem:get_count())
	end
	
	if recipe.input then
		for initem, incount in pairs(recipe.input) do
			write_item_graphml(file, craft_type, initem)
			write_edge_graphml(file, initem.."_"..craft_type, recipe_id, input_edge, incount)
		end
	end
	if recipe.returns then
		for returnitem, returncount in pairs(recipe.returns) do
			write_item_graphml(file, craft_type, returnitem)
			write_edge_graphml(file, recipe_id, returnitem.."_"..craft_type, returns_edge, returncount)
		end
	end
end


local current_element = {}

local recipes
local item_ids
local parse_error

local SLAXML = dofile(minetest.get_modpath(minetest.get_current_modname()) .. "/slaxml/slaxml.lua")
local parser = SLAXML:parser{
	startElement = function(name,nsURI,nsPrefix) -- When "<foo" or <x:foo is seen
		if parse_error then return end
		if name == "node" or name == "edge" then
			current_element = {}
		end
		current_element.type = name
	end,
	attribute = function(name,value,nsURI,nsPrefix) -- attribute found on current element
		if parse_error then return end
		if current_element.type == "node" then
			if name == "id" then
				current_element.id = value
			end
		elseif current_element.type == "edge" then
			if name == "id" then
				current_element.id = value
			elseif name == "target" then
				current_element.target = value
			elseif name == "source" then
				current_element.source = value
			end				
		elseif current_element.type == "data" and name == "key" then
			current_element.key = value
		end
	end,
	closeElement = function(name,nsURI) -- When "</foo>" or </x:foo> or "/>" is seen
		if parse_error then return end
		if name == "node" or name == "edge" then
			if not current_element.id then parse_error = name .. " " .. dump(current_element) .. " did not have an id" return end
			
			if current_element.node_type == "item" then
				if not current_element.item then parse_error = "item node " .. current_element.id .. " had no item data" return end

				item_ids[current_element.id] = current_element.item

			elseif current_element.node_type == "recipe" then
				local new_recipe = {craft_type=current_element.craft_type}
				if current_element.recipe_extra_data then
					local extra_data = minetest.deserialize(current_element.recipe_extra_data)
					for k, v in pairs(extra_data) do
						new_recipe[k] = v
					end
				end
				recipes[current_element.id] = new_recipe
				
			elseif current_element.edge_type == "input" then
				local current_recipe = recipes[current_element.target]
				if not current_recipe then parse_error = "input edge " .. current_element.id .. " could not find target " .. current_element.target return end
				local item = item_ids[current_element.source]
				if not item then parse_error = "input edge " .. current_element.id .. " could not find source " .. current_element.source return end
				
				current_recipe.input = current_recipe.input or {}
				current_recipe.input[item] = current_element.quantity
				
			elseif current_element.edge_type == "output" then
				local current_recipe = recipes[current_element.source]
				if not current_recipe then parse_error = "output edge " .. current_element.id .. " could not find source " .. current_element.source return end
				local item = item_ids[current_element.target]
				if not item then parse_error = "output edge " .. current_element.id .. " could not find target " .. current_element.target return end
				
				current_recipe.output = item.." "..tostring(current_element.quantity) --ItemStack({name=item, count=current_element.quantity})
				
			elseif current_element.edge_type == "returns" then
				local current_recipe = recipes[current_element.source]
				if not current_recipe then parse_error = "returns edge " .. current_element.id .. " could not find source " .. current_element.source return end
				local item = item_ids[current_element.target]
				if not item then parse_error = "returns edge " .. current_element.id .. " could not find target " .. current_element.target return end

				current_recipe.returns = current_recipe.returns or {}
				current_recipe.returns[item] = current_element.quantity			
			end
			current_element = {}
		end
	end,
	text = function(text,cdata) -- text and CDATA nodes (cdata is true for cdata nodes)
		if parse_error then return end
		if current_element.type == "data" then
			if current_element.key == "quantity" then
				local quantity = tonumber(text)
				if not quantity then parse_error = "failed to parse quantity in " .. dump(current_element) return end	
				current_element[current_element.key] = quantity
			else
				current_element[current_element.key] = text
			end
		end	
	end,
}
local parse_graphml_recipes = function(xml)
	recipes = {}
	item_ids = {}
	parse_error = nil
	
	parser:parse(xml,{stripWhitespace=true})
	
	if parse_error then return end
	
	local returns = recipes
	
	item_ids = nil
	recipes = nil
	return returns
end

local save_recipes_graphml = function(name)
	local path = minetest.get_worldpath()
	local filename = path .. "/" .. name .. ".graphml"
	local file, err = io.open(filename, "w")
	if err ~= nil then
		minetest.log("error", "[simplecrafting_lib] Could not save recipes to \"" .. filename .. "\"")
		return false
	end

	file:write(graphml_header)
	
	nodes_written = {}
	for craft_type, recipe_list in pairs(simplecrafting_lib.type) do
		file:write('<graph id="'..craft_type..'" edgedefault="directed">\n')
		for id, recipe in pairs(recipe_list.recipes) do
			write_recipe_graphml(file, craft_type, id, recipe)
		end
		file:write('</graph>\n')
	end	
	nodes_written = nil
	
	file:write('</graphml>')
	
	file:flush()
	file:close()

	return true
end

local read_recipes_graphml = function(name)
	local path = minetest.get_worldpath()
	local filename = path .. "/" .. name .. ".graphml"

	local file, err = io.open(filename, "r")
	if err ~= nil then
		minetest.log("error", "[simplecrafting_lib] Could not read recipes from \"" .. filename .. "\"")
		return false
	end
	local myxml = file:read('*all')
	myxml = parse_graphml_recipes(myxml)
	if parse_error then
		minetest.log("error", "Failed to parse graphml " .. filename .. " with error: " .. parse_error)
		parse_error = nil
		return false
	end		
		
	return myxml
end

-------------------------------------------------------------

-- registers all recipes in the provided filename, which is usually a file generated by save_recipes and then perhaps modified by the developer.
local load_recipes = function(param)
	local path = minetest.get_worldpath()
	local filename = path .. "/" .. param .. ".lua"
	local new_recipes = loadfile(filename)
	if new_recipes == nil then
		minetest.log("error", "[simplecrafting_lib] Could not read recipes from \"" .. filename .. "\"")
		return false
	end
	new_recipes = new_recipes()	
	
	for crafting_type, recipes in pairs(new_recipes) do
		for _, recipe in pairs(recipes) do
			simplecrafting_lib.register(crafting_type, recipe)
		end	
	end	
	return true
end

-- What the function name says it does
local get_recipes_that_are_in_first_recipe_list_but_not_in_second_recipe_list = function(first_recipe_list, second_recipe_list)
	if first_recipe_list == nil then
		return nil
	elseif second_recipe_list == nil then
		return first_recipe_list
	end
	
	local returns

	for _, first_recipe in pairs(first_recipe_list) do
		local found = false
		for _, second_recipe in pairs(second_recipe_list) do
			if simplecrafting_lib.recipe_equals(first_recipe, second_recipe) then
				found = true
				break
			end
		end
		if found ~= true then
			returns = returns or {}
			table.insert(returns, first_recipe)
		end
	end
	
	return returns
end

-- Used in diff_recipes for writing lists of recipes
local write_recipe_lists = function(file, recipe_lists)
	for craft_type, recipe_list in orderedPairs(recipe_lists) do	
		file:write("-- Craft Type " .. craft_type .. "--------------------------------------------------------\n[\"" .. craft_type .. "\"] = {\n")
		for _, recipe in ipairs(recipe_list) do
			write_recipe(file, recipe)
		end
		file:write("},\n")
	end
end

-- compares the recipes in the infile (of the form written by save_recipes) to the recipes in the existing crafting system, and outputs differences to outfile
local diff_recipes = function(infile, outfile)
	local path = minetest.get_worldpath()
	local filename = path .. "/" .. infile .. ".lua"
	local new_recipes = loadfile(filename)
	if new_recipes == nil then
		minetest.log("error", "[simplecrafting_lib] Could not read recipes from \"" .. filename .. "\"")
		return false
	end
	new_recipes = new_recipes()
	
	local new_only_recipes = {}
	local existing_only_recipes = {}
	
	for craft_type, recipe_lists in pairs(simplecrafting_lib.type) do
		if new_recipes[craft_type] ~= nil then
			new_only_recipes[craft_type] = get_recipes_that_are_in_first_recipe_list_but_not_in_second_recipe_list(new_recipes[craft_type], recipe_lists.recipes)
		else
			existing_only_recipes[craft_type] = recipe_lists.recipes
		end
	end
	for craft_type, recipe_lists in pairs(new_recipes) do
		local existing_recipes = simplecrafting_lib.type[craft_type]
		if existing_recipes ~= nil then
			existing_only_recipes[craft_type] = get_recipes_that_are_in_first_recipe_list_but_not_in_second_recipe_list(existing_recipes.recipes, recipe_lists)
		else
			new_only_recipes[craft_type] = recipe_lists
		end
	end
	
	filename = path .. "/" .. outfile .. ".txt"
	local file, err = io.open(filename, "w")
	if err ~= nil then
		minetest.log("error", "[simplecrafting_lib] Could not save recipe diffs to \"" .. filename .. "\"")
		return false
	end
		
	file:write("-- Recipes found only in the external file:\n--------------------------------------------------------\n")
	write_recipe_lists(file, new_only_recipes)
	file:write("\n")

	file:write("-- Recipes found only in the existing crafting database:\n--------------------------------------------------------\n")
	write_recipe_lists(file, existing_only_recipes)
	file:write("\n")
	
	file:flush()
	file:close()
	
	return true
end

minetest.register_chatcommand("saverecipes", {
	params = "<file>",
	description = "Save the current recipes to \"(world folder)/<file>.lua\"",
	func = function(name, param)
		if not minetest.check_player_privs(name, {server = true}) then
			minetest.chat_send_player(name, "You need the \"server\" priviledge to use this command.", false)
			return
		end
		
		if param == "" then
			minetest.chat_send_player(name, "Invalid usage, filename parameter needed", false)
			return
		end
		
		if save_recipes(param) then
			minetest.chat_send_player(name, "Recipes saved", false)
		else
			minetest.chat_send_player(name, "Failed to save recipes", false)
		end
	end,
})

minetest.register_chatcommand("saverecipesgraph", {
	params = "<file>",
	description = "Save the current recipes to \"(world folder)/<file>.graphml\"",
	func = function(name, param)
		if not minetest.check_player_privs(name, {server = true}) then
			minetest.chat_send_player(name, "You need the \"server\" priviledge to use this command.", false)
			return
		end
		
		if param == "" then
			minetest.chat_send_player(name, "Invalid usage, filename parameter needed", false)
			return
		end
		
		if save_recipes_graphml(param) then
			minetest.chat_send_player(name, "Recipes saved", false)
		else
			minetest.chat_send_player(name, "Failed to save recipes", false)
		end
	end,
})

minetest.register_chatcommand("readrecipesgraph", {
	params = "<file>",
	description = "Read the current recipes from \"(world folder)/<file>.graphml\"",
	func = function(name, param)
		if not minetest.check_player_privs(name, {server = true}) then
			minetest.chat_send_player(name, "You need the \"server\" priviledge to use this command.", false)
			return
		end
		
		if param == "" then
			minetest.chat_send_player(name, "Invalid usage, filename parameter needed", false)
			return
		end
		
		local read_recipes = read_recipes_graphml(param)		
		if read_recipes then
			for _, recipe in pairs(read_recipes) do
				local craft_type = recipe.craft_type
				recipe.craft_type = nil
				simplecrafting_lib.register(craft_type, recipe)				
			end
		
			minetest.chat_send_player(name, "Recipes read", false)
		else
			minetest.chat_send_player(name, "Failed to read recipes", false)
		end
	end,
})

minetest.register_chatcommand("clearrecipes", {
	params = "",
	description = "Clear all recipes from simplecrafting_lib",
	func = function(name, param)
		if not minetest.check_player_privs(name, {server = true}) then
			minetest.chat_send_player(name, "You need the \"server\" priviledge to use this command.", false)
			return
		end
		simplecrafting_lib.type = {}
		minetest.chat_send_player(name, "Recipes cleared", false)
	end,
})

minetest.register_chatcommand("loadrecipes", {
	params="<file>",
	description="Clear recipes and load replacements from \"(world folder)/<file>.lua\"",
	func = function(name, param)
		if not minetest.check_player_privs(name, {server = true}) then
			minetest.chat_send_player(name, "You need the \"server\" priviledge to use this command.", false)
			return
		end

		if param == "" then
			minetest.chat_send_player(name, "Invalid usage, filename parameter needed", false)
			return
		end
		
		if load_recipes(param) then		
			minetest.chat_send_player(name, "Recipes loaded", false)
		else
			minetest.chat_send_player(name, "Failed to load recipes", false)
		end
	end,
})

function split(inputstr, seperator)
	if seperator == nil then
		seperator = "%s"
	end
	local out={}
	local i=1
	for substring in string.gmatch(inputstr, "([^"..seperator.."]+)") do
		out[i] = substring
		i = i + 1
	end
	return out
end

minetest.register_chatcommand("diffrecipes", {
	params="<infile> <outfile>",
	description="Compares existing recipe data to the data in \"(world folder)/<infile>.lua\", outputting the differences to \"(world folder)/<outfile>.txt\"",
	func = function(name, param)
		if not minetest.check_player_privs(name, {server = true}) then
			minetest.chat_send_player(name, "You need the \"server\" priviledge to use this command.", false)
			return
		end

		local params = split(param)
		if #params ~= 2 then
			minetest.chat_send_player(name, "Invalid usage, two filename parameters separted by a space are needed", false)
			return
		end
		
		if diff_recipes(params[1], params[2]) then
			minetest.chat_send_player(name, "Recipes diffed", false)
		else
			minetest.chat_send_player(name, "Failed to diff recipes", false)
		end
	end,
})