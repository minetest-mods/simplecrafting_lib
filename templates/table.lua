local MP = minetest.get_modpath(minetest.get_current_modname())
local S, NS = dofile(MP.."/intllib.lua")

local modpath_default = minetest.get_modpath("default")

-- table_def can have the following:
--{
--	show_guides = true or false,
--	alphabetize_items = true or false,
--	description = string,
--	hopper_node_name = string,
--	enable_pipeworks = true or false,
--}

simplecrafting_lib.generate_table_functions = function(craft_type, table_def)

if table_def == nil then
	table_def = {}
end

-- Hopper compatibility
if table_def.hopper_node_name and minetest.get_modpath("hopper") and hopper ~= nil and hopper.add_container ~= nil then
	hopper:add_container({
		{"top", table_def.hopper_node_name, "input"},
		{"bottom", table_def.hopper_node_name, "input"},
		{"side", table_def.hopper_node_name, "input"},
	})
end

local function refresh_output(inv, max_mode)
	local craftable = simplecrafting_lib.get_craftable_items(craft_type, inv:get_list("input"), max_mode, table_def.alphabetize_items)
	inv:set_size("output", #craftable + ((8*6) - (#craftable%(8*6))))
	inv:set_list("output", craftable)
end

local function make_formspec(row, item_count, max_mode)
	if item_count < (8*6) then
		row = 0
	elseif (row*8)+(8*6) > item_count then
		row = (item_count - (8*6)) / 8
	end

	local inventory = {
		"size[10.2,10.2]",
		"list[context;input;0,0.5;2,5;]",
		"list[context;output;2.2,0;8,6;" , tostring(row*8), "]",
		"list[current_player;main;1.1,6.25;8,1;]",
		"list[current_player;main;1.1,7.5;8,3;8]",
		"listring[context;output]",
		"listring[current_player;main]",
		"listring[context;input]",
		"listring[current_player;main]",
	}
	
	if table_def.description then
		inventory[#inventory+1] = "label[0,0;"..table_def.description.."]"
	end
	
	if modpath_default then
		inventory[#inventory+1] = default.gui_bg
		inventory[#inventory+1] = default.gui_bg_img
		inventory[#inventory+1] = default.gui_slots
	end
	
	local pages = false
	local page_button_y = "7.3"
	if item_count > ((row/6)+1) * (8*6) then
		inventory[#inventory+1] = "button[9.3,"..page_button_y..";1,0.75;next;»]"
		inventory[#inventory+1] = "tooltip[next;"..S("Next page of crafting products").."]"
		page_button_y = "8.0"
		pages = true
	end
	if row >= 6 then
		inventory[#inventory+1] = "button[9.3,"..page_button_y..";1,0.75;prev;«]"
		inventory[#inventory+1] = "tooltip[prev;"..S("Previous page of crafting products").."]"
		pages = true
	end
	if pages then
		inventory[#inventory+1] = "label[9.3,6.5;" .. S("Page @1", tostring(row/6+1)) .. "]"
	end
	
	if max_mode then
		inventory[#inventory+1] = "button[9.3,8.7;1,0.75;max_mode;"..S("Max\nOutput").."]"
	else
		inventory[#inventory+1] = "button[9.3,8.7;1,0.75;max_mode;"..S("Min\nOutput").."]"
	end
	
	if table_def.show_guides then
		inventory[#inventory+1] = "button[9.3,9.7;1,0.75;show_guide;"..S("Show\nGuide").."]"
	end

	return table.concat(inventory), row
end

local function refresh_inv(meta)
	local inv = meta:get_inventory()
	local max_mode = meta:get_string("max_mode")
	refresh_output(inv, max_mode == "True")

	local page = meta:get_int("page")
	local form, page = make_formspec(page, inv:get_size("output"), max_mode == "True")
	meta:set_int("page", page)
	meta:set_string("formspec", form)
end

local on_construct = function(pos)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	inv:set_size("input", 2*5)
	inv:set_size("output", 8*6)
	meta:set_int("row", 0)
	meta:set_string("formspec", make_formspec(0, 0, true))
end
	
local allow_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, number, player)
	if to_list == "output" then
		return 0
	end
	if table_def.protect_inventory and
		minetest.is_protected(pos, player:get_player_name())
		and not minetest.check_player_privs(player:get_name(), "protection_bypass") then
		return 0
	end
	if to_list == "input" then
		if from_list == "input" then
			return number
		end
		local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()
		local stack = inv:get_stack(from_list, from_index)
		if simplecrafting_lib.is_possible_input(craft_type, stack:get_name()) then
			return number
		end
	end
	return 0
end

local _pipeworks_override_player = {} -- Horrible hack. Pipeworks gets to insert stuff regardless of protection.

local allow_metadata_inventory_put = function(pos, list_name, index, stack, player)
	if table_def.protect_inventory and
		player ~= _pipeworks_override_player and
		minetest.is_protected(pos, player:get_player_name())
		and not minetest.check_player_privs(player:get_name(), "protection_bypass") then
		return 0
	end
	if list_name == "output" then
		return 0
	end
	if list_name == "input" and simplecrafting_lib.is_possible_input(craft_type, stack:get_name()) then
		return stack:get_count()
	end
	return 0
end

-- Pipeworks compatibility
local tube = nil
if table_def.enable_pipeworks and minetest.get_modpath("pipeworks") then
	tube = {
		insert_object = function(pos, node, stack, direction)
			local meta = minetest.get_meta(pos)
			local inv = meta:get_inventory()
			return inv:add_item("main", stack)
		end,
		can_insert = function(pos, node, stack, direction)
			local meta = minetest.get_meta(pos)
			local inv = meta:get_inventory()
			return allow_metadata_inventory_put(pos, "input", 1, stack, _pipeworks_override_player) > 0 and inv:room_for_item("main", stack)
		end,
		input_inventory = "main",
		connect_sides = {left = 1, right = 1, back = 1, bottom = 1, top = 1}
	}
end

local function allow_metadata_inventory_take(pos, listname, index, stack, player)
	if table_def.protect_inventory and
		minetest.is_protected(pos, player:get_player_name())
		and not minetest.check_player_privs(player:get_name(), "protection_bypass") then
		return 0
	end
	return stack:get_count()
end
	
local on_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, number, player)
	local meta = minetest.get_meta(pos)
	if from_list == "output" and to_list == "input" then
		local inv = meta:get_inventory()
		local stack = inv:get_stack(to_list, to_index)
		simplecrafting_lib.craft_stack(craft_type, stack, inv, "input", inv, to_list, player)
	end
	refresh_inv(meta)
end
	
local on_metadata_inventory_take = function(pos, list_name, index, stack, player)
	local meta = minetest.get_meta(pos)
	if list_name == "output" then
		local inv = meta:get_inventory()
		simplecrafting_lib.craft_stack(craft_type, stack, inv, "input", player:get_inventory(), "main", player)
	end
	refresh_inv(meta)
end
	
local on_metadata_inventory_put = function(pos, list_name, index, stack, player)
	local meta = minetest.get_meta(pos)
	refresh_inv(meta)
end
	
local on_receive_fields = function(pos, formname, fields, sender)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	local size = inv:get_size("output")
	local row = meta:get_int("row")
	local max_mode = meta:get_string("max_mode")
	local refresh = false
	if fields.next then
		minetest.sound_play("paperflip1", {to_player=sender:get_player_name(), gain = 1.0})
		row = row + 6
	elseif fields.prev  then
		minetest.sound_play("paperflip2", {to_player=sender:get_player_name(), gain = 1.0})
		row = row - 6
	elseif fields.max_mode then
		if max_mode == "" then
			max_mode = "True"
		else
			max_mode = ""
		end
		refresh = true
	elseif fields.show_guide and table_def.show_guides then
		simplecrafting_lib.show_crafting_guide(craft_type, sender)
	else
		return
	end
	if refresh then
		refresh_output(inv, max_mode == "True")
	end
	
	meta:set_string("max_mode", max_mode)
	local form, row = make_formspec(row, size, max_mode == "True")
	meta:set_int("row", row)
	meta:set_string("formspec", form)
end
	
local can_dig = function(pos, player)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	return inv:is_empty("input")
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
	tube = tube,
}
end