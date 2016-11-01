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

local function set_infotext(state)
	state.infotext = string.format("Fuel time: %.1f | Item time: %.1f"
			,state.burntime
			,state.itemtime
		)
end

local function get_furnace_state(pos)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	return {
		inv = inv,
		meta = meta,
		burntime = meta:get_float("burntime"),
		itemtime = meta:get_float("itemtime"),
		item = inv:get_stack("input",1),
		fuel = inv:get_stack("input",2),
		old_fuel = meta:get_string("fuel"),
		old_item = meta:get_string("item"),
		infotext = meta:get_string("infotext"),
	}
end

local function set_furnace_state(pos,state)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	meta:set_float("burntime",state.burntime)
	meta:set_float("itemtime",state.itemtime)
	inv:set_stack("input",1,state.item)
	inv:set_stack("input",2,state.fuel)
	meta:set_string("fuel",state.old_fuel)
	meta:set_string("item",state.old_item)
	meta:set_string("infotext",state.infotext)
end

local function burn_fuel(state)
	local fuel_def = is_fuel(state.fuel:get_name())
	state.old_fuel = state.fuel:get_name()
	state.burntime = fuel_def.burntime
	state.fuel:set_count(state.fuel:get_count() - 1)
end

local function set_ingredient(state,item,recipe)
	state.old_item = item:get_name()
	state.itemtime = recipe.time
end

local function clear_item(state)
	state.old_item = ""
	state.itemtime = math.huge
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
	local state = get_furnace_state(pos)

	local recipe,fuel_def = is_recipe(state.item:get_name(),state.fuel:get_name())

	if not recipe
	or not enough_items(state.item,recipe)
	or not room_for_out(recipe,state.inv) then
		return
	end

	set_ingredient(state,state.item,recipe)
	burn_fuel(state)

	set_timer(pos,recipe.time,fuel_def.burntime)
	swap_furnace(pos)
	set_infotext(state)
	set_furnace_state(pos,state)
end

minetest.register_node("crafting:furnace",{
	description = "Furnace",
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

local function on_timeout(state)
	local recipe,fuel_def = is_recipe(state.item:get_name(),state.old_fuel)

	if state.item:get_name() ~= state.old_item then
		if recipe then
			set_ingredient(state,state.item,recipe)
			return true
		else
			clear_item(state)
			return false
		end
	end

	-- Triggered if active furnace placed
	if not recipe then
		clear_item(state)
		return false
	end

	if not room_for_out(recipe,state.inv)
	or not enough_items(state.item,recipe) then
		clear_item(state)
		return false
	end

	for output,count in pairs(recipe.output) do
		state.inv:add_item("output",output .. " " .. count)
	end
	state.item:set_count(state.item:get_count() - recipe.input[get_recipe_name(state.item)])

	if not room_for_out(recipe,state.inv)
	or not enough_items(state.item,recipe) then
		clear_item(state)
		return false
	else
		set_ingredient(state,state.item,recipe)
		return true
	end
end

local function on_burnout(state)
	local recipe,fuel_def = is_recipe(state.item:get_name(),state.fuel:get_name())

	if not recipe then
		clear_item(state)
		state.burntime = 0
		return false
	end

	if not room_for_out(recipe,state.inv)
	or not enough_items(state.item,recipe) then
		clear_item(state)
		state.burntime = 0
		return false
	end

	burn_fuel(state)
	return true
end
	
local function try_change(pos)
	local state = get_furnace_state(pos)
	local recipe,fuel_def = is_recipe(state.item:get_name(),state.fuel:get_name())
	local timer = minetest.get_node_timer(pos)

	if state.item:get_name() ~= state.old_item and recipe then
		-- Check if remains of old fuel can be used
		local old_recipe = is_recipe(state.item:get_name(),state.old_fuel)
		if old_recipe == recipe then
			set_ingredient(state,state.item,recipe)
			state.burntime = state.burntime - timer:get_elapsed()
			timer:start(math.min(state.burntime,recipe.time))
			set_infotext(state)
			set_furnace_state(pos,state)
			return
		else
			burn_fuel(state)
			set_ingredient(state,state.item,recipe)
			timer:start(math.min(recipe.time,fuel_def.burntime))
			set_infotext(state)
			set_furnace_state(pos,state)
			return
		end
	end

	if state.fuel:get_name() ~= state.old_fuel then
		local old_recipe = is_recipe(state.item:get_name(),state.old_fuel)
		if recipe and recipe ~= old_recipe then
			burn_fuel(state)
			set_ingredient(state,state.item,recipe)
			timer:start(math.min(recipe.time,fuel_def.burntime))
			set_infotext(state)
			set_furnace_state(pos,state)
			return
		end
	end
end


local function furnace_timer(pos,elapsed,state)
	state = state or get_furnace_state(pos)

	local timer = minetest.get_node_timer(pos)

	local time_taken = math.min(state.burntime,state.itemtime)

	local create_timer = true
	local remaining = elapsed
	if remaining >= time_taken then
		remaining = elapsed - time_taken
		state.itemtime = state.itemtime - time_taken
		state.burntime = state.burntime - time_taken

		create_timer = state.burntime > 0

		if state.itemtime <= 0 then
			on_timeout(state)
		end
		if state.burntime <= 0 then
			create_timer = on_burnout(state)
		end
	end

	if create_timer then
		local time = math.min(state.burntime,state.itemtime)
		if remaining > time then
			return furnace_timer(pos,remaining,state)
		else
			timer:set(time,remaining)
		end
	else
		swap_furnace(pos)
	end
	set_infotext(state)
	set_furnace_state(pos,state)
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
