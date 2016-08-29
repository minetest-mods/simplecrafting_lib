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
	return false
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
	return false
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

local function clear_item_meta(meta)
	meta:set_string("item","")
	meta:set_float("itemtime",0)
end

local function set_burnout(timer,meta)
	local burntime = meta:get_float("burntime") - timer:get_elapsed()
	meta:set_float("burntime",burntime)
	timer:set(burntime,0)
end

local function is_recipe(item,fuel)
	local recipes = is_ingredient(item)
	local fuel_def = is_fuel(fuel)
	if not recipes or not fuel_def then
		return nil
	end
	return get_fueled_recipe(recipes,fuel_def)
end

local function update_furnace(pos)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()

	local item = inv:get_stack("input",1)
	local old_item = meta:get_string("item")
	local fuel = inv:get_stack("input",2)
	local old_fuel = meta:get_string("fuel")

	local active = meta:get_string("active")
	local timer = minetest.get_node_timer(pos)
	if active == "true" then
		-- Check all item conditions
		if item:is_empty() then
			clear_item_meta(meta)
			set_burnout(timer,meta)
			return
		end

		if item:get_name() ~= old_item then
			clear_item_meta(meta)
			local recipe = is_recipe(item:get_name(),old_fuel)
			if recipe then
				meta:set_string("item",item:get_name())
				meta:set_float("itemtime",recipe.time)
				local burntime = meta:get_float("burntime") - timer:get_elapsed()
				meta:set_float("burntime",burntime)
				burntime = math.min(burntime,recipe.time)
				timer:set(burntime,0)
			else
				set_burnout(timer,meta)
			end
			return
		end

		local recipe = is_recipe(old_item,old_fuel)
		if item:get_count() < recipe.input[old_item] then
			clear_item_meta(meta)
			set_burnout(timer,meta)
			return
		end

		for k,v in pairs(recipe.output) do
			if not inv:room_for_item("output",k .. " " .. tostring(v)) then
				clear_item_meta(meta)
				set_burnout(timer,meta)
				return
			end
		end

		-- If fuel has changed, the time should already be set to
		-- it's burnout or smaller
	else
		if item:is_empty() or fuel:is_empty() then
			return
		end

		local recipe = is_recipe(item:get_name(),fuel:get_name())
		if not recipe then
			return
		end

		for k,v in pairs(recipe.output) do
			if not inv:room_for_item("output",k .. " " .. tostring(v)) then
				return
			end
		end

		if item:get_count() < recipe.input[item:get_name()] then
			return
		end

		-- Everything has been checked - furnace can be started
		meta:set_string("item",item:get_name())
		meta:set_float("itemtime",recipe.time)
		local fuel_def = is_fuel(fuel:get_name())
		meta:set_string("fuel",fuel:get_name())
		meta:set_float("burntime",fuel_def.burntime)
		meta:set_string("active","true")
		timer:set(math.min(fuel_def.burntime,recipe.time),0)
	end
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
	groups = {oddly_breakable_by_hand = 1,choppy=3},
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
		update_furnace(pos)
	end,
	on_metadata_inventory_take = function(pos,lname,i,stack,player)
		local meta = minetest.get_meta(pos)
		update_furnace(pos)
	end,
	on_metadata_inventory_put = function(pos,lname,i,stack,player)
		local meta = minetest.get_meta(pos)
		if lname == "input" then
			sort_input(meta)
		end
		update_furnace(pos)
	end,
	can_dig = function(pos,player)
		local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()
		return inv:is_empty("output") and inv:is_empty("input")
	end,
	on_timer = function(pos,elapsed)
		local meta = minetest.get_meta(pos)
	end,
})
	--allow_metadata_inventory_take = function(pos,lname,i,stack,player) end,
	--]]
