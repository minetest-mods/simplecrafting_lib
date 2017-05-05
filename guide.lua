crafting.guide = {}
crafting.guide.outputs = {}
crafting.guide.playerdata = {}
crafting.guide.groups = {}

-- Explicitly set examples for some common input item groups
-- Other mods can also add explicit items like this if they wish
if minetest.get_modpath("default") then
	crafting.guide.groups["wood"] = "default:wood"
	crafting.guide.groups["stick"] = "default:stick"
	crafting.guide.groups["tree"] = "default:tree"
	crafting.guide.groups["stone"] = "default:stone"
end
if minetest.get_modpath("wool") then
	crafting.guide.groups["wool"] = "wool:white"
end

-- internationalization boilerplate
local MP = minetest.get_modpath(minetest.get_current_modname())
local S, NS = dofile(MP.."/intllib.lua")

local function get_group_examples()
	if crafting.guide.groups_initialized then return crafting.guide.groups end
	-- finds an example item for every group that does not already have one defined
	for item, def in pairs(minetest.registered_items) do
		for group, _ in pairs(def.groups) do
			if not crafting.guide.groups[group] then
				crafting.guide.groups[group] = item
			end
		end
	end
	crafting.guide.groups_initialized = true
	return crafting.guide.groups
end

-- splits a string into an array of substrings based on a delimiter
local function split(str, delimiter)
    local result = {}
    for match in (str..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match)
    end
    return result
end

local function find_multi_group(multigroup)
	if crafting.guide.groups[multigroup] then
		return crafting.guide.groups[multigroup]
	end

	local target_groups = split(multigroup, ",")

	for item, def in pairs(minetest.registered_items) do
		local overall_found = true
		for _, target_group in pairs(target_groups) do
			local one_group_found = false
			for group, _ in pairs(def.groups) do
				if group == target_group then
					one_group_found = true
					break
				end
			end
			if not one_group_found then
				overall_found = false
				break
			end
		end
		if overall_found then
			crafting.guide.groups[multigroup] = item
			return item
		end
	end
	return nil
end

-- Used for alphabetizing an array of items by description
local function compare_items_by_desc(item1, item2)
	local def1 = minetest.registered_items[item1]
	local def2 = minetest.registered_items[item2]
	return def1.description < def2.description
end

local function get_output_list(craft_type)
	if crafting.guide.outputs[craft_type] then return crafting.guide.outputs[craft_type] end
	crafting.guide.outputs[craft_type] = {}
	local outputs = crafting.guide.outputs[craft_type]
	for item, _ in pairs(crafting.type[craft_type].recipes_by_out) do
		if minetest.get_item_group(item, "not_in_craft_guide") == 0 then
			table.insert(outputs, item)
		end
	end
	if crafting.config.sort_alphabetically then
		table.sort(outputs, compare_items_by_desc)
	else
		table.sort(outputs)
	end
	return outputs
end

local function get_playerdata(craft_type, player_name)
	if not crafting.guide.playerdata[craft_type] then
		crafting.guide.playerdata[craft_type] = {}
	end
	if crafting.guide.playerdata[craft_type][player_name] then
		return crafting.guide.playerdata[craft_type][player_name]
	end
	crafting.guide.playerdata[craft_type][player_name] = {["input_page"] = 0, ["output_page"] = 0, ["selection"] = 0}
	return crafting.guide.playerdata[craft_type][player_name]
end

local function make_formspec(craft_type, player_name)
	local groups = get_group_examples()
	local outputs = get_output_list(craft_type)
	local playerdata = get_playerdata(craft_type, player_name)
	
	local formspec = {
		"size[8,9.2]",
		default.gui_bg,
		default.gui_bg_img,
		default.gui_slots,
	}

	local x = 0
	local y = 0

	for i = 1, 8*4 do
		local current_item_index = i + playerdata.output_page * 8 * 4
		local current_item = outputs[current_item_index]
		if current_item then
			table.insert(formspec, "item_image_button[" ..
				x + (i-1)%8 .. "," .. y + math.floor((i-1)/8) ..
				";1,1;" .. current_item .. ";product_" .. current_item_index ..
				";]")
		else
			table.insert(formspec, "item_image_button[" ..
				x + (i-1)%8 .. "," .. y + math.floor((i-1)/8) ..
				";1,1;;;]")
		end
	end

	if playerdata.selection == 0 then
		table.insert(formspec,  "item_image[" .. x + 3.5 .. "," .. y + 4 .. ";1,1;]")
	else
		table.insert(formspec, "item_image[" .. x + 3.5 .. "," .. y + 4 .. ";1,1;" ..
			outputs[playerdata.selection] .. "]")
	end

	if #outputs > 8*4 then
		table.insert(formspec, "button[" .. x .. "," .. y + 4 .. ";1,1;previous_output;Prev]")
		table.insert(formspec, "button[" .. x + 1 .. "," .. y + 4 .. ";1,1;next_output;Next]")
		table.insert(formspec, "label[" .. x + 2 .. "," .. y + 4 .. ";Product\npage]")
	end

	local recipes
	if playerdata.selection > 0 then
		recipes = crafting.type[craft_type].recipes_by_out[outputs[playerdata.selection]]
	end

	if recipes == nil then
		return table.concat(formspec)
	end
	
	-- Note: there may be invalid recipes that won't be displayed if inputs are not defined.
	-- In that case there might be a blank page or two available for the player to view.
	-- This is a rare edge case that's a bit complicated to fix properly, and not really harmful
	-- in the meantime, so fix this later.
	if #recipes > 4 then
		table.insert(formspec, "label[" .. x + 5 .. "," .. y + 4 .. ";Recipe\npage]")
		table.insert(formspec, "button[" .. x + 6 .. "," .. y + 4 .. ";1,1;previous_input;Prev]")
		table.insert(formspec, "button[" .. x + 7 .. "," .. y + 4 .. ";1,1;next_input;Next]")
	end

	if playerdata.input_page > #recipes/4 then
		playerdata.input_page = math.floor(#recipes/4)
	end
	
	local x_out = x
	local y_out = y + 5
	for i=1,4 do
		local recipe = recipes[i + playerdata.input_page * 4]
		if not recipe then break end
		local recipe_formspec = {}
		local valid_recipe = true
		for input, count in pairs(recipe.input) do
			if string.match(input, ":") then
				table.insert(recipe_formspec, "item_image_button["..x_out..","..y_out..";1,1;"..input..";;\n\n    "..count.."]")
			elseif not string.match(input, ",") then
				if groups[input] then
					table.insert(recipe_formspec, "item_image_button["..x_out..","..y_out..";1,1;"..groups[input]..";;\n  G\n      "..count.."]")
				else
					valid_recipe = false
				end
			else
				-- it's one of those weird multi-group items, like dyes.
				local multimatch = find_multi_group(input)
				if multimatch then
					table.insert(recipe_formspec, "item_image_button["..x_out..","..y_out..";1,1;"..multimatch..";;\n  G\n      "..count.."]")
				else
					valid_recipe = false
				end
			end
			x_out = x_out + 1
		end

		x_out = 7
		for output, count in pairs(recipe.output) do
			table.insert(recipe_formspec, "item_image_button["..x_out..","..y_out..";1,1;"..output..";;\n\n    "..count.."]")
			x_out = x_out - 1
		end
		for returns, count in pairs(recipe.returns) do
			table.insert(recipe_formspec, "item_image_button["..x_out..","..y_out..";1,1;"..returns..";;\n\n    "..count.."]")
			x_out = x_out - 1
		end

		table.insert(recipe_formspec, "label["..x_out..","..y_out..";=>]")

		x_out = x
		if valid_recipe then
			y_out = y_out + 1
			for _, button in pairs(recipe_formspec) do
				table.insert(formspec, button)
			end
		end
	end
	
	return table.concat(formspec)
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if string.sub(formname, 1, 20) ~= "crafting:craftguide_" then return false end

	local craft_type = string.sub(formname, 21)

	local playerdata = get_playerdata(craft_type, player:get_player_name())
	local outputs = get_output_list(craft_type)
	
	local stay_in_formspec = false
	
	for field, _ in pairs(fields) do
		if field == "previous_output" and playerdata.output_page > 0 then
			playerdata.output_page = playerdata.output_page - 1
			stay_in_formspec = true
		elseif field == "next_output" and playerdata.output_page < #outputs/(8*4)-1 then
			playerdata.output_page = playerdata.output_page + 1
			stay_in_formspec = true
		elseif field == "previous_input" and playerdata.input_page > 0 then
			playerdata.input_page = playerdata.input_page - 1
			stay_in_formspec = true
		elseif field == "next_input" then -- we don't know how many recipes there are, let make_formspec sanitize this
			playerdata.input_page = playerdata.input_page + 1
			stay_in_formspec = true
		elseif string.sub(field, 1, 8) == "product_" then
			playerdata.selection = tonumber(string.sub(field, 9))
			stay_in_formspec = true
		elseif field == "exit" then
			return true
		end
	end
	
	if stay_in_formspec then
		minetest.show_formspec(player:get_player_name(), "crafting:craftguide_"..craft_type, make_formspec(craft_type,player:get_player_name()))
		return true
	end	
end)

crafting.show_crafting_guide = function(user, craft_type)
	minetest.show_formspec(user:get_player_name(), "crafting:craftguide_"..craft_type, make_formspec(craft_type, user:get_player_name()))
end

minetest.register_craftitem("crafting:table_guide", {
	description = S("Crafting Guide (Table)"),
	inventory_image = "crafting_guide_contents.png^(crafting_guide_cover.png^[colorize:#0088ff88)",
	wield_image = "crafting_guide_contents.png^(crafting_guide_cover.png^[colorize:#0088ff88)",
	stack_max = 1,
	groups = {book = 1},
	on_use = function(itemstack, user)
		crafting.show_crafting_guide(user, "table")
	end,
})

minetest.register_craftitem("crafting:furnace_guide", {
	description = S("Crafting Guide (Furnace)"),
	inventory_image = "crafting_guide_contents.png^(crafting_guide_cover.png^[colorize:#88000088)",
	wield_image = "crafting_guide_contents.png^(crafting_guide_cover.png^[colorize:#88000088)",
	stack_max = 1,
	groups = {book = 1},
	on_use = function(itemstack, user)
		crafting.show_crafting_guide(user, "furnace")
	end,
})

if minetest.get_modpath("default") then

	minetest.register_craft({
		output = "crafting:table_guide",
		type = "shapeless",
		recipe = {"crafting:table", "default:book"},
		replacements = {{"crafting:table", "crafting:table"}}
	})

	minetest.register_craft({
		output = "crafting:furnace_guide",
		type = "shapeless",
		recipe = {"crafting:furnace", "default:book"},
		replacements = {{"crafting:furnace", "crafting:furnace"}}
	})

end