local MP = minetest.get_modpath(minetest.get_current_modname())
local S, NS = dofile(MP.."/intllib.lua")

local function is_ingredient(item)
	local recipes = crafting.type.furnace.recipes

	local outputs = crafting.get_craftable_recipes("furnace", {ItemStack(item)})
	
	if #outputs > 0 then
		return outputs[1]
	end
	return nil
end

--
-- Formspecs
--

local function active_formspec(fuel_percent, item_percent)
	local formspec =
		"size[8,8.5]"..
		default.gui_bg..
		default.gui_bg_img..
		default.gui_slots..
		"list[current_name;src;2.75,0.5;1,1;]"..
		"list[current_name;fuel;2.75,2.5;1,1;]"..
		"image[2.75,1.5;1,1;default_furnace_fire_bg.png^[lowpart:"..
		(100-fuel_percent)..":default_furnace_fire_fg.png]"..
		"image[3.75,1.5;1,1;gui_furnace_arrow_bg.png^[lowpart:"..
		(item_percent)..":gui_furnace_arrow_fg.png^[transformR270]"..
		"list[current_name;dst;4.75,0.96;2,2;]"..
		"list[current_player;main;0,4.25;8,1;]"..
		"list[current_player;main;0,5.5;8,3;8]"..
		"listring[current_name;dst]"..
		"listring[current_player;main]"..
		"listring[current_name;src]"..
		"listring[current_player;main]"..
		"listring[current_name;fuel]"..
		"listring[current_player;main]"..
		default.get_hotbar_bg(0, 4.25)
	return formspec
end

local inactive_formspec =
	"size[8,8.5]"..
	default.gui_bg..
	default.gui_bg_img..
	default.gui_slots..
	"list[current_name;src;2.75,0.5;1,1;]"..
	"list[current_name;fuel;2.75,2.5;1,1;]"..
	"image[2.75,1.5;1,1;default_furnace_fire_bg.png]"..
	"image[3.75,1.5;1,1;gui_furnace_arrow_bg.png^[transformR270]"..
	"list[current_name;dst;4.75,0.96;2,2;]"..
	"list[current_player;main;0,4.25;8,1;]"..
	"list[current_player;main;0,5.5;8,3;8]"..
	"listring[current_name;dst]"..
	"listring[current_player;main]"..
	"listring[current_name;src]"..
	"listring[current_player;main]"..
	"listring[current_name;fuel]"..
	"listring[current_player;main]"..
	default.get_hotbar_bg(0, 4.25)

--
-- Node callback functions that are the same for active and inactive furnace
--

local function can_dig(pos, player)
	local meta = minetest.get_meta(pos);
	local inv = meta:get_inventory()
	return inv:is_empty("fuel") and inv:is_empty("dst") and inv:is_empty("src")
end

local function allow_metadata_inventory_put(pos, listname, index, stack, player)
	if minetest.is_protected(pos, player:get_player_name()) then
		return 0
	end
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	if listname == "fuel" then
		if crafting.is_fuel(stack:get_name()) then
			if inv:is_empty("src") then
				meta:set_string("infotext", S("Furnace is empty"))
			end
			return stack:get_count()
		else
			return 0
		end
	elseif listname == "src" then
		if is_ingredient(stack:get_name()) then
			return stack:get_count()
		else
			return 0
		end
	elseif listname == "dst" then
		return 0
	end
end

local function allow_metadata_inventory_move(pos, from_list, from_index, to_list, to_index, count, player)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	local stack = inv:get_stack(from_list, from_index)
	return allow_metadata_inventory_put(pos, to_list, to_index, stack, player)
end

local function allow_metadata_inventory_take(pos, listname, index, stack, player)
	if minetest.is_protected(pos, player:get_player_name()) then
		return 0
	end
	return stack:get_count()
end

local function swap_node(pos, name)
	local node = minetest.get_node(pos)
	if node.name == name then
		return
	end
	node.name = name
	minetest.swap_node(pos, node)
end

local function furnace_node_timer(pos, elapsed)
	--
	-- Inizialize metadata
	--
	local meta = minetest.get_meta(pos)
	local fuel_time = meta:get_float("fuel_time") or 0
	local src_time = meta:get_float("src_time") or 0
	local fuel_totaltime = meta:get_float("fuel_totaltime") or 0

	local inv = meta:get_inventory()
	local srclist, fuelitem

	local cookable
	local fuel_present

	local update = true
	while update do
		update = false

		srclist = inv:get_list("src")
		fuelitem = inv:get_stack("fuel", 1)
		fuel_present = crafting.is_fuel(fuelitem:get_name())

		--
		-- Cooking
		--

		-- Check if we have cookable content
		
		local craftable = crafting.get_craftable_recipes("furnace", srclist)
		if #craftable > 0 then
			cookable = craftable[1]
		end
		
		-- Check if we have enough fuel to burn
		if fuel_time < fuel_totaltime then
			-- The furnace is currently active and has enough fuel
			fuel_time = fuel_time + elapsed
			-- If there is a cookable item then check if it is ready yet
			if cookable then
				src_time = src_time + elapsed
				if src_time >= cookable.time then
					-- Place result in dst list if possible					
					if crafting.add_items(inv, "dst", cookable.output) then
						crafting.remove_items(inv, "src", cookable.input)
						if cookable.returns then
							crafting.add_items(inv, "src", cookable.returns)
						end
						src_time = src_time - cookable.time
						update = true
					end
				end
			end
		else
			-- Furnace ran out of fuel
			if cookable then
				-- We need to get new fuel
				if not fuel_present then
					-- No valid fuel in fuel list
					fuel_totaltime = 0
					src_time = 0
				else
					-- Take fuel from fuel list
					fuelitem:take_item(1)
					inv:set_stack("fuel", 1, fuelitem)
					update = true
					fuel_totaltime = fuel_present.burntime + (fuel_time - fuel_totaltime)
					src_time = src_time + elapsed
				end
			else
				-- We don't need to get new fuel since there is no cookable item
				fuel_totaltime = 0
				src_time = 0
			end
			fuel_time = 0
		end

		elapsed = 0
	end

	if fuel_present and fuel_totaltime > fuel_present.burntime then
		fuel_totaltime = fuel_present.burntime
	end
	if srclist[1]:is_empty() then
		src_time = 0
	end

	--
	-- Update formspec, infotext and node
	--
	local formspec = inactive_formspec
	local item_state = ""
	local item_percent = 0
	if cookable then
		item_percent = math.floor(src_time / cookable.time * 100)
		if item_percent > 100 then
			item_state = S("100% (output full)")
		else
			item_state = S("@1%", item_percent)
		end
	elseif srclist[1]:is_empty() then
		item_state = S("Empty")
	end

	local fuel_state = S("Empty")
	local result = false

	if fuel_totaltime ~= 0 then
		local fuel_percent = math.floor(fuel_time / fuel_totaltime * 100)
		fuel_state = S("@1%", fuel_percent)
		formspec = active_formspec(fuel_percent, item_percent)
		swap_node(pos, "crafting:furnace_active")
		-- make sure timer restarts automatically
		result = true
	else
		if not fuelitem:is_empty() then
			fuel_state = S("0%")
		end
		swap_node(pos, "crafting:furnace")
		-- stop timer on the inactive furnace
		minetest.get_node_timer(pos):stop()
	end

	local infotext
	if result then
		infotext = S("Furnace active (Item: @1; Fuel: @2)", item_state, fuel_state)
	else
		infotext = S("Furnace inactive (Item: @1; Fuel: @2)", item_state, fuel_state)
	end

	--
	-- Set meta values
	--
	meta:set_float("fuel_totaltime", fuel_totaltime)
	meta:set_float("fuel_time", fuel_time)
	meta:set_float("src_time", src_time)
	meta:set_string("formspec", formspec)
	meta:set_string("infotext", infotext)

	return result
end

--
-- Node definitions
--

minetest.register_node("crafting:furnace", {
	description = S("Furnace"),
	tiles = {
		"default_furnace_top.png", "default_furnace_bottom.png",
		"default_furnace_side.png", "default_furnace_side.png",
		"default_furnace_side.png", "default_furnace_front.png"
	},
	paramtype2 = "facedir",
	groups = {cracky=2},
	is_ground_content = false,
	sounds = default.node_sound_stone_defaults(),

	can_dig = can_dig,

	on_timer = furnace_node_timer,

	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		meta:set_string("formspec", inactive_formspec)
		local inv = meta:get_inventory()
		inv:set_size('src', 1)
		inv:set_size('fuel', 1)
		inv:set_size('dst', 4)
	end,

	on_metadata_inventory_move = function(pos)
		minetest.get_node_timer(pos):start(1.0)
	end,
	on_metadata_inventory_put = function(pos)
		-- start timer function, it will sort out whether furnace can burn or not.
		minetest.get_node_timer(pos):start(1.0)
	end,
	on_blast = function(pos)
		local drops = {}
		default.get_inventory_drops(pos, "src", drops)
		default.get_inventory_drops(pos, "fuel", drops)
		default.get_inventory_drops(pos, "dst", drops)
		drops[#drops+1] = "crafting:furnace"
		minetest.remove_node(pos)
		return drops
	end,

	allow_metadata_inventory_put = allow_metadata_inventory_put,
	allow_metadata_inventory_move = allow_metadata_inventory_move,
	allow_metadata_inventory_take = allow_metadata_inventory_take,
})

minetest.register_node("crafting:furnace_active", {
	description = S("Furnace"),
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
		}
	},
	paramtype2 = "facedir",
	light_source = 8,
	drop = "crafting:furnace",
	groups = {cracky=2, not_in_creative_inventory=1},
	is_ground_content = false,
	sounds = default.node_sound_stone_defaults(),
	on_timer = furnace_node_timer,

	can_dig = can_dig,

	allow_metadata_inventory_put = allow_metadata_inventory_put,
	allow_metadata_inventory_move = allow_metadata_inventory_move,
	allow_metadata_inventory_take = allow_metadata_inventory_take,
})




