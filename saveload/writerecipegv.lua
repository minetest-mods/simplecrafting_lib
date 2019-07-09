local write_item_gv = function(file, item, node_lines, nodes_written)
	local itemtag = item:gsub(":", "_"):gsub(",","_")
	if nodes_written[itemtag] then
		return itemtag
	end
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
		color = simplecrafting_lib.get_key_color(mod)
	end
	table.insert(node_lines, '\t'..itemtag..' [label="'..item..'",style="filled",fillcolor="'..color..'",shape="box"]')
	nodes_written[itemtag] = true
	return itemtag
end

local write_recipe_gv = function(file, craft_type, id, recipe, nodes_written, node_lines, recipe_lines)
	local recipe_id = "recipe_"..craft_type.."_"..tostring(id)
	
	local extra_data = {}
	local has_extra_data = false
	for k, v in pairs(recipe) do
		if type(v) == "function" then
			minetest.log("error", "[simplecrafting_lib] recipe write: " .. key .. "'s value is a function")
		elseif k ~= "output" and k ~= "input" and k ~= "returns" then
			extra_data[k] = v
			has_extra_data = true
		end
	end
	
	table.insert(recipe_lines, '\t'..recipe_id..' [label="'..craft_type..'",style="filled",fillcolor="#FFCC00",shape="diamond"]') -- recipe node
	
	if has_extra_data then
		--TODO
		--write_data_gv(file, "recipe_extra_data", minetest.serialize(extra_data))
	end
	
	if recipe.input then
		for initem, incount in pairs(recipe.input) do
			local itemtag = write_item_gv(file, initem, node_lines, nodes_written)
			table.insert(recipe_lines, '\t'..itemtag..' -> '..recipe_id..' [label="'..tostring(incount)..'"]')
		end
	end
	
	if recipe.returns then
		for returnitem, returncount in pairs(recipe.returns) do
			local itemtag = write_item_gv(file, returnitem, node_lines, nodes_written)
			table.insert(recipe_lines, '\t'..recipe_id..' -> '..itemtag..' [label="'..tostring(returncount)..'",arrowhead="onormal",color="#888888"]')
		end
	end

	if recipe.output then
		local output = ItemStack(recipe.output)
		local outitem = output:get_name()
		local itemtag = write_item_gv(file, outitem, node_lines, nodes_written)
		table.insert(recipe_lines, '\t'..recipe_id..' -> '..itemtag..' [label="'..tostring(output:get_count())..'"]')
	end	

	table.insert(recipe_lines, "") -- blank line between recipes
	
end

return function(file, recipes, recipe_filter, show_unused)

	for craft_type, recipe_list in pairs(recipes) do
		local items_written = {} -- tracks which items have already been written
		local node_lines = {} -- gather up all the unique item node definitions
		local recipe_lines = {} -- recipe nodes and recipes bundled together

		file:write('digraph ' .. craft_type .. '{\n')
		for id, recipe in pairs(recipe_list.recipes) do
			if recipe_filter.filter(recipe) then
				write_recipe_gv(file, craft_type, id, recipe, items_written, node_lines, recipe_lines)
			end
		end
		
		table.sort(node_lines) -- don't sort recipe_lines, those have an actual order to them
		
		file:write(table.concat(node_lines, "\n"))
		file:write("\n\n")
		file:write(table.concat(recipe_lines, "\n"))		
		file:write('}\n')
	end

	simplecrafting_lib.save_key_colors()
	
	file:flush()
	file:close()
end