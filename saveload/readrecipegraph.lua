local current_element = {}

local key_ids
local recipes
local item_ids
local parse_error

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
		elseif current_element.type == "data" and name == "key" then
			current_element.key = key_ids[value]
		end
	end,
	closeElement = function(name,nsURI) -- When "</foo>" or </x:foo> or "/>" is seen
		if parse_error then return end
		if name == "node" then
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

return function(xml)
	recipes = {}
	item_ids = {}
	key_ids = {}
	parse_error = nil
	
	parser:parse(xml,{stripWhitespace=true})
	
	local returns = recipes
	
	item_ids = nil
	recipes = nil
	key_ids = nil
	return returns, parse_error
end