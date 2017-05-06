local clear_default_crafting = crafting.config.clear_default_crafting

local function create_recipe(legacy)
	local items = legacy.items
	local has_items = false
	for _, item in pairs(items) do
		has_items = true
		break
	end
	if not has_items then return end
	local recipe = {}
	local stack = ItemStack(legacy.output)
	local output = stack:get_name()
	local nout = stack:get_count()
	recipe.output = {[output] = nout}
	recipe.input = {}
	recipe.returns = legacy.returns
	for _, item in pairs(items) do
		if item ~= "" then
			recipe.input[item] = (recipe.input[item] or 0) + 1
		end
	end
	crafting.register("table",recipe)
end

-- This loop goes through all recipes that have already been registered and
-- converts them
for item,_ in pairs(minetest.registered_items) do
	local crafts = minetest.get_all_craft_recipes(item)
	if crafts and item ~= "" then
		for _,recipe in pairs(crafts) do
			if recipe.method == "normal" then
				if recipe.replacements then
					recipe.returns = {}
					local count = {}
					for _, item in pairs(recipe.items) do
						count[item] = (count[item] or 0) + 1
					end
					for _,pair in pairs(recipe.replacements) do
						recipe.returns[pair[2]] = count[pair[1]]
					end
				end
				create_recipe(recipe)
			elseif recipe.method == "cooking" then
				local legacy = {input={},output={}}
				legacy.output[recipe.output] = 1
				legacy.input[recipe.items[1]] = 1 
				local cooked = minetest.get_craft_result({method = "cooking", width = 1, items = {recipe.items[1]}})
				legacy.time = cooked.time
				
				legacy.fuel_grade = {}
				legacy.fuel_grade.min = 0
				legacy.fuel_grade.max = math.huge	
				crafting.register("furnace",legacy)
			end
		end
		if clear_default_crafting then
			minetest.clear_craft({output=item})
		end
	end
	local fuel, afterfuel = minetest.get_craft_result({method="fuel",width=1,items={item}})
	if fuel.time ~= 0 then
		local legacy = {}
		legacy.name = item
		legacy.burntime = fuel.time
		legacy.grade = 1
		for _, afteritem in pairs(afterfuel.items) do
			if afteritem:get_count() > 0 then
				legacy.returns = legacy.returns or {}
				legacy.returns[afteritem:get_name()] = (legacy.returns[afteritem:get_name()] or 0) + afteritem:get_count()
			end
		end
		crafting.register_fuel(legacy)
		if clear_default_crafting then
			minetest.clear_craft({type="fuel", recipe=item})
		end
	end
end

-- This replaces the core register_craft method so that any crafts
-- registered after this one will be added to the new system.
crafting.minetest_register_craft = minetest.register_craft
minetest.register_craft = function(recipe)
	if not recipe.type then
		local legacy = {items={},returns={},output=recipe.output}
		local count = {}
		for _,row in pairs(recipe.recipe) do
			for _, item in pairs(row) do
				legacy.items[#legacy.items+1] = item
				count[item] = (count[item] or 0) + 1
			end
		end
		if recipe.replacements then
			for _,pair in pairs(recipe.replacements) do
				legacy.returns[pair[2]] = count[pair[1]]
			end
		end
		create_recipe(legacy)
	elseif recipe.type == "shapeless" then
		local legacy = {items={},returns={},output=recipe.output}
		if recipe.replacements then
			local count = {}
			for _, item in pairs(recipe.recipe) do
				count[item] = (count[item] or 0) + 1
			end
			for _,pair in pairs(recipe.replacements) do
				legacy.returns[pair[2]] = count[pair[1]]
			end
		end
		legacy.items = recipe.recipe
		create_recipe(legacy)
	elseif recipe.type == "cooking" then
		local legacy = {input={},output={}}
		legacy.output[recipe.output] = 1
		legacy.input[recipe.recipe] = 1
		legacy.time = recipe.cooktime or 3
		
		-- TODO: may make more sense to leave this nil and have these defaults on the util side
		legacy.fuel_grade = {}
		legacy.fuel_grade.min = 0
		legacy.fuel_grade.max = math.huge
		
		crafting.register("furnace",legacy)
	elseif recipe.type == "fuel" then
		local legacy = {}
		legacy.name = recipe.recipe
		legacy.burntime = recipe.burntime
		legacy.grade = 1
		if recipe.replacements then
			legacy.returns = {}
			for _,pair in pairs(recipe.replacements) do
				legacy.returns[pair[2]] = 1
			end
		end	
		crafting.register_fuel(legacy)
	end
	if not clear_default_crafting then
		return crafting.minetest_register_craft(recipe)
	end
end

local table_recipe = {
	output = "crafting:table",
	recipe = {
		{"group:tree","group:tree",""},
		{"group:tree","group:tree",""},
		{"","",""},
	},
}
local furnace_recipe = {
	output = "crafting:furnace",
	recipe = {
		{"default:stone","default:stone","default:stone"},
		{"default:stone","default:coal_lump","default:stone"},
		{"default:stone","default:stone","default:stone"},
	},
}

minetest.register_craft(table_recipe)
if clear_default_crafting then
	-- If we've cleared all native crafting recipes, add the table in so that the player can
	-- build that and access everything else
	crafting.minetest_register_craft(table_recipe)
end

if clear_default_crafting then
	-- If we've cleared native crafting, there's no point to the default furnace.
	-- replace it with the crafting: mod furnace.
	minetest.register_alias_force("default:furnace", "crafting:furnace")
	minetest.register_alias_force("default:furnace_active", "crafting:furnace_active")
else
	-- If we haven't cleared native crafting, leave the existing furnace alone and add the crafting: mod one separately
	minetest.register_craft(furnace_recipe)
end
