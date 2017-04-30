local MP = minetest.get_modpath(minetest.get_current_modname())
local S, NS = dofile(MP.."/intllib.lua")

local alphabetize_items = crafting.config.sort_alphabetically

local function refresh_output(inv, max_mode)
	local craftable = crafting.get_craftable_items("table", inv:get_list("store"), max_mode, alphabetize_items)
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
		"size[10.2,10.2]"
		, default.gui_bg
		, default.gui_bg_img
		, default.gui_slots
		, "list[context;store;0,0.5;2,5;]"
		, "list[context;output;2.2,0;8,6;" , tostring(row*8), "]"
		, "list[current_player;main;1.1,6.25;8,1;]"
		, "list[current_player;main;1.1,7.5;8,3;8]"
		, "listring[context;output]"
		, "listring[current_player;main]"
		, "listring[context;store]"
		, "listring[current_player;main]"
	}
	
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
		inventory[#inventory+1] = "button[9.3,8.7;1,0.75;max_mode;Max\nOutput]"
	else
		inventory[#inventory+1] = "button[9.3,8.7;1,0.75;max_mode;Min\nOutput]"
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


local function take_craft(inv, target_inv, target_list, stack, player)
	local craft_result = crafting.get_crafting_result("table", inv:get_list("store"), stack)
	if craft_result then
		if crafting.remove_items(inv, "store", craft_result.input) then
			-- We've successfully paid for this craft's output.
			local item_name = stack:get_name()
			
			-- log it
			minetest.log("action", S("@1 crafts @2", player:get_player_name(), item_name .. " " .. tostring(craft_result.output[item_name])))
					
			-- subtract the amount of output that the player's getting anyway (from having taken it)
			craft_result.output[item_name] = craft_result.output[item_name] - stack:get_count() 
			
			-- stuff the output in the target inventory, or the player's inventory if it doesn't fit, finally dropping anything that doesn't fit at the player's location
			local leftover = crafting.add_items(target_inv, target_list, craft_result.output)
			leftover = crafting.add_items(player:get_inventory(), "main", leftover)
			crafting.drop_items(player:getpos(), leftover)
				
			-- Put returns into the store first, or player's inventory if it doesn't fit, or drop it at player's location as final fallback
			leftover = crafting.add_items(inv, "store", craft_result.returns)
			leftover = crafting.add_items(player:get_inventory(), "main", leftover)
			crafting.drop_items(player:getpos(), leftover)
		end
	end
end

minetest.register_node("crafting:table", {
	description = S("Crafting Table"),
	drawtype = "normal",
	tiles = {"crafting.table_top.png", "default_chest_top.png",
		"crafting.table_front.png", "crafting.table_front.png",
		"crafting.table_side.png", "crafting.table_side.png"},
	sounds = default.node_sound_wood_defaults(),
	paramtype2 = "facedir",
	is_ground_content = false,
	groups = {oddly_breakable_by_hand = 1, choppy=3},
	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()
		inv:set_size("store", 2*5)
		inv:set_size("output", 8*6)
		meta:set_int("row", 0)
		meta:set_string("formspec", make_formspec(0, 0, true))
	end,
	allow_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, number, player)
		if to_list == "output" then
			return 0
		end
		return number
	end,
	allow_metadata_inventory_put = function(pos, list_name, index, stack, player)
		if list_name == "output" then
			return 0
		end
		return stack:get_count()
	end,
	on_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, number, player)
		local meta = minetest.get_meta(pos)
		if from_list == "output" and to_list == "store" then
			local inv = meta:get_inventory()
			local stack = inv:get_stack(to_list, to_index)
			take_craft(inv, inv, to_list, stack, player)
		end
		refresh_inv(meta)
	end,
	on_metadata_inventory_take = function(pos, list_name, index, stack, player)
		local meta = minetest.get_meta(pos)
		if list_name == "output" then
			local inv = meta:get_inventory()
			take_craft(inv, player:get_inventory(), "main", stack, player)			
		end
		refresh_inv(meta)
	end,
	on_metadata_inventory_put = function(pos, list_name, index, stack, player)
		local meta = minetest.get_meta(pos)
		refresh_inv(meta)
	end,
	on_receive_fields = function(pos, formname, fields, sender)
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
			minetest.sound_play("paperflip1", {to_player=sender:get_player_name(), gain = 1.0})
			row = row - 6
		elseif fields.max_mode then
			if max_mode == "" then
				max_mode = "True"
			else
				max_mode = ""
			end
			refresh = true
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
	end,
	can_dig = function(pos, player)
		local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()
		return inv:is_empty("store")
	end,
})
