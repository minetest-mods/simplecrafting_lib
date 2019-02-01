local current_element = {}

local key_ids
local recipes
local item_ids
local parse_error
local yEd_detected

local SLAXML = dofile(minetest.get_modpath(minetest.get_current_modname()) .. "/saveload/slaxml/slaxml.lua")
local parser = SLAXML:parser{

	startElement = function(name,nsURI,nsPrefix) -- When "<foo" or <x:foo is seen
		if parse_error then return end
		current_element.type = name
	end,
	
	attribute = function(name,value,nsURI,nsPrefix) -- attribute found on current element
		if parse_error then return end
		if current_element.type == "key" then
			current_element[name] = value
		elseif current_element.type == "node" then
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
		elseif current_element.type == "graphml" and name == "xmlns:yed" then
			yEd_detected = true
		elseif current_element.type == "data" and name == "key" then
			current_element.key = key_ids[value]
		elseif current_element.type == "Shape" and name == "type" then -- A yEd node's shape, record this as fallback data in case the actual data isn't set
			current_element.nodeshape = value
		elseif current_element.type == "Arrows" and name == "target" then -- A yEd edge's arrow type, use as a fallback in case edge type "returns" isn't set
			current_element.arrowtarget = value
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
		elseif current_element.type == "NodeLabel" then -- This is a yEd node, record its label as a source of fallback data if the user's been messing about with the graph and didn't set the actual data values
			current_element.nodelabel = text
		elseif current_element.type == "EdgeLabel" then -- This is a yEd edge, record its label etc
			current_element.edgelabel = tonumber(text)
		end
	end,

	closeElement = function(name,nsURI) -- When "</foo>" or </x:foo> or "/>" is seen
		if parse_error then return end
		if name == "node" then
		
			if yEd_detected and current_element.node_type == nil and current_element.nodelabel ~= nil then -- Fall back to yEd data
				if current_element.nodeshape == "roundedrectangle" then
					--current_element.node_type = "item" -- don't bother to set this, we don't care about anything other than setting the item id
					item_ids[current_element.id] = current_element.nodelabel
				elseif current_element.nodeshape == "diamond" then
					current_element.node_type = "recipe"
					current_element.craft_type = current_element.nodelabel
				end
			end
		
			if current_element.node_type == "item" then
				if not current_element.id then parse_error = name .. " " .. dump(current_element) .. " did not have an id" return end
				if not current_element.item then parse_error = "item node " .. current_element.id .. " had no item data" return end

				item_ids[current_element.id] = current_element.item

			elseif current_element.node_type == "recipe" then
				if not current_element.id then parse_error = name .. " " .. dump(current_element) .. " did not have an id" return end
				local new_recipe = {craft_type=current_element.craft_type}
				if current_element.recipe_extra_data then
					local extra_data = minetest.deserialize(current_element.recipe_extra_data)
					for k, v in pairs(extra_data) do
						new_recipe[k] = v
					end
				end
				recipes[current_element.id] = new_recipe
			end
			current_element = {}

		elseif name == "edge" then

			if not current_element.id then parse_error = name .. " " .. dump(current_element) .. " did not have an id" return end
			if not current_element.target then parse_error = name .. " " .. dump(current_element) .. " did not have a target" return end
			if not current_element.source then parse_error = name .. " " .. dump(current_element) .. " did not have a source" return end
			
			if yEd_detected then -- yEd fallback
				if not current_element.quantity and current_element.edgelabel then
					current_element.quantity = current_element.edgelabel
				end
				if not current_element.edge_type and current_element.targetarrow == "white_delta" then
					current_element.edge_type = "returns"
				end
			end
				
			if not current_element.quantity then parse_error = name .. " " .. dump(current_element) .. " did not have a quantity" return end

			local item_target = item_ids[current_element.target]
			local item_source = item_ids[current_element.source]
			local recipe_target = recipes[current_element.target]
			local recipe_source = recipes[current_element.source]
		
			if item_source and recipe_target then
				recipe_target.input = recipe_target.input or {}
				recipe_target.input[item_source] = current_element.quantity
			elseif current_element.edge_type == "output" then
				if not recipe_source then parse_error = name .. " " .. dump(current_element) .. " output did not have a resolvable source" return end
				recipe_source.output = item_target.." "..tostring(current_element.quantity) --ItemStack({name=item, count=current_element.quantity})
			elseif recipe_source and item_target then
				recipe_source.returns = recipe_source.returns or {}
				recipe_source.returns[item_target] = current_element.quantity
			else
				parse_error = name .. " " .. dump(current_element) .. " did not have a resolvable target or source" return
			end
			current_element = {}

		elseif name == "key" then

			if not current_element.id then parse_error = name .. " " .. dump(current_element) .. " did not have an id" return end
			key_ids[current_element.id] = current_element["attr.name"]			
			current_element = {}
		end
	end,
}

return function(xml)
	recipes = {}
	item_ids = {}
	key_ids = {}
	parse_error = nil
	yEd_detected = false
	
	parser:parse(xml,{stripWhitespace=true})
	
	for _, recipe in pairs(recipes) do
		-- If there's no output and one "returns", make the returns into an output.
		if recipe.output == nil then
			if recipe.returns then
				local count = 0
				for k, v in pairs(recipe.returns) do
					count = count + 1
				end
				if count == 1 then
					local item, count = next(recipe.returns)
					recipe.output = item .. " " .. tostring(count)
					recipe.returns  = nil
				else
					if not parse_error then
						parse_error = ""
					else
						parse_error = parse_error .. "/n"
					end
					parse_error = parse_error .. "Recipe with no output and multiple returns detected, cannot guess output: " .. dump(recipe)
				end
			end
		end
	end
	
	local returns = recipes
	
	item_ids = nil
	recipes = nil
	key_ids = nil
	return returns, parse_error
end