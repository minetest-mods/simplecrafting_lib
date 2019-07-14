local MP = minetest.get_modpath(minetest.get_current_modname())
local S, NS = dofile(MP.."/intllib.lua")
local F = minetest.formspec_escape

local modpath_default = minetest.get_modpath("default")
local modpath_awards = minetest.get_modpath("awards")
local modpath_sfinv = minetest.get_modpath("sfinv")
local modpath_unified_inventory = minetest.get_modpath("unified_inventory")

-- table_def can have the following:
--{
--	alphabetize_items = true or false,
--	description = string,
--	append_to_formspec = string,
--	input_width = number,	-- height and width of the input inventory. Note that if you make this too small some recipes may no longer be craftable.
--	input_height = number,
--	output_width = number,	-- height and width of the output inventory
--	output_height = number,
--	controls_x = number,	-- location of the column of controls for controlling output display
--	controls_y = number,
--}

simplecrafting_lib.register_player_craft_type = function(craft_type, table_def)

if table_def == nil then
	table_def = {}
end

local input_width = table_def.input_width or 2
local input_height = table_def.input_height or 5
local output_width = table_def.output_width or 8
local output_height = table_def.output_height or 6
local controls_x = table_def.controls_x or 9.3
local controls_y = table_def.controls_y or 6.5

local input_list_name = craft_type .. "_input"

local input_count = input_width * input_height
local output_count = output_width * output_height

local show_player_inventory = true
-- Unified inventory has strict limitations on the size of the crafting interface, and
-- has a hard-coded player inventory display
if modpath_unified_inventory then
	input_width = 2
	input_height = 4
	output_width = 5
	output_height = 4
	controls_x = 7.3
	controls_y = 0
	show_player_inventory = false
end

-- This is to vertically align the input and output inventories,
-- keeping them centered relative to each other.
local y_displace_input = 0
local y_displace_output = 0
if input_height < output_height then
	y_displace_input = (output_height-input_height)/2
elseif input_height > output_height then
	y_displace_output = (input_height-output_height)/2
end

-- pre-declare this so that get_or_create_context can reference it
local refresh_inv

local get_or_create_context = function(player)
	local player_name = player:get_player_name()
	local context

	if modpath_sfinv then
		context = sfinv.get_or_create_context(player)
--	elseif modpath_unified_inventory then
--		context = unified_inventory.get_per_player_formspec(player:get_player_name())
	else
		simplecrafting_lib.player_contexts = simplecrafting_lib.player_contexts or {}
		context = simplecrafting_lib.player_contexts[player_name]
		if not context then
			context = {}
			simplecrafting_lib.player_contexts[player_name] = context
		end
	end
	if context.simplecrafting_lib_row == nil then context.simplecrafting_lib_row = 0 end -- the currently selected output page
	
	-- Create a detached inventory to hold prospective crafting outputs
	if context.simplecrafting_lib_output_inventory_name == nil then
		context.simplecrafting_lib_output_inventory_name = "simplecrafting_" .. craft_type .. "_" .. player_name
	end

	if context.simplecrafting_lib_output_inventory == nil then
		context.simplecrafting_lib_output_inventory = minetest.create_detached_inventory(context.simplecrafting_lib_output_inventory_name, {
			allow_move = function(inv, from_list, from_index, to_list, to_index, count, player)
				return 0
			end,
			allow_put = function(inv, listname, index, stack, player)
				return 0
			end,
			allow_take = function(inv, listname, index, stack, player)
				return -1
			end,
			on_move = function(inv, from_list, from_index, to_list, to_index, count, player)
			end,
			on_take = function(inv, listname, index, stack, player)
				if stack and stack:get_count() > 0 then
					local player_inv = minetest.get_inventory({type="player", name=player_name})
					if listname == "main" then
						simplecrafting_lib.craft_stack(craft_type, stack, player_inv, input_list_name, player_inv, input_list_name, player)
						if modpath_awards then
							awards.increment_item_counter(awards.players[player:get_player_name()], "craft", ItemStack(stack):get_name(), ItemStack(stack):get_count()) 
						end
					end
					refresh_inv(player_inv, player)
					return stack:get_count()
				end
			end,
		}, player_name)
		if context.simplecrafting_lib_output_inventory == nil then
			minetest.log("error", "[simplecrafting_lib] get_or_create_context failed to create a detached inventory to hold crafting outputs")
		end
	end
	if context.simplecrafting_lib_max_mode == nil then context.simplecrafting_lib_max_mode = false end
	return context
end

refresh_inv = function(player_inv, player)
	local context = get_or_create_context(player)
	local max_mode = context.simplecrafting_lib_max_mode

	local craftable = simplecrafting_lib.get_craftable_items(craft_type, player_inv:get_list(input_list_name), max_mode, table_def.alphabetize_items)
	-- Output size is the number of multiples of output_count that we can fit the craftable outputs into,
	-- with a minimum of one multuple so there's an empty page if there's no recipes to craft
	local output_size = math.max(math.ceil(#craftable / output_count), 1) * output_count
	context.simplecrafting_lib_output_inventory:set_size("main", output_size)
	context.simplecrafting_lib_output_inventory:set_list("main", craftable)
	
	if modpath_unified_inventory then
		local player_name = player:get_player_name()
		unified_inventory.set_inventory_formspec(player, unified_inventory.current_page[player_name])
	elseif modpath_sfinv then
		sfinv.set_player_inventory_formspec(player, context)
	end
end

local make_formspec = function(player)
	local context = get_or_create_context(player)
	local row = context.simplecrafting_lib_row or 0
	local item_count
	if context.simplecrafting_lib_output_inventory then
		item_count = context.simplecrafting_lib_output_inventory:get_size("main")
	else
		item_count = output_count
	end
	local max_mode = context.simplecrafting_lib_max_mode or false
	local output_inventory = context.simplecrafting_lib_output_inventory_name

	if item_count < output_count then
		row = 0
		context.simplecrafting_lib_row = row
	elseif (row*output_width)+output_count > item_count then
		row = (item_count - output_count) / output_width
		context.simplecrafting_lib_row = row
	end
	
	local inventory = {
		"list[current_player;"..input_list_name..";0,"..y_displace_input..";"..input_width..","..input_height..";]"..
		"list[detached:"..output_inventory..";main;"..tostring(input_width+0.2)..","..y_displace_output..";"..output_width..","..output_height..";"..tostring(row*output_width), "]",
	}
	if show_player_inventory then
		inventory[#inventory+1] = "list[current_player;main;1.1,"..tostring(output_height+0.25)..";8,1;]"..
									"list[current_player;main;1.1,"..tostring(output_height+1.5)..";8,3;8]"
	end
	inventory[#inventory+1] = "listring[detached:"..output_inventory..";main]"..
								"listring[current_player;main]"..
								"listring[current_player;"..input_list_name.."]"..
								"listring[current_player;main]"
	
	if table_def.description then
		inventory[#inventory+1] = "label[0,0;"..table_def.description.."]"
	end
	
	if modpath_default then
		inventory[#inventory+1] = default.gui_bg .. default.gui_bg_img .. default.gui_slots
	end
	
	local pages = false
	local page_button_y = controls_y + 0.6
	if item_count > ((row/output_height)+1) * output_count then
		inventory[#inventory+1] = "button["..controls_x..","..page_button_y..";1,0.75;next;»]"..
									"tooltip[next;"..F(S("Next page of crafting products")).."]"
		page_button_y = page_button_y + 0.8
		pages = true
	end
	if row >= output_height then
		inventory[#inventory+1] = "button["..controls_x..","..page_button_y..";1,0.75;prev;«]"..
									"tooltip[prev;"..F(S("Previous page of crafting products")).."]"
		pages = true
	end
	if pages then
		inventory[#inventory+1] = "label["..controls_x..","..controls_y..";" .. F(S("Page @1", tostring(row/output_height+1))) .. "]"
	end
	
	if max_mode then
		inventory[#inventory+1] = "button["..controls_x..","..tostring(controls_y+2.2)..";1,0.75;max_mode;"..F(S("Max\nOutput")).."]"
	else
		inventory[#inventory+1] = "button["..controls_x..","..tostring(controls_y+2.2)..";1,0.75;max_mode;"..F(S("Min\nOutput")).."]"
	end
	
	if table_def.append_to_formspec then
		inventory[#inventory+1] = table_def.append_to_formspec
	end

	return table.concat(inventory)
end

minetest.register_on_joinplayer(function(player)
	local player_inv = minetest.get_inventory({type="player", name=player:get_player_name()})
	player_inv:set_size(input_list_name, input_count)
	refresh_inv(player_inv, player)
end)

minetest.register_on_leaveplayer(function(player)
	local player_name = player:get_player_name()
	simplecrafting_lib.player_contexts[player_name] = nil
	minetest.remove_detached_inventory("simplecrafting_" .. craft_type .. "_" .. player_name)
end)

minetest.register_allow_player_inventory_action(function(player, action, inventory, inventory_info)
	if action == "move" then
		if inventory_info.to_list == input_list_name then
			if inventory_info.from_list == input_list_name then
				return inventory_info.count
			end
			local stack = inventory:get_stack(inventory_info.from_list, inventory_info.from_index)
			if simplecrafting_lib.is_possible_input(craft_type, stack:get_name()) then
				return inventory_info.count
			end
			return 0
		end
		if inventory_info.to_list == "main" then
			return inventory_info.count
		end
	end
end)

minetest.register_on_player_inventory_action(function(player, action, inventory, inventory_info)
	if inventory_info.to_list == input_list_name or inventory_info.from_list == input_list_name then
		local context = get_or_create_context(player)
		refresh_inv(inventory, player)
	end	
end)
  
local handle_receive_fields = function(player, fields, context)
	local row = context.simplecrafting_lib_row
	local refresh = false
	if fields.next then
		minetest.sound_play("paperflip1", {to_player=player:get_player_name(), gain = 1.0})
		row = row + output_height
	elseif fields.prev  then
		minetest.sound_play("paperflip2", {to_player=player:get_player_name(), gain = 1.0})
		row = row - output_height
	elseif fields.max_mode then
		context.simplecrafting_lib_max_mode = not context.simplecrafting_lib_max_mode
		refresh = true
	else
		return false
	end
	context.simplecrafting_lib_row = row
	if refresh then
		local player_inv = minetest.get_inventory({type="player", name=player:get_player_name()})
		refresh_inv(player_inv, player)
	end
	return true
end

if modpath_unified_inventory then
	local background = ""
	for x = 0, input_width - 1 do
		for y = 0 + y_displace_input, input_height + y_displace_input - 1 do
			background = background .. "background["..x..","..y..";1,1;ui_single_slot.png]"
		end
	end
	for x = input_width + 0.2, input_width + 0.2 + output_width - 1 do
		for y = 0 + y_displace_output, y_displace_output + output_height - 1 do
			background = background .. "background["..x..","..y..";1,1;ui_single_slot.png]"				
		end
	end

	unified_inventory.register_page("craft", {
		get_formspec = function(player, perplayer_formspec)
			local formspec = make_formspec(player) .. background			

			if unified_inventory.trash_enabled or unified_inventory.is_creative(player_name) or minetest.get_player_privs(player_name).give then
				formspec = formspec.."label["..controls_x..","..tostring(controls_y+2.8)..";" .. F(S("Trash:")) .. "]"
									.."background["..controls_x..","..tostring(controls_y+3.3)..";1,1;ui_single_slot.png]"
									.."list[detached:trash;main;"..controls_x..","..tostring(controls_y+3.3)..";1,1;]"
			end
			--Alas, have run out of room to fit this.
--			if unified_inventory.is_creative(player_name) then
--				formspec = formspec.."label[0,"..(formspecy + 1.5)..";" .. F(S("Refill:")) .. "]"
--				formspec = formspec.."list[detached:"..F(player_name).."refill;main;0,"..(formspecy +2)..";1,1;]"
--			end
			return {formspec=formspec}
		end,
	})
	--unified_inventory.register_page("craftguide", {
	--})
	
	minetest.register_on_player_receive_fields(function(player, formname, fields)
		if formname ~= "" then -- Unified_inventory is using the empty string as its formname.
			return
		end

		local player_name = player:get_player_name()
		local context = get_or_create_context(player)
	
		if handle_receive_fields(player, fields, context) then
			unified_inventory.set_inventory_formspec(player, unified_inventory.current_page[player_name])
			return true
		end
	end)
	
elseif modpath_sfinv then
	sfinv.override_page("sfinv:crafting", {
		title = "Crafting",
		get = function(self, player, context)
			return sfinv.make_formspec(player, context, make_formspec(player), false, "size[10.2,10.2]")
		end,
		on_player_receive_fields = function(self, player, context, fields)
			if handle_receive_fields(player, fields, context) then
				sfinv.set_player_inventory_formspec(player, context)
				return true
			end
		end,
	})
	
	simplecrafting_lib.set_crafting_guide_def(craft_type, {
		output_width = 10,
		output_height = 6,
		recipes_per_page = 3,
	})
	
	sfinv.register_page("simplecrafting_lib:guide_"..craft_type, {
		title = "Guide",
		get = function(self, player, context)
			local formspec, size = simplecrafting_lib.make_guide_formspec(craft_type, player:get_player_name())
			return sfinv.make_formspec(player, context, formspec, false, "size[10.2,10.2]")		
		end,
		on_player_receive_fields = function(self, player, context, fields)
			if simplecrafting_lib.handle_guide_receive_fields(craft_type, player, fields) then
				sfinv.set_player_inventory_formspec(player, context)
				return true
			end		
		end,
	})
	
end

end