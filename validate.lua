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
					.. table.concat(invalid_items, " ") .. "\nRecipe removed.")
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

minetest.after(0, validate)