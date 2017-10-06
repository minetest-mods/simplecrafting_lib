local MP = minetest.get_modpath(minetest.get_current_modname())
local S, NS = dofile(MP.."/intllib.lua")

-- autocraft_def can have the following:
--{
--	show_guides = true or false,
--	alphabetize_items = true or false,
--	description = string,
--	hopper_node_name = string,
--	enable_pipeworks = true or false,
--	protect_inventory = true or false
--	crafting_time_multiplier = function(pos, recipe)
--	active_node = string,
--}

local modpath_default = minetest.get_modpath("default")

simplecrafting_lib.generate_autocraft_functions = function(craft_type, autocraft_def)

if autocraft_def == nil then
	autocraft_def = {}
end

-- Hopper compatibility
if autocraft_def.hopper_node_name and minetest.get_modpath("hopper") and hopper ~= nil and hopper.add_container ~= nil then
	hopper:add_container({
		{"top", autocraft_def.hopper_node_name, "output"},
		{"bottom", autocraft_def.hopper_node_name, "input"},
		{"side", autocraft_def.hopper_node_name, "input"},
})
end

local function refresh_formspec(meta)
	local craft_time = meta:get_float("craft_time") or 0.0
	local total_craft_time = meta:get_float("total_craft_time") or 0.0

	local item_percent
	if total_craft_time > 0 then item_percent = math.floor((math.min(craft_time, total_craft_time) / total_craft_time) * 100) else item_percent = 0 end
	
	local inventory = {
		"size[10,10.2]",
		"list[context;input;0,0.5;2,5;]",
		
		"image[3,0.5;1,1;gui_furnace_arrow_bg.png^[lowpart:"..(item_percent)..":gui_furnace_arrow_fg.png^[transformR270]",

		"list[context;output;4,0;6,2;]",

		"list[current_player;main;1,6.2;8,1;0]",
		"list[current_player;main;1,7.4;8,3;8]",
		
		"listring[context;output]",
		"listring[current_player;main]",
		"listring[context;input]",
		"listring[current_player;main]",
	}
	
	if autocraft_def.description then
		inventory[#inventory+1] = "label[1.5,0;"..autocraft_def.description.."]"
	end
	
	if modpath_default then
		inventory[#inventory+1] = default.gui_bg
		inventory[#inventory+1] = default.gui_bg_img
		inventory[#inventory+1] = default.gui_slots
	end

	local target = meta:get_string("target_item")
	if target ~= "" then
		inventory[#inventory+1] = "item_image_button[2,0.5;1,1;" .. target .. ";target;]"
	else
		inventory[#inventory+1] = "item_image_button[2,0.5;1,1;;;]"
	end

	-- product selection buttons
	
	local product_x_dim = 8
	local product_y_dim = 4
	local corner_x = 2
	local corner_y = 2
	local product_count = product_x_dim * product_y_dim

	local product_list = minetest.deserialize(meta:get_string("product_list"))
	local product_page = meta:get_int("product_page") or 0
	local max_pages = math.floor(#product_list / product_count)
	
	if product_page > max_pages then
		product_page = max_pages
		meta:set_int("product_page", product_page)
	elseif product_page < 0 then
		product_page = 0
		meta:set_int("product_page", product_page)
	end

	local pages = false
	local page_button_y = "7.3"
	if product_page < max_pages then
		inventory[#inventory+1] = "button[9,"..page_button_y..";1,0.75;next_page;»]"
		inventory[#inventory+1] = "tooltip[next;"..S("Next page of crafting products").."]"
		page_button_y = "8.0"
		pages = true
	end
	if product_page > 0 then
		inventory[#inventory+1] = "button[9,"..page_button_y..";1,0.75;prev_page;«]"
		inventory[#inventory+1] = "tooltip[prev;"..S("Previous page of crafting products").."]"
		pages = true
	end
	if pages then
		inventory[#inventory+1] = "label[9.2,6.25;" .. S("Page @1", tostring(product_page+1)) .. "]"
	end
		
	for i = 1, product_count do
		local current_item = product_list[i + product_page*product_count]
		if current_item then
			inventory[#inventory+1] = "item_image_button[" ..
			corner_x + (i-1)%product_x_dim .. "," .. corner_y + math.floor((i-1)/product_x_dim) ..
			";1,1;" .. current_item.name .. ";product_".. i + product_page*product_count ..
			";\n\n       " .. current_item.count .. "]"
		else
			inventory[#inventory+1] = "item_image_button[" ..
			corner_x + (i-1)%product_x_dim .. "," .. corner_y + math.floor((i-1)/product_x_dim) ..
			";1,1;;empty;]"
		end
	end
	
	-----------------
	
	if autocraft_def.show_guides then
		inventory[#inventory+1] = "button[9,9.5;1,0.75;show_guide;"..S("Show\nGuide").."]"
	end
	
	meta:set_string("formspec", table.concat(inventory))
end

local function refresh_products(meta)
	local inv = meta:get_inventory()
	local craftable = simplecrafting_lib.get_craftable_items(craft_type, inv:get_list("input"), false, autocraft_def.alphabetize_items)
	local product_list = {}
	for _, craft in pairs(craftable) do
		table.insert(product_list, craft:to_table())
	end
	meta:set_string("product_list", minetest.serialize(product_list))
end

local function count_items(count_list)
	local totalcount = 0
	for _, itemcount in pairs(count_list) do
		totalcount = totalcount + itemcount
	end
	return totalcount
end

local function on_timer(pos, elapsed)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
		
	local craft_time = meta:get_float("craft_time") or 0.0
	local total_craft_time = meta:get_float("total_craft_time") or 0.0

	local target_item = meta:get_string("target_item")
	
	local recipe
	local recipe_input_count
	local room_for_items = false
	local output
	if target_item ~= "" then
		recipe = simplecrafting_lib.get_crafting_result(craft_type, inv:get_list("input"), ItemStack({name=target_item, count=1}))
		if recipe then
			output = simplecrafting_lib.count_list_add(recipe.output, recipe.returns)
			room_for_items = simplecrafting_lib.room_for_items(inv, "output", output)
			recipe_input_count = count_items(recipe.input)
			total_craft_time = recipe.cooktime or recipe_input_count
			minetest.debug("total_craft_time " .. total_craft_time .. " # input " .. count_items(recipe.input) .. " input " .. dump(recipe.input))
		end
	end

	if autocraft_def.crafting_time_multiplier then
		elapsed = elapsed / autocraft_def.crafting_time_multiplier(pos, recipe)
	end

	craft_time = craft_time + elapsed
	
	if recipe == nil or not room_for_items then
		-- we're not crafting anything.
		craft_time = 0.0
		minetest.get_node_timer(pos):stop()
		if autocraft_def.active_node then -- only bother doing this if there's an active node
			local this_node = minetest.get_node(pos)
			this_node.name = meta:get_string("inactive_node")
			minetest.swap_node(pos, this_node)
		end
	else
		
		while true do
			if craft_time >= (recipe.cooktime or recipe_input_count) then
				-- produce product
				simplecrafting_lib.add_items(inv, "output", output)
				simplecrafting_lib.remove_items(inv, "input", recipe.input)
				craft_time = craft_time - (recipe.cooktime or recipe_input_count)
				minetest.get_node_timer(pos):start(1)
				break
			else
				-- if we get here craft time hasn't reached recipe time yet.
				-- Do nothing this round.
				if autocraft_def.active_node then
					local this_node = minetest.get_node(pos)
					this_node.name = autocraft_def.active_node
					minetest.swap_node(pos, this_node)
				end
				minetest.get_node_timer(pos):start(1)
				break
			end
		end
	end

	meta:set_float("craft_time", craft_time)	
	meta:set_float("total_craft_time", total_craft_time)	

	refresh_formspec(meta)
end

local on_construct = function(pos)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	inv:set_size("input", 2*5) -- materials that can be processed to outputs
	inv:set_size("output", 2*6) -- holds output product
	meta:set_string("product_list", minetest.serialize({}))
	meta:set_string("target", "")
	if autocraft_def.active_node then
		meta:set_string("inactive_node", minetest.get_node(pos).name) -- we only need this if there's an active node defined
	end
	refresh_formspec(meta)
end

local _pipeworks_override_player = {} -- Horrible hack. Pipeworks gets to insert stuff regardless of protection.

local function allow_metadata_inventory_put(pos, listname, index, stack, player)
	if autocraft_def.protect_inventory and
		player ~= _pipeworks_override_player and
		minetest.is_protected(pos, player:get_player_name())
		and not minetest.check_player_privs(player:get_name(), "protection_bypass") then
		return 0
	end
	if listname == "input" then
		if simplecrafting_lib.is_possible_input(craft_type, stack:get_name()) then
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

-- Pipeworks compatibility
local tube = nil
if autocraft_def.enable_pipeworks and minetest.get_modpath("pipeworks") then
	tube = {
		insert_object = function(pos, node, stack, direction)
			local meta = minetest.get_meta(pos)
			local inv = meta:get_inventory()
			return inv:add_item("input", stack)
		end,
		can_insert = function(pos, node, stack, direction)
			local meta = minetest.get_meta(pos)
			local inv = meta:get_inventory()
			return allow_metadata_inventory_put(pos, "input", 1, stack, _pipeworks_override_player) > 0 and inv:room_for_item("input", stack)
		end,
		input_inventory = "input",
		connect_sides = {left = 1, right = 1, back = 1, bottom = 1, top = 1}
	}
end

local function allow_metadata_inventory_take(pos, listname, index, stack, player)
	if autocraft_def.protect_inventory and
		minetest.is_protected(pos, player:get_player_name())
		and not minetest.check_player_privs(player:get_name(), "protection_bypass") then
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
	return inv:is_empty("output") and inv:is_empty("input")
end
	
local on_receive_fields = function(pos, formname, fields, sender)
	local meta = minetest.get_meta(pos)
	local product_list = minetest.deserialize(meta:get_string("product_list"))

	for field, _ in pairs(fields) do
		if field == "target" then
			meta:set_string("target_item", "")
			meta:set_float("craft_time", 0.0)
			meta:set_float("total_craft_time", 0.0)
		elseif string.sub(field, 1, 8) == "product_" then
			local new_target = product_list[tonumber(string.sub(field, 9))].name
			meta:set_string("target_item", new_target)
			meta:set_float("craft_time", 0.0)
			meta:set_string("last_selector_name", sender:get_player_name())
			refresh_formspec(meta)
		end
	end
	
	if fields.show_guide and autocraft_def.show_guides then
		simplecrafting_lib.show_crafting_guide(craft_type, sender)
	end
	
	if fields.next_page then
		meta:set_int("product_page", meta:get_int("product_page") + 1)
		refresh_formspec(meta)
	elseif fields.prev_page then
		meta:set_int("product_page", meta:get_int("product_page") - 1)	
		refresh_formspec(meta)
	end
	
	on_timer(pos, 0)
end

return {
	allow_metadata_inventory_move = allow_metadata_inventory_move,
	allow_metadata_inventory_put = allow_metadata_inventory_put,
	allow_metadata_inventory_take = allow_metadata_inventory_take,
	can_dig = can_dig,
	on_construct = on_construct,
	on_metadata_inventory_move = on_metadata_inventory_move,
	on_metadata_inventory_put = on_metadata_inventory_put,
	on_metadata_inventory_take = on_metadata_inventory_take,
	on_receive_fields = on_receive_fields,
	on_timer = on_timer,
	tube = tube,
}
end
