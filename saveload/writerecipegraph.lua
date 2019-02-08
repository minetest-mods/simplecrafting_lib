local graphml_header = 	'<?xml version="1.0" encoding="UTF-8"?>\n'
	..'<graphml xmlns="http://graphml.graphdrawing.org/xmlns" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
	..'xmlns:y="http://www.yworks.com/xml/graphml" xmlns:yed="http://www.yworks.com/xml/yed/3" xsi:schemaLocation="http://graphml.graphdrawing.org/xmlns http://graphml.graphdrawing.org/xmlns/1.0/graphml.xsd http://www.yworks.com/xml/schema/graphml/1.1/ygraphml.xsd"'
	..'>\n'
	..'<key id="quantity" for="edge" attr.name="quantity" attr.type="int"/>\n'
	..'<key id="edge_type" for="edge" attr.name="edge_type" attr.type="string"/>\n'
	..'<key id="node_type" for="node" attr.name="node_type" attr.type="string"/>\n'
	..'<key id="craft_type" for="node" attr.name="craft_type" attr.type="string"/>\n'
	..'<key id="recipe_extra_data" for="node" attr.name="recipe_extra_data" attr.type="string"/>\n'
	..'<key id="item" for="node" attr.name="item" attr.type="string"/>\n'
	..'<key id="mod" for="node" attr.name="mod" attr.type="string"/>\n'
	..'<key id="nodegraphics" for="node" yfiles.type="nodegraphics"/>\n' --yEd
	..'<key id="edgegraphics" for="edge" yfiles.type="edgegraphics"/>\n' --yEd

local nodes_written
local items_written
local edge_id = 0

local write_new_color_file = false
local last_assigned_hue = math.random()
local last_assigned_saturation = math.random()
local golden_ratio_conjugate = 0.618033988749895 -- for spreading out the random colours more evenly, reducing clustering

local mod_color_map
local path = minetest.get_worldpath()
local color_filename = path .. "/simplecrafting_mod_colors.lua"
local color_file = loadfile(color_filename)
if color_file ~= nil then
	mod_color_map = color_file()
else
	mod_color_map = {}
end

-- HSV values in [0..1[
-- returns {r, g, b} values from 0 to 255
local hsv_to_rgb = function(h, s, v)
	local h_i = math.floor(h*6)
	local f = h*6 - h_i
	local p = v * (1 - s)
	local q = v * (1 - f*s)
	local t = v * (1 - (1 - f) * s)
	local r, g, b
	if h_i==0 then r, g, b = v, t, p
	elseif h_i==1 then r, g, b = q, v, p
	elseif h_i==2 then r, g, b = p, v, t
	elseif h_i==3 then r, g, b = p, q, v
	elseif h_i==4 then r, g, b = t, p, v
	elseif h_i==5 then r, g, b = v, p, q
	end
	return {math.floor(r*255), math.floor(g*255), math.floor(b*255)}
end

local write_data_graphml = function(file, datatype, data)
	file:write('<data key="'..datatype..'">'..data..'</data>')
end

local write_item_graphml = function(file, craft_type, item)
	local node_id = item .. "_" .. craft_type -- craft type is added to the id to separate graphs
	if not nodes_written[node_id] then
		file:write('<node id="'..node_id..'">')
		
		local color
		local mod
		local colon_index = string.find(item, ":")
		if colon_index == nil then
			item = "group:" .. item
			colon_index = 6
			color = "#C0C0C0"
			mod = "group"
		else
			mod = string.sub(item, 1, colon_index-1)
			if not mod_color_map[mod] then
				last_assigned_hue = last_assigned_hue + golden_ratio_conjugate
				last_assigned_hue = last_assigned_hue % 1
				last_assigned_saturation = last_assigned_saturation + golden_ratio_conjugate
				last_assigned_saturation = last_assigned_saturation % 1
				local color_vec = hsv_to_rgb(last_assigned_hue, last_assigned_saturation/2 + 0.5, 1)
				color = "#"..string.format('%02X', color_vec[1])..string.format('%02X', color_vec[2])..string.format('%02X', color_vec[3])
				mod_color_map[mod] = color
				write_new_color_file = true
			else
				color = mod_color_map[mod]
			end			
		end
		
		write_data_graphml(file, "node_type", "item")
		write_data_graphml(file, "item", item)
		write_data_graphml(file, "mod", mod)
		
		--yEd
		write_data_graphml(file, "nodegraphics", '<y:ShapeNode><y:Geometry height="30.0" width="60.0"/><y:Fill color="'
			..color
			..'" transparent="false"/><y:BorderStyle color="#000000" raised="false" type="line" width="1.0"/>'
			..'<y:NodeLabel alignment="center" autoSizePolicy="node_width" configuration="CroppingLabel" fontFamily="Dialog" fontSize="8" fontStyle="plain" hasBackgroundColor="false" hasLineColor="false" height="26.125" horizontalTextPosition="center" iconTextGap="4" modelName="internal" modelPosition="c" textColor="#000000" verticalTextPosition="bottom" visible="true" width="60.0" xml:space="preserve">'
			..item
			..'</y:NodeLabel><y:Shape type="roundrectangle"/></y:ShapeNode>')		
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
	
	local targetarrow = "delta"
	if edgetype == "returns" then
		targetarrow = "white_delta"
	end
	
	--yEd
	write_data_graphml(file, "edgegraphics", '<y:PolyLineEdge><y:Path sx="0.0" sy="0.0" tx="0.0" ty="0.0"/><y:LineStyle color="#000000" type="line" width="1.0"/><y:Arrows source="none" target="'
		..targetarrow
		..'"/><y:EdgeLabel alignment="center" backgroundColor="#FFFFFF" distance="2.0" fontFamily="Dialog" fontSize="12" fontStyle="plain" horizontalTextPosition="center" iconTextGap="4" lineColor="#000000" modelName="centered" modelPosition="center" preferredPlacement="anywhere" ratio="0.5" textColor="#000000" verticalTextPosition="bottom" visible="true" xml:space="preserve">'
		..tostring(quantity)
		..'<y:PreferredPlacementDescriptor angle="0.0" angleOffsetOnRightSide="0" angleReference="absolute" angleRotationOnRightSide="co" distance="-1.0" frozen="true" placement="anywhere" side="anywhere" sideReference="relative_to_edge_flow"/></y:EdgeLabel><y:BendStyle smoothed="true"/></y:PolyLineEdge>')
		
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
	
	--yEd
	write_data_graphml(file, "nodegraphics", '<y:ShapeNode><y:Geometry height="30.0" width="30.0"/><y:Fill color="#FFCC00" transparent="false"/>'
		..'<y:BorderStyle color="#000000" raised="false" type="line" width="1.0"/>'
		..'<y:NodeLabel alignment="center" autoSizePolicy="node_width" fontFamily="Dialog" fontSize="10" fontStyle="plain" hasBackgroundColor="false" hasLineColor="false" horizontalTextPosition="center" iconTextGap="4" modelName="internal" modelPosition="c" textColor="#000000" verticalTextPosition="bottom" visible="true" width="30.0" xml:space="preserve">'
		..craft_type
		..'</y:NodeLabel><y:Shape type="diamond"/></y:ShapeNode>')
	
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
	
	if write_new_color_file then
		local color_file, err = io.open(color_filename, "w")
		if err == nil then
			color_file:write("return "..dump(mod_color_map))
			color_file:flush()
			color_file:close()		
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