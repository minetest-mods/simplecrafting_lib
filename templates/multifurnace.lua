local MP = minetest.get_modpath(minetest.get_current_modname())
local S, NS = dofile(MP.."/intllib.lua")

-- multifurnace_def can have the following:
--{
--	show_guides = true or false,
--	alphabetize_items = true or false,
--	description = string,
--	hopper_node_name = string,
--	enable_pipeworks = true or false,
--	protect_inventory = true or false
--	crafting_time_multiplier = function(pos, recipe)
--	active_node = string,
--	lock_in_mode = "count" | "endless",
--	append_to_formspec = string,
--}

local modpath_default = minetest.get_modpath("default")

simplecrafting_lib.generate_multifurnace_functions = function(craft_type, fuel_type, multifurnace_def)

if multifurnace_def == nil then
	multifurnace_def = {}
end

-- Hopper compatibility
if multifurnace_def.hopper_node_name and minetest.get_modpath("hopper") and hopper ~= nil and hopper.add_container ~= nil then

	hopper:add_container({
		{"top", multifurnace_def.hopper_node_name, "output"},
		{"bottom", multifurnace_def.hopper_node_name, "input"},
		{"side", multifurnace_def.hopper_node_name, "fuel"},
	})
	
	if multifurnace_def.active_node then
		hopper:add_container({
			{"top", multifurnace_def.active_node, "output"},
			{"bottom", multifurnace_def.active_node, "input"},
			{"side", multifurnace_def.active_node, "fuel"},
		})
	end
end

local function get_count_mode(meta)
	if multifurnace_def.lock_in_mode == "endless" then
		return false
	elseif multifurnace_def.lock_in_mode == "count" then
		return true
	else
		return meta:get_string("count_mode") == "true"
	end
end

local function refresh_formspec(pos)
	local meta = minetest.get_meta(pos)
	local cook_time = meta:get_float("cook_time") or 0.0
	local total_cook_time = meta:get_float("total_cook_time") or 0.0
	local burn_time = meta:get_float("burn_time") or 0.0
	local total_burn_time = meta:get_float("total_burn_time") or 0.0
	local product_count = meta:get_int("product_count") or 0
	local count_mode = get_count_mode(meta)
	
	local item_percent
	if total_cook_time > 0 then item_percent = math.floor((math.min(cook_time, total_cook_time) / total_cook_time) * 100) else item_percent = 0 end
	local burn_percent
	if total_burn_time > 0 then burn_percent = math.floor((math.min(burn_time, total_burn_time) / total_burn_time) * 100) else burn_percent = 0 end

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

	if count_mode then
		inventory[#inventory+1] = "field[4.8,1.7;1,0.25;product_count;;"..product_count.."]"
		inventory[#inventory+1] = "field_close_on_enter[product_count;false]"
		if multifurnace_def.lock_in_mode == nil then
			inventory[#inventory+1] = "button[9,7.5;1,0.75;count_mode;"..S("Endless\nOutput").."]"
		end
	elseif multifurnace_def.lock_in_mode == nil then
		inventory[#inventory+1] = "button[9,7.5;1,0.75;count_mode;"..S("Counted\nOutput").."]"	
	end
	
	if multifurnace_def.description then
		inventory[#inventory+1] = "label[4.5,0;"..multifurnace_def.description.."]"
	end
	
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

	local product_x_dim = 4
	local product_y_dim = 2
	local corner_x = 6
	local corner_y = 2.75
	local product_count = product_x_dim * product_y_dim

	local product_list = minetest.deserialize(meta:get_string("product_list"))
	local product_page = meta:get_int("product_page") or 0
	local max_pages = math.floor((#product_list - 1) / product_count)
	
	if product_page > max_pages then
		product_page = max_pages
		meta:set_int("product_page", product_page)
	elseif product_page < 0 then
		product_page = 0
		meta:set_int("product_page", product_page)
	end
	
	local pages = false
	if product_page > 0 then
		inventory[#inventory+1] = "button[6.0,2.5;1,0.1;prev_page;<<]"	
	end
	if product_page < max_pages then
		inventory[#inventory+1] = "button[9.0,2.5;1,0.1;next_page;>>]"			
	end
	if pages then
		inventory[#inventory+1] = "label[9.3,2.5;" .. S("Page @1", tostring(product_page)) .. "]"
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
	
	if multifurnace_def.show_guides then
		inventory[#inventory+1] = "button[9.0,8.3;1,0.75;show_guide;"..S("Show\nGuide").."]"
	end
	
	if multifurnace_def.append_to_formspec then
		inventory[#inventory+1] = table_def.append_to_formspec
	end
	
	meta:set_string("formspec", table.concat(inventory))
	meta:set_string("infotext", multifurnace_def.get_infotext(pos))
end

local function refresh_products(meta)
	local inv = meta:get_inventory()
	local craftable = simplecrafting_lib.get_craftable_items(craft_type, inv:get_list("input"), false, multifurnace_def.alphabetize_items)
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
	local product_count = meta:get_int("product_count") or 0
	local count_mode = get_count_mode(meta)

	local target_item = meta:get_string("target_item")
	
	local recipe
	local room_for_items = false
	local output
	if target_item ~= "" then
		recipe = simplecrafting_lib.get_crafting_result(craft_type, inv:get_list("input"), ItemStack({name=target_item, count=1}))
		if recipe then
			output = simplecrafting_lib.count_list_add({[recipe.output:get_name()]=recipe.output:get_count()}, recipe.returns)
			room_for_items = simplecrafting_lib.room_for_items(inv, "output", output)
			total_cook_time = recipe.input["simplecrafting_lib:heat"] or 1
			if multifurnace_def.crafting_time_multiplier then
				total_cook_time = total_cook_time * multifurnace_def.crafting_time_multiplier(pos, recipe)
			end
		end
	end
	
	cook_time = cook_time + elapsed
	burn_time = burn_time - elapsed
	
	if recipe == nil or not room_for_items or (product_count <= 0 and count_mode) then
		-- we're not cooking anything.
		cook_time = 0.0
		if burn_time < 0 then burn_time = 0 end
		minetest.get_node_timer(pos):stop()
		if multifurnace_def.active_node then -- only bother doing this if there's an active node
			local this_node = minetest.get_node(pos)
			this_node.name = meta:get_string("inactive_node")
			minetest.swap_node(pos, this_node)
		end
	else
		while true do
			if burn_time < 0 then
				-- burn some fuel, if possible.
				local fuel_recipes = simplecrafting_lib.get_fuels(fuel_type, inv:get_list("fuel"))
				local longest_burning
				for _, fuel_recipe in pairs(fuel_recipes) do
					local recipe_burntime = 0
					if fuel_recipe.output and fuel_recipe.output:get_name() == "simplecrafting_lib:heat" then
						recipe_burntime = fuel_recipe.output:get_count()
					end
					if longest_burning == nil or longest_burning.output:get_count() < recipe_burntime then
						longest_burning = fuel_recipe
					end
				end
						
				if longest_burning then
					total_burn_time = longest_burning.output:get_count()
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
			elseif cook_time >= total_cook_time then
				-- produce product
				if count_mode then
					product_count = product_count - recipe.output:get_count()
					meta:set_int("product_count", math.max(product_count, 0))
				end
				simplecrafting_lib.add_items(inv, "output", output)
				simplecrafting_lib.remove_items(inv, "input", recipe.input)
				simplecrafting_lib.execute_post_craft(craft_type, recipe, recipe.output, inv, "input", inv, "output")
				cook_time = cook_time - total_cook_time
				minetest.get_node_timer(pos):start(1)
				break
			else
				-- if we get here there's burning fuel but cook time hasn't reached recipe time yet.
				-- Do nothing this round.
				if multifurnace_def.active_node then
					local this_node = minetest.get_node(pos)
					this_node.name = multifurnace_def.active_node
					minetest.swap_node(pos, this_node)
				end
				minetest.get_node_timer(pos):start(1)
				break
			end
		end
	end

	meta:set_float("burn_time", burn_time)
	meta:set_float("total_burn_time", total_burn_time)
	meta:set_float("cook_time", cook_time)	
	meta:set_float("total_cook_time", total_cook_time)	

	refresh_formspec(pos)
end

local on_construct = function(pos)
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	inv:set_size("input", 2*4) -- materials that can be processed to outputs
	inv:set_size("fuel", 2*4) -- materials that can be burned for fuel
	inv:set_size("output", 2*4) -- holds output product
	meta:set_string("product_list", minetest.serialize({}))
	meta:set_string("target", "")
	if multifurnace_def.active_node then
		meta:set_string("inactive_node", minetest.get_node(pos).name) -- we only need this if there's an active node defined
	end
	refresh_formspec(pos)
end

local _pipeworks_override_player = {} -- Horrible hack. Pipeworks gets to insert stuff regardless of protection.

local function allow_metadata_inventory_put(pos, listname, index, stack, player)
	if multifurnace_def.protect_inventory and
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

-- Pipeworks compatibility
local tube = nil
if multifurnace_def.enable_pipeworks and minetest.get_modpath("pipeworks") then
	tube = {
		insert_object = function(pos, node, stack, direction)
			local meta = minetest.get_meta(pos)
			local inv = meta:get_inventory()
			local timer = minetest.get_node_timer(pos)
			if not timer:is_started() then
				timer:start(1.0)
			end
			if direction.y == 1 then
				return inv:add_item("fuel", stack)
			else
				return inv:add_item("input", stack)
			end
		end,
		can_insert = function(pos,node,stack,direction)
			local meta = minetest.get_meta(pos)
			local inv = meta:get_inventory()
			if direction.y == 1 then
				return allow_metadata_inventory_put(pos, "fuel", 1, stack, _pipeworks_override_player) > 0
					and inv:room_for_item("fuel", stack)
			else
				return allow_metadata_inventory_put(pos, "input", 1, stack, _pipeworks_override_player) > 0
					and inv:room_for_item("input", stack)
			end
		end,
		input_inventory = "output",
		connect_sides = {left = 1, right = 1, back = 1, front = 1, bottom = 1, top = 1}
	}
end

local function allow_metadata_inventory_take(pos, listname, index, stack, player)
	if multifurnace_def.protect_inventory and
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
		refresh_formspec(pos)
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
	local refresh = false

	for field, _ in pairs(fields) do
		if field == "target" then
			meta:set_string("target_item", "")
			meta:set_float("cook_time", 0.0)
			meta:set_float("total_cook_time", 0.0)
		elseif string.sub(field, 1, 8) == "product_" then
			local product = product_list[tonumber(string.sub(field, 9))]
			if product then
				local new_target = product.name
				meta:set_string("target_item", new_target)
				meta:set_float("cook_time", 0.0)
				meta:set_string("last_selector_name", sender:get_player_name())
				refresh = true
			end
		end
	end
	
	if fields.show_guide and multifurnace_def.show_guides then
		simplecrafting_lib.show_crafting_guide(craft_type, sender)
	end
	
	if fields.product_count ~= nil then
		meta:set_int("product_count", math.max((tonumber(fields.product_count) or 0), 0))
		refresh = true
	end
	
	if fields.count_mode then
		if meta:get_string("count_mode") == "" then
			meta:set_string("count_mode", "true")
		else
			meta:set_string("count_mode", "")
		end
		refresh = true
	end
	
	if fields.next_page then
		meta:set_int("product_page", meta:get_int("product_page") + 1)
		refresh = true
	elseif fields.prev_page then
		meta:set_int("product_page", meta:get_int("product_page") - 1)	
		refresh = true
	end
	
	if refresh then
		refresh_formspec(pos)
	end
	
	on_timer(pos, 0)
end

local function default_infotext(pos)
	local infotext = ""
	local meta = minetest.get_meta(pos)

	if multifurnace_def.description then
		infotext = infotext .. multifurnace_def.description
	end

	local target = meta:get_string("target_item")
	if target ~= "" then
		local craft_time = meta:get_float("cook_time") or 0.0
		local total_craft_time = meta:get_float("total_cook_time") or 0.0
		local item_percent
		if total_craft_time > 0 then item_percent = math.floor((math.min(craft_time, total_craft_time) / total_craft_time) * 100) else item_percent = 0 end	

		infotext = infotext .. "\n" .. S("@1% done crafting @2", item_percent, minetest.registered_items[target].description or target)
		
		if get_count_mode(meta) then
			local product_count = meta:get_int("product_count") or 0
			infotext = infotext .. "\n" .. S("@1 remaining to do", product_count)
		end
	end
	
	return infotext	
end
multifurnace_def.get_infotext = multifurnace_def.get_infotext or default_infotext

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
