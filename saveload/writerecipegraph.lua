local graphml_header = 	'<?xml version="1.0" encoding="UTF-8"?>\n'
	..'<graphml xmlns="http://graphml.graphdrawing.org/xmlns" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://graphml.graphdrawing.org/xmlns http://graphml.graphdrawing.org/xmlns/1.0/graphml.xsd">\n'
	..'<key id="quantity" for="edge" attr.name="quantity" attr.type="int"/>\n'
	..'<key id="edge_type" for="edge" attr.name="edge_type" attr.type="string"/>\n'
	..'<key id="node_type" for="node" attr.name="node_type" attr.type="string"/>\n'
	..'<key id="craft_type" for="node" attr.name="craft_type" attr.type="string"/>\n'
	..'<key id="recipe_extra_data" for="node" attr.name="recipe_extra_data" attr.type="string"/>\n'
	..'<key id="item" for="node" attr.name="item" attr.type="string"/>\n'
	..'<key id="mod" for="node" attr.name="mod" attr.type="string"/>\n'

local nodes_written
local items_written
local edge_id = 0

local write_data_graphml = function(file, datatype, data)
	file:write('<data key="'..datatype..'">'..data..'</data>')
end

local write_item_graphml = function(file, craft_type, item)
	local node_id = item .. "_" .. craft_type -- craft type is added to the id to separate graphs
	if not nodes_written[node_id] then
		file:write('<node id="'..node_id..'">')
		
		local colon_index = string.find(item, ":")
		if colon_index == nil then
			item = "group:" .. item
			colon_index = 6
		end
		
		write_data_graphml(file, "node_type", "item")
		write_data_graphml(file, "item", item)
		write_data_graphml(file, "mod", string.sub(item, 1, colon_index-1))
		file:write('</node>\n')
		nodes_written[node_id] = true
		items_written[item] = true
	end
end

local write_edge_graphml = function(file, source, target, edgetype, quantity)
	edge_id = edge_id + 1
	file:write('<edge id="e_'..tostring(edge_id).. '" source="' .. source .. '" target="' .. target ..'">')
	write_data_graphml(file, "edge_type", edgetype)
	write_data_graphml(file, "quantity", tostring(quantity))
	
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
	file:write('<node id="'..recipe_id..'">')
	write_data_graphml(file, "node_type", "recipe")
	write_data_graphml(file, "craft_type", craft_type)
	if has_extra_data then
		write_data_graphml(file, "recipe_extra_data", minetest.serialize(extra_data))
	end
	file:write('</node>\n') -- recipe node

	if recipe.output then
		local outitem = ItemStack(recipe.output)
		write_item_graphml(file, craft_type, outitem:get_name())
		write_edge_graphml(file, recipe_id, outitem:get_name().."_"..craft_type, "output", outitem:get_count())
	end
	
	if recipe.input then
		for initem, incount in pairs(recipe.input) do
			write_item_graphml(file, craft_type, initem)
			write_edge_graphml(file, initem.."_"..craft_type, recipe_id, "input", incount)
		end
	end
	if recipe.returns then
		for returnitem, returncount in pairs(recipe.returns) do
			write_item_graphml(file, craft_type, returnitem)
			write_edge_graphml(file, recipe_id, returnitem.."_"..craft_type, "returns", returncount)
		end
	end
end

return function(file, recipes, recipe_filter, show_unused)
	file:write(graphml_header)
	
	nodes_written = {}
	items_written = {}
	for craft_type, recipe_list in pairs(recipes) do
		file:write('<graph id="'..craft_type..'" edgedefault="directed">\n')
		for id, recipe in pairs(recipe_list.recipes) do
			if recipe_filter.filter(recipe) then
				write_recipe_graphml(file, craft_type, id, recipe)
			end
		end
		file:write('</graph>\n')
	end
	
	-- Write out nodes for everything that hasn't already had a node written for it, for convenience of hand-crafting new recipes
	if show_unused then
		items_written[""] = true
		items_written["ignore"] = true
		items_written["unknown"] = true
		items_written["air"] = true
		items_written["default:cloud"] = true
		items_written["doors:hidden"] = true
		for item, item_def in pairs(minetest.registered_items) do
			if not items_written[item] then
				write_item_graphml(file, "", item)
			end
		end
	end
	
	nodes_written = nil
	items_written = nil
	
	file:write('</graphml>')
	
	file:flush()
	file:close()
end