local function create_recipe(legacy)
	local recipe = {}
	local items = legacy.items
	local stack = ItemStack(legacy.output)
	local output = stack:get_name()
	local nout = stack:get_count()
	recipe.output = {[output] = nout}
	recipe.input = {}
	for i=1,9 do
		if items[i] then
			recipe.input[items[i]] = (recipe.input[items[i]] or 0) + 1
		end
	end
	crafting.register("table",recipe)
end

for item,_ in pairs(minetest.registered_items) do
	local crafts = minetest.get_all_craft_recipes(item)
	if crafts then
		for i,v in ipairs(crafts) do
			if v.method == "normal" then
				create_recipe(v,item)
			end
		end
	end
end

local register_craft = minetest.register_craft
minetest.register_craft = function(recipe)
	if not recipe.type or recipe.type == "shapeless" then
		local legacy = {items={},output=recipe.output}
		if not recipe.type then
			for _,v in ipairs(recipe.recipe) do
				for _,item in ipairs(v) do
					legacy.items[item] = (legacy.items[item] or 0) + 1
				end
			end
		elseif recipe.type == "shapeless" then
			for _,item in ipairs(recipe.recipe) do
				legacy.items[item] = (legacy.items[item] or 0) + 1
			end
		end
	end
	return register_craft(recipe)
end
