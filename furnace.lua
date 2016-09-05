crafting.furnace = {}
crafting.furnace.recipes = {}
crafting.furnace.fuels = {}

-- For use by other mods
crafting.furnace.recipes_by_out = {}
local recipes_by_out = crafting.furnace.recipes_by_out

local recipes = crafting.furnace.recipes
local fuels = crafting.furnace.fuels

crafting.furnace.register = function(def)
	def.ret = def.ret or {}
	-- Furnace recipes can only have one input and output
	if #def.input > 1 or #def.output > 1 then
		return false
	end
	-- Strip group: from group names to simplify comparison later
	for item,count in pairs(def.input) do
		local group = string.match(item,"^group:(%S+)$")
		if group then
			def.input[group] = count
			def.input[item] = nil
		end
	end

	-- Set fuel grade defaults
	def.fuel_grade = def.fuel_grade or {}
	def.fuel_grade.min = def.fuel_grade.min or 0
	def.fuel_grade.max = def.fuel_grade.max or math.huge

	-- Only one input, but pairs is easiest way to find it
	for item,count in pairs(def.input) do
		recipes[item] = recipes[item] or {}
		local inserted = false
		-- If a recipe is more specific, insert it before other recipe
		for i,recipe in ipairs(recipes[item]) do
			if def.fuel_grade.min > recipe.fuel_grade.min
			or def.fuel_grade.max < recipe.fuel_grade.max then
				table.insert(recipes[item],i,def)
				inserted = true
				break
			end
		end
		if not inserted then
			recipes[item][#recipes[item] + 1] = def
		end
	end

	-- Only one output, but more may be allowed in future
	for item,_ in pairs(def.output) do
		recipes_by_out[item] = recipes_by_out[item] or {} 
		recipes_by_out[item][#recipes_by_out[item]+1] = def
	end
	return true
end

crafting.furnace.register_fuel = function(def)
	-- Strip group: from group names to simplify comparison later
	local group = string.match(def.name,"^group:(%S+)$")
	def.name = group or def.name

	fuels[def.name] = def
	return true
end

local function is_ingredient(item)
	if recipes[item] then
		return recipes[item]
	end

	local def = minetest.registered_items[item]
	if def and def.groups then
		for group,_ in pairs(def.groups) do
			if recipes[group] then
				return recipes[group]
			end
		end
	end
	return nil
end

local function get_recipe_name(item_stack)
	local item = item_stack:get_name()
	
	if recipes[item] then
		return item
	end

	local def = minetest.registered_items[item]
	if def and def.groups then
		for group,_ in pairs(def.groups) do
			if recipes[group] then
				return group
			end
		end
	end
	return nil
end

local function is_fuel(item,grade)
	if fuels[item] then
		return fuels[item]
	end

	local def = minetest.registered_items[item]
	if def and def.groups then
		local max = -1
		local fuel_group
		for group,_ in pairs(def.groups) do
			if fuels[group] then
				if fuels[group].burntime > max then
					fuel_group = fuels[group]
					max = fuel_group.burntime
				end
			end
		end
		if fuel_group then
			return fuel_group
		end
	end
	return nil
end

local function get_fueled_recipe(item_recipes,fuel)
	for _,recipe in ipairs(item_recipes) do
		if  fuel.grade >= recipe.fuel_grade.min
		and fuel.grade <= recipe.fuel_grade.max then
			return recipe
		end
	end
	return nil
end

local function sort_input(meta)
	local inv = meta:get_inventory()
	if inv:is_empty("input") then
		return
	end

	local item = inv:get_stack("input",1)
	local fuel = inv:get_stack("input",2)

	
	local item_recipes
	local item_fuel
	if not item:is_empty() then
		item_recipes = is_ingredient(item:get_name())
		item_fuel = is_fuel(item:get_name())
	end

	local fuel_recipes
	local fuel_fuel
	if not fuel:is_empty() then
		fuel_recipes = is_ingredient(fuel:get_name())
		fuel_fuel = is_fuel(fuel:get_name())
	end

	-- Assume correct combinations first
	if item_recipes and fuel_fuel then
		if get_fueled_recipe(item_recipes,fuel_fuel) then
			return false
		end
	end
	if fuel_recipes and item_fuel then
		if get_fueled_recipe(fuel_recipes,item_fuel) then
			return false
		end
	end

	-- Assume one is a correct fuel
	if fuel_fuel then
		return false
	elseif item_fuel then
		inv:set_list("input",{fuel,item})
		return true
	end

	-- Assume one is an ingredient
	if item_recipes then
		return false
	elseif fuel_recipes then
		inv:set_list("input",{fuel,item})
		return true
	end

	-- If both wrong, don't do anything
	return false
end

local function is_recipe(item,fuel)
	local recipes = is_ingredient(item)
	local fuel_def = is_fuel(fuel)
	if not recipes or not fuel_def then
		return nil, nil
	end
	return get_fueled_recipe(recipes,fuel_def),fuel_def
end

local function swap_furnace(pos)
	local node = minetest.get_node(pos)
	if node.name == "crafting:furnace" then
		node.name = "crafting:furnace_active"
	elseif node.name == "crafting:furnace_active" then
		node.name = "crafting:furnace"
	end
	minetest.swap_node(pos,node)
end

local function set_infotext(meta)
	meta:set_string("infotext", 
		string.format("Fuel time: %.1f | Item time: %.1f"
			,meta:get_float("burntime")
			,meta:get_float("itemtime")
		)
	)
end

local function get_items(inv)
	return inv:get_stack("input",1), inv:get_stack("input",2)
end

local function get_old_items(meta)
	return meta:get_string("item"), meta:get_string("fuel")
end

local function burn_fuel(meta,inv)
	local fuel = inv:get_stack("input",2)
	local fuel_def = is_fuel(fuel:get_name())
	meta:set_string("fuel",fuel:get_name())
	meta:set_float("burntime",fuel_def.burntime)
	fuel:set_count(fuel:get_count() - 1)
	inv:set_stack("input",2,fuel)
end

local function set_ingredient(meta,item,recipe)
	meta:set_string("item",item:get_name())
	meta:set_float("itemtime",recipe.time)
end

local function clear_item(meta)
	meta:set_string("item","")
	meta:set_float("itemtime",math.huge)
end

local function set_timer(pos,itemtime,burntime)
	minetest.get_node_timer(pos):start(math.min(itemtime,burntime))
end

local function enough_items(item_stack,recipe)
	if item_stack:is_empty() then
		return false
	end
	return item_stack:get_count() >= recipe.input[get_recipe_name(item_stack)]
end

local function room_for_out(recipe,inv)
	for output,count in pairs(recipe.output) do
		if not inv:room_for_item("output",output .. " " .. count) then
			return false
		end
	end
	return true
end

local function try_start(pos)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()

	local item,fuel = get_items(inv)
	local recipe,fuel_def = is_recipe(item:get_name(),fuel:get_name())

	if not recipe
	or not enough_items(item,recipe)
	or not room_for_out(recipe,inv) then
		return
	end

	set_ingredient(meta,item,recipe)
	burn_fuel(meta,inv)

	set_timer(pos,recipe.time,fuel_def.burntime)
	swap_furnace(pos)
	set_infotext(meta)
end

minetest.register_node("crafting:furnace",{
	drawtype = "normal",
	tiles = {
		"default_furnace_top.png", "default_furnace_bottom.png",
		"default_furnace_side.png", "default_furnace_side.png",
		"default_furnace_side.png", "default_furnace_front.png"
	},
	paramtype2 = "facedir",
	is_ground_content = false,
	groups = {oddly_breakable_by_hand = 1,cracky=3},
	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()
		inv:set_size("input", 2)
		inv:set_size("output", 2*2)
		meta:set_string("formspec",table.concat({
			"size[12,9]",
			"list[context;input;4,1;1,1;]",
			"list[context;input;4,3;1,1;1]",
			"list[context;output;6,1.5;2,2;]",
			"list[current_player;main;2,5;8,1;0]",
			"list[current_player;main;2,6;8,3;8]",
			"listring[context;output]",
			"listring[current_player;main]",
			"listring[context;input]",
			"listring[current_player;main]",
		}))
	end,
	on_metadata_inventory_move = function(pos,flist,fi,tlist,ti,no,player)
		local meta = minetest.get_meta(pos)
		if tlist == "input" then
			sort_input(meta)
		end
		try_start(pos)
	end,
	on_metadata_inventory_take = function(pos,lname,i,stack,player)
		local meta = minetest.get_meta(pos)
		try_start(pos)
	end,
	on_metadata_inventory_put = function(pos,lname,i,stack,player)
		local meta = minetest.get_meta(pos)
		if lname == "input" then
			sort_input(meta)
		end
		try_start(pos)
	end,
	can_dig = function(pos,player)
		local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()
		return inv:is_empty("output") and inv:is_empty("input")
	end,
})

local function on_timeout(pos)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()

	local item = inv:get_stack("input",1)
	local old_fuel = meta:get_string("fuel")
	local old_item = meta:get_string("item")

	local recipe,fuel_def = is_recipe(item:get_name(),old_fuel)
	local timer = minetest.get_node_timer(pos)

	if item:get_name() ~= old_item then
		if recipe then
			set_ingredient(meta,item,recipe)
			return true
		else
			clear_item(meta)
			return false
		end
	end

	-- Triggered if active furnace placed
	if not recipe then
		clear_item(meta)
		return false
	end

	if not room_for_out(recipe,inv)
	or not enough_items(item,recipe) then
		clear_item(meta)
		return false
	end

	for output,count in pairs(recipe.output) do
		inv:add_item("output",output .. " " .. count)
	end
	item:set_count(item:get_count() - recipe.input[get_recipe_name(item)])
	inv:set_stack("input",1,item)

	if not room_for_out(recipe,inv)
	or not enough_items(item,recipe) then
		clear_item(meta)
		return false
	else
		set_ingredient(meta,item,recipe)
		return true
	end
end

local function on_burnout(pos)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()

	local item,fuel = get_items(inv)
	local recipe,fuel_def = is_recipe(item:get_name(),fuel:get_name())

	if not recipe then
		clear_item(meta)
		meta:set_float("burntime",0)
		return false
	end

	if not room_for_out(recipe,inv)
	or not enough_items(item,recipe) then
		clear_item(meta)
		meta:set_float("burntime",0)
		return false
	end

	burn_fuel(meta,inv)
	return true
end
	
local function try_change(pos)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()

	local item = inv:get_stack("input",1)
	local fuel = inv:get_stack("input",2)
	local old_fuel = meta:get_string("fuel")
	local old_item = meta:get_string("item")

	local recipe,fuel_def = is_recipe(item:get_name(),fuel:get_name())
	local timer = minetest.get_node_timer(pos)

	if item:get_name() ~= old_item and recipe then
		-- Check if remains of old fuel can be used
		local old_recipe = is_recipe(item:get_name(),old_fuel)
		if old_recipe == recipe then
			set_ingredient(meta,item,recipe)
			local burntime = meta:get_float("burntime") - timer:get_elapsed()
			meta:set_float("burntime",burntime)
			timer:start(math.min(burntime,recipe.time))
			set_infotext(meta)
			return
		else
			burn_fuel(meta,inv)
			set_ingredient(meta,item,recipe)
			timer:start(math.min(recipe.time,fuel_def.burntime))
			set_infotext(meta)
			return
		end
	end

	if fuel:get_name() ~= old_fuel then
		local old_recipe = is_recipe(item:get_name(),old_fuel)
		if recipe and recipe ~= old_recipe then
			burn_fuel(meta,inv)
			set_ingredient(meta,item,recipe)
			timer:start(math.min(recipe.time,fuel_def.burntime))
			set_infotext(meta)
			return
		end
	end
end

local function furnace_timer(pos,elapsed)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()

	local item = inv:get_stack("input",1)
	local fuel = inv:get_stack("input",2)
	local old_fuel = meta:get_string("fuel")
	local old_item = meta:get_string("item")

	local recipe,fuel_def = is_recipe(item:get_name(),fuel:get_name())
	local timer = minetest.get_node_timer(pos)

	local burntime = meta:get_float("burntime") - elapsed
	local itemtime = meta:get_float("itemtime") - elapsed


	meta:set_float("itemtime",itemtime)
	meta:set_float("burntime",burntime)

	local create_timer = burntime > 0

	if itemtime <= 0 then
		on_timeout(pos)
	end
	if burntime <= 0 then
		create_timer = on_burnout(pos)
	end

	if create_timer then
		timer:start(math.min(meta:get_float("burntime"),meta:get_float("itemtime")))
	else
		swap_furnace(pos)
	end
	set_infotext(meta)
	return false
end

minetest.register_node("crafting:furnace_active",{
	drawtype = "normal",
	tiles = {
		"default_furnace_top.png", "default_furnace_bottom.png",
		"default_furnace_side.png", "default_furnace_side.png",
		"default_furnace_side.png",
		{
			image = "default_furnace_front_active.png",
			backface_culling = false,
			animation = {
				type = "vertical_frames",
				aspect_w = 16,
				aspect_h = 16,
				length = 1.5
			},
		},
	},
	paramtype2 = "facedir",
	drop = "crafting:furnace",
	is_ground_content = false,
	groups = {oddly_breakable_by_hand = 1,cracky=3},
	on_metadata_inventory_move = function(pos,flist,fi,tlist,ti,no,player)
		local meta = minetest.get_meta(pos)
		if tlist == "input" then
			sort_input(meta)
		end
		try_change(pos)
	end,
	on_metadata_inventory_take = function(pos,lname,i,stack,player)
		try_change(pos)
	end,
	on_metadata_inventory_put = function(pos,lname,i,stack,player)
		local meta = minetest.get_meta(pos)
		if lname == "input" then
			sort_input(meta)
		end
		try_change(pos)
	end,
	can_dig = function(pos,player)
		local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()
		return inv:is_empty("output") and inv:is_empty("input")
	end,
	on_timer = furnace_timer,
})
