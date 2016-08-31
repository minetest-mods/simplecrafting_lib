local function create_recipe(legacy)
	local recipe = {}
	local items = legacy.items
	local stack = ItemStack(legacy.output)
	local output = stack:get_name()
	local nout = stack:get_count()
	recipe.output = {[output] = nout}
	recipe.input = {}
	for i=1,9 do
		if items[i] and items[i] ~= "" then
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
			elseif v.method == "cooking" then
				local legacy = {input={},output={}}
				legacy.output[v.output] = 1
				legacy.input[v.input[1]] = 1
				-- TODO correct detection of time - this is always 3
				legacy.time = v.time or 3
				crafting.register("furnace",legacy)
			-- TODO detection of fuels
			end
		end
	end
end

local register_craft = minetest.register_craft
minetest.register_craft = function(recipe)
	if not recipe.type or recipe.type == "shapeless" then
		local legacy = {items={},output=recipe.output}
		if not recipe.type then
			for _,row in ipairs(recipe.recipe) do
				for _,item in ipairs(row) do
					legacy.items[#legacy.items+1] = item
				end
			end
		elseif recipe.type == "shapeless" then
			legacy.items = recipe.recipe
		end
		create_recipe(legacy)
	elseif recipe.type == "cooking" then
		local legacy = {input={},output={}}
		legacy.output[recipe.output] = 1
		legacy.input[recipe.recipe] = 1
		legacy.time = recipe.cooktime or 3
		crafting.register("furnace",legacy)
	elseif recipe.type == "fuel" then
		local legacy = {}
		legacy.name = recipe.recipe
		legacy.burntime = recipe.burntime
		legacy.grade = 1
		crafting.register("fuel",legacy)
	end
	return register_craft(recipe)
end


minetest.register_craft({
	output = "crafting:table",
	recipe = {
		{"group:wood","group:wood",""},
		{"group:wood","group:wood",""},
		{"","",""},
	},
})
minetest.register_craft({
	output = "crafting:furnace",
	recipe = {
		{"default:stone","default:stone","default:stone"},
		{"default:stone","default:coal_lump","default:stone"},
		{"default:stone","default:stone","default:stone"},
	},
})
