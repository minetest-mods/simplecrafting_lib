local MP = minetest.get_modpath(minetest.get_current_modname())
local S, NS = dofile(MP.."/intllib.lua")

simplecrafting_lib.generate_multifurnace_functions = function(craft_type, fuel_type, show_guides, alphabetize_items)

local modpath_default = minetest.get_modpath("default")

local function refresh_formspec(meta)
	local cook_time = meta:get_float("cook_time") or 0.0
	local total_cook_time = meta:get_float("total_cook_time") or 0.0
	local burn_time = meta:get_float("burn_time") or 0.0
	local total_burn_time = meta:get_float("total_burn_time") or 0.0

	local item_percent
	if total_cook_time > 0 then item_percent = math.floor((math.min(cook_time, total_cook_time) / total_cook_time) * 100) else item_percent = 0 end
	local burn_percent
	if total_burn_time > 0 then burn_percent = math.floor((math.min(burn_time, total_burn_time) / total_burn_time) * 100) else burn_percent = 0 end

	local product_list = minetest.deserialize(meta:get_string("product_list"))

	local product_page = meta:get_int("product_page") or 0
	
	local inventory = {
		"size[10,9.2]",

		"list[context;input;0,0.25;4,2;]",
		"list[context;fuel;0,2.75;4,2]",
		
		"image[4.5,0.7;1,1;gui_furnace_arrow_bg.png^[lowpart:"..(item_percent)..":gui_furnace_arrow_fg.png^[transformR270]",
		"image[4.5,3.3;1,1;default_furnace_fire_bg.png^[lowpart:"..(burn_percent)..":default_furnace_fire_fg.png]",

		"list[context;output;6,0.25;4,2;]",

		"list[current_player;main;1,5;8,1;0]",
		"list[current_player;main;1,6.2;8,3;8]",
		
		"listring[context;output]",
		"listring[current_player;main]",
		"listring[context;input]",
		"listring[current_player;main]",
		"listring[context;fuel]",
		"listring[current_player;main]",		
	}
	
	if modpath_default then
		inventory[#inventory+1] = default.gui_bg
		inventory[#inventory+1] = default.gui_bg_img
		inventory[#inventory+1] = default.gui_slots
	end

	local target = meta:get_string("target_item")
	if target ~= "" then
		inventory[#inventory+1] = "item_image_button[4.5,2;1,1;" .. target .. ";target;]"
	else
		inventory[#inventory+1] = "item_image_button[4.5,2;1,1;;;]"
	end

	for i = 1, 8 do
		local current_item = product_list[i + product_page*8]
		if current_item then
			inventory[#inventory+1] = "item_image_button[" ..
			6 + (i-1)%4 .. "," .. 2.75 + math.floor((i-1)/4) ..
			";1,1;" .. current_item.name .. ";product_".. i ..
			";\n\n       " .. current_item.count .. "]"
		else
			inventory[#inventory+1] = "item_image_button[" ..
			6 + (i-1)%4 .. "," .. 2.75 + math.floor((i-1)/4) ..
			";1,1;;empty;]"
		end
	end
	
	if show_guides then
		inventory[#inventory+1] = "button[9.0,8.3;1,0.75;show_guide;"..S("Show\nGuide").."]"
	end
	
	meta:set_string("formspec", table.concat(inventory))
end

local function refresh_products(meta)
	local inv = meta:get_inventory()
	local craftable = simplecrafting_lib.get_craftable_items(craft_type, inv:get_list("input"), false, alphabetize_items)
	local product_list = {}
	for _, craft in pairs(craftable) do
		table.insert(product_list, craft:to_table())
	end
	meta:set_string("product_list", minetest.serialize(product_list))
end

local function on_timer(pos, elapsed)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	
	local cook_time = meta:get_float("cook_time") or 0.0
	local total_cook_time = meta:get_float("total_cook_time") or 0.0
	local burn_time = meta:get_float("burn_time") or 0.0
	local total_burn_time = meta:get_float("total_burn_time") or 0.0

	local target_item = meta:get_string("target_item")

	cook_time = cook_time + elapsed
	burn_time = burn_time - elapsed
	
	local recipe
	local room_for_items = false
	local output
	if target_item ~= "" then
		recipe = simplecrafting_lib.get_crafting_result(craft_type, inv:get_list("input"), ItemStack({name=target_item, count=1}))
		if recipe then
			output = simplecrafting_lib.count_list_add(recipe.output, recipe.returns)
			room_for_items = simplecrafting_lib.room_for_items(inv, "output", output)
			total_cook_time = recipe.cooktime
		end
	end
	
	if recipe == nil or not room_for_items then
		-- we're not cooking anything.
		cook_time = 0.0
		if burn_time < 0 then burn_time = 0 end
		minetest.get_node_timer(pos):stop()
	else
		while true do
			if burn_time < 0 then
				-- burn some fuel, if possible.
				local fuel_recipes = simplecrafting_lib.get_fuels(fuel_type, inv:get_list("fuel"))
				local longest_burning
				for _, fuel_recipe in pairs(fuel_recipes) do
					if longest_burning == nil or longest_burning.burntime < fuel_recipe.burntime then
						longest_burning = fuel_recipe
					end
				end
						
				if longest_burning then
					total_burn_time = longest_burning.burntime
					burn_time = burn_time + total_burn_time
					local success = true
					if longest_burning.returns then
						success = simplecrafting_lib.add_items_if_room(inv, "output", longest_burning.returns) and
							simplecrafting_lib.room_for_items(inv, "output", output)						
					end
					if success then
						for item, count in pairs(longest_burning.input) do
							inv:remove_item("fuel", ItemStack({name = item, count = count}))
						end
					else
						--no room for both output and fuel reside
						cook_time = 0
						if burn_time < 0 then burn_time = 0 end
						break
					end
				else
					--out of fuel
					cook_time = 0
					if burn_time < 0 then burn_time = 0 end
					break
				end
			elseif cook_time >= recipe.cooktime then
				-- produce product
				simplecrafting_lib.add_items(inv, "output", output)
				simplecrafting_lib.remove_items(inv, "input", recipe.input)
				cook_time = cook_time - recipe.cooktime
				minetest.get_node_timer(pos):start(1)
				break
			else
				-- if we get here there's burning fuel but cook time hasn't reached recipe time yet.
				-- Do nothing this round.
				minetest.get_node_timer(pos):start(1)
				break
			end
		end
	end

	meta:set_float("burn_time", burn_time)
	meta:set_float("total_burn_time", total_burn_time)
	meta:set_float("cook_time", cook_time)	
	meta:set_float("total_cook_time", total_cook_time)	

	refresh_formspec(meta)
end

local on_construct = function(pos)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	inv:set_size("input", 2*4) -- materials that can be processed to outputs
	inv:set_size("fuel", 2*4) -- materials that can be burned for fuel
	inv:set_size("output", 2*4) -- holds output product
	meta:set_string("product_list", minetest.serialize({}))
	meta:set_string("target", "")
	refresh_formspec(meta)
end

local function allow_metadata_inventory_put(pos, listname, index, stack, player)
	if minetest.is_protected(pos, player:get_player_name()) then
		return 0
	end
	local meta = minetest.get_meta(pos)
	if listname == "input" then
		if simplecrafting_lib.is_possible_input(craft_type, stack:get_name()) then
			return stack:get_count()
		else
			return 0
		end
	elseif listname == "fuel" then
		if simplecrafting_lib.is_fuel(fuel_type, stack:get_name()) then
			return stack:get_count()
		else
			return 0
		end
	elseif listname == "output" then
		-- not allowed to put items into the output
		return 0
	end
	return stack:get_count()
end

local function allow_metadata_inventory_take(pos, listname, index, stack, player)
	if minetest.is_protected(pos, player:get_player_name()) then
		return 0
	end
	if listname == "target" then
		--delete the imaginary item from the target slot
		local inv = minetest.get_inventory({type="node", pos=pos})
		inv:set_stack(listname, index, ItemStack(""))
		return 0
	end
	return stack:get_count()
end

local function allow_metadata_inventory_move(pos, from_list, from_index, to_list, to_index, count, player)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	local stack = inv:get_stack(from_list, from_index)
	return math.min(allow_metadata_inventory_put(pos, to_list, to_index, stack, player), 
		allow_metadata_inventory_take(pos, from_list, from_index, stack, player))
end

local on_metadata_inventory_move = function(pos, flist, fi, tlist, ti, no, player)
	local meta = minetest.get_meta(pos)
	if tlist == "input" then
		refresh_products(meta)
	end
	on_timer(pos, 0)
end

local on_metadata_inventory_take = function(pos, lname, i, stack, player)
	local meta = minetest.get_meta(pos)
	if lname == "input" then
		refresh_products(meta)
		refresh_formspec(meta)
	elseif lname == "output" then
		on_timer(pos, 0)
	end
end

local on_metadata_inventory_put = function(pos, lname, i, stack, player)
	local meta = minetest.get_meta(pos)
	if lname == "input" then
		refresh_products(meta)
	end
	on_timer(pos, 0)
end

local can_dig = function(pos, player)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	return inv:is_empty("output") and inv:is_empty("fuel") and inv:is_empty("input")
end
	
local on_receive_fields = function(pos, formname, fields, sender)
	local meta = minetest.get_meta(pos)
	local product_list = minetest.deserialize(meta:get_string("product_list"))

	for field, _ in pairs(fields) do
		if field == "target" then
			meta:set_string("target_item", "")
			meta:set_float("cook_time", 0.0)
			meta:set_float("total_cook_time", 0.0)
		elseif string.sub(field, 1, 8) == "product_" then
			local new_target = product_list[tonumber(string.sub(field, 9))].name
			meta:set_string("target_item", new_target)
			meta:set_float("cook_time", 0.0)
			refresh_formspec(meta)
		end
	end
	
	if fields.show_guide and show_guides then
		simplecrafting_lib.show_crafting_guide(craft_type, sender)
	end
	
	on_timer(pos, 0)
end

return {
	allow_metadata_inventory_move = allow_metadata_inventory_move,
	allow_metadata_inventory_put = allow_metadata_inventory_put,
	can_dig = can_dig,
	on_construct = on_construct,
	on_metadata_inventory_move = on_metadata_inventory_move,
	on_metadata_inventory_put = on_metadata_inventory_put,
	on_metadata_inventory_take = on_metadata_inventory_take,
	on_receive_fields = on_receive_fields,
	on_timer = on_timer,
}
end
