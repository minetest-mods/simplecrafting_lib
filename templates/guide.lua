local MP = minetest.get_modpath(minetest.get_current_modname())
local S, NS = dofile(MP.."/intllib.lua")

simplecrafting_lib.guide = {}
simplecrafting_lib.guide.outputs = {}
simplecrafting_lib.guide.playerdata = {}
simplecrafting_lib.guide.groups = {}
simplecrafting_lib.guide.guide_def = {}

local default_width = 10
local default_height = 6
local default_recipes_per_page = 4

local function get_guide_def(craft_type)
	return simplecrafting_lib.guide.guide_def[craft_type] or {}
end

-- Explicitly set examples for some common input item groups
-- Other mods can also add explicit items like this if they wish
-- Groups list isn't populated with "guessed" examples until
-- after initialization, when all other mods are already loaded
if minetest.get_modpath("default") then
	simplecrafting_lib.guide.groups["wood"] = "default:wood"
	simplecrafting_lib.guide.groups["stick"] = "default:stick"
	simplecrafting_lib.guide.groups["tree"] = "default:tree"
	simplecrafting_lib.guide.groups["stone"] = "default:stone"
	simplecrafting_lib.guide.groups["sand"] = "default:sand"
end
if minetest.get_modpath("wool") then
	simplecrafting_lib.guide.groups["wool"] = "wool:white"
end

-- internationalization boilerplate
local MP = minetest.get_modpath(minetest.get_current_modname())
local S, NS = dofile(MP.."/intllib.lua")

local function initialize_group_examples()
	-- finds an example item for every group that does not already have one defined
	for item, def in pairs(minetest.registered_items) do
		for group, _ in pairs(def.groups) do
			if not simplecrafting_lib.guide.groups[group] then
				simplecrafting_lib.guide.groups[group] = item
			end
		end
	end
end
minetest.after(0, initialize_group_examples) -- run once after server has loaded all other mods

-- splits a string into an array of substrings based on a delimiter
local function split(str, delimiter)
    local result = {}
    for match in (str..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match)
    end
    return result
end

local function find_multi_group(multigroup)
	if simplecrafting_lib.guide.groups[multigroup] then
		return simplecrafting_lib.guide.groups[multigroup]
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
			simplecrafting_lib.guide.groups[multigroup] = item
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
	if simplecrafting_lib.guide.outputs[craft_type] then return simplecrafting_lib.guide.outputs[craft_type] end
	simplecrafting_lib.guide.outputs[craft_type] = {}
	local outputs = simplecrafting_lib.guide.outputs[craft_type]
	for item, _ in pairs(simplecrafting_lib.type[craft_type].recipes_by_out) do
		if minetest.get_item_group(item, "not_in_craft_guide") == 0 then
			table.insert(outputs, item)
		end
	end
	-- TODO: sorting option
	table.sort(outputs)
	return outputs
end

local function get_playerdata(craft_type, player_name)
	if not simplecrafting_lib.guide.playerdata[craft_type] then
		simplecrafting_lib.guide.playerdata[craft_type] = {}
	end
	if simplecrafting_lib.guide.playerdata[craft_type][player_name] then
		return simplecrafting_lib.guide.playerdata[craft_type][player_name]
	end
	simplecrafting_lib.guide.playerdata[craft_type][player_name] = {["input_page"] = 0, ["output_page"] = 0, ["selection"] = 0}
	return simplecrafting_lib.guide.playerdata[craft_type][player_name]
end

local function make_formspec(craft_type, player_name)
	local guide_def = get_guide_def(craft_type)
	local width = guide_def.output_width or default_width
	local height = guide_def.output_height or default_height
	local recipes_per_page = guide_def.recipes_per_page or default_recipes_per_page

	local groups = simplecrafting_lib.guide.groups
	local outputs = get_output_list(craft_type)
	local playerdata = get_playerdata(craft_type, player_name)

	local description = simplecrafting_lib.get_crafting_info(craft_type).description
	local displace_y = 0
	if description then
		displace_y = 0.5
	end
	
	local formspec = {
		"size[" .. width .. "," .. height + recipes_per_page + 0.7 + displace_y .."]",
	}

	if description then
		table.insert(formspec, "label[" .. width/2-0.5 .. ",0;"..description.."]")
	end
	
	if minetest.get_modpath("default") then
		table.insert(formspec, default.gui_bg)
		table.insert(formspec, default.gui_bg_img)
		table.insert(formspec, default.gui_slots)
	end

	local x = 0
	local y = 0
	
	local buttons_per_page = width*height

	for i = 1, buttons_per_page do
		local current_item_index = i + playerdata.output_page * buttons_per_page
		local current_item = outputs[current_item_index]
		if current_item then
			table.insert(formspec, "item_image_button[" ..
				x + (i-1)%width .. "," .. y + math.floor((i-1)/width) + displace_y ..
				";1,1;" .. current_item .. ";product_" .. current_item_index ..
				";]")
		else
			table.insert(formspec, "item_image_button[" ..
				x + (i-1)%width .. "," .. y + math.floor((i-1)/width) + displace_y ..
				";1,1;;;]")
		end
	end

	if playerdata.selection == 0 then
		table.insert(formspec,  "item_image[" .. x + width/2-0.5 .. "," .. y + height + displace_y .. ";1,1;]")
	else
		table.insert(formspec, "item_image[" .. x + width/2-0.5 .. "," .. y + height + displace_y .. ";1,1;" ..
			outputs[playerdata.selection] .. "]")
	end

	if #outputs > buttons_per_page then
		table.insert(formspec, "button[" .. x .. "," .. y + height + displace_y .. ";1,1;previous_output;"..S("Prev").."]")
		table.insert(formspec, "button[" .. x + 1 .. "," .. y + height + displace_y .. ";1,1;next_output;"..S("Next").."]")
		table.insert(formspec, "label[" .. x + 2 .. "," .. y + height + displace_y .. ";".. S("Product\npage @1", playerdata.output_page + 1) .."]")
	end

	local recipes
	if playerdata.selection > 0 then
		recipes = simplecrafting_lib.type[craft_type].recipes_by_out[outputs[playerdata.selection]]
	end

	if recipes == nil then
		return table.concat(formspec)
	end

	local last_page = math.floor((#recipes-1)/recipes_per_page)
	local next_input = "next_input"
	if playerdata.input_page >= last_page then
		playerdata.input_page = last_page
	end
	if playerdata.input_page == last_page then
		next_input = "" -- disable the next_input button, we're on the last page.
	end
	
	if #recipes > recipes_per_page then
		table.insert(formspec, "label[" .. x + width - 3 .. "," .. y + height + displace_y .. ";".. S("Recipe\npage @1", playerdata.input_page + 1) .."]")
		table.insert(formspec, "button[" .. x + width - 2 .. "," .. y + height + displace_y .. ";1,1;previous_input;"..S("Prev").."]")
		table.insert(formspec, "button[" .. x + width - 1 .. "," .. y + height + displace_y .. ";1,1;"..next_input..";"..S("Next").."]")
	end
	
	local x_out = x
	local y_out = y + height + 1 + displace_y
	local recipe_button_count = 1
	for i = 1, recipes_per_page do
		local recipe = recipes[i + playerdata.input_page * recipes_per_page]
		if not recipe then break end
		local recipe_formspec = {}
		
		-------------------------------- Inputs
		
		for input, count in pairs(recipe.input) do
			if string.match(input, ":") then
				local itemdef = minetest.registered_items[input]
				local itemdesc = input
				if itemdef then
					itemdesc = itemdef.description
				end				
				table.insert(recipe_formspec, "item_image_button["..x_out..","..y_out..";1,1;"..input..";recipe_button_"..recipe_button_count..";\n\n    "..count.."]")
				table.insert(recipe_formspec, "tooltip[recipe_button_"..recipe_button_count..";"..count.." "..itemdesc.."]")
			elseif not string.match(input, ",") then
				local itemdesc = "Group: "..input
				table.insert(recipe_formspec, "item_image_button["..x_out..","..y_out..";1,1;"..groups[input]..";recipe_button_"..recipe_button_count..";\n  G\n      "..count.."]")
				table.insert(recipe_formspec, "tooltip[recipe_button_"..recipe_button_count..";"..count.." "..itemdesc.."]")
			else
				-- it's one of those weird multi-group items, like dyes.
				local multimatch = find_multi_group(input)
				local itemdesc = "Groups: "..input
				table.insert(recipe_formspec, "item_image_button["..x_out..","..y_out..";1,1;"..multimatch..";recipe_button_"..recipe_button_count..";\n  G\n      "..count.."]")
				table.insert(recipe_formspec, "tooltip[recipe_button_"..recipe_button_count..";"..count.." "..itemdesc.."]")
			end
			recipe_button_count = recipe_button_count + 1
			x_out = x_out + 1
		end

		-------------------------------- Outputs
		x_out = width - 1

		local output_name = recipe.output:get_name()
		local output_count = recipe.output:get_count()
		local itemdesc = minetest.registered_items[output_name].description -- we know this item exists otherwise a recipe wouldn't have been found
		table.insert(recipe_formspec, "item_image_button["..x_out..","..y_out..";1,1;"..output_name..";recipe_button_"..recipe_button_count..";\n\n    "..output_count.."]")
		table.insert(recipe_formspec, "tooltip[recipe_button_"..recipe_button_count..";"..output_count.." "..itemdesc.."]")
		recipe_button_count = recipe_button_count + 1
		x_out = x_out - 1

		if recipe.returns then
			for returns, count in pairs(recipe.returns) do
				local itemdef = minetest.registered_items[returns]
				local itemdesc = returns
				if itemdef then
					itemdesc = itemdef.description
				end	
				table.insert(recipe_formspec, "item_image_button["..x_out..","..y_out..";1,1;"..returns..";recipe_button_"..recipe_button_count..";\n\n    "..count.."]")
				table.insert(recipe_formspec, "tooltip[recipe_button_"..recipe_button_count..";"..count.." "..itemdesc.."]")
				recipe_button_count = recipe_button_count + 1
				x_out = x_out - 1
			end
		end

		if minetest.get_modpath("default") then
			table.insert(recipe_formspec, "image["..x_out..","..y_out..";1,1;gui_furnace_arrow_bg.png^[transformR270]")
		else
			table.insert(recipe_formspec, "label["..x_out..","..y_out..";=>]")
		end

		x_out = x
		y_out = y_out + 1
		for _, button in pairs(recipe_formspec) do
			table.insert(formspec, button)
		end
	end
	
	if guide_def.append_to_formspec then
		table.insert(formspec, guide_def.append_to_formspec)
	end
	
	return table.concat(formspec)
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if string.sub(formname, 1, 30) ~= "simplecrafting_lib:craftguide_" then return false end

	local craft_type = string.sub(formname, 31)

	local guide_def = get_guide_def(craft_type)
	local width = guide_def.output_width or default_width
	local height = guide_def.output_height or default_height
	
	local playerdata = get_playerdata(craft_type, player:get_player_name())
	local outputs = get_output_list(craft_type)
	
	local stay_in_formspec = false
	
	for field, _ in pairs(fields) do
		if field == "previous_output" and playerdata.output_page > 0 then
			playerdata.output_page = playerdata.output_page - 1
			minetest.sound_play("paperflip2", {to_player=player:get_player_name(), gain = 1.0})
			stay_in_formspec = true
		elseif field == "next_output" and playerdata.output_page < #outputs/(width*height)-1 then
			playerdata.output_page = playerdata.output_page + 1
			minetest.sound_play("paperflip1", {to_player=player:get_player_name(), gain = 1.0})
			stay_in_formspec = true
		elseif field == "previous_input" and playerdata.input_page > 0 then
			playerdata.input_page = playerdata.input_page - 1
			minetest.sound_play("paperflip2", {to_player=player:get_player_name(), gain = 1.0})
			stay_in_formspec = true
		elseif field == "next_input" then -- we don't know how many recipes there are, let make_formspec sanitize this
			playerdata.input_page = playerdata.input_page + 1
			minetest.sound_play("paperflip1", {to_player=player:get_player_name(), gain = 1.0})
			stay_in_formspec = true
		elseif string.sub(field, 1, 8) == "product_" then
			playerdata.input_page = 0
			playerdata.selection = tonumber(string.sub(field, 9))
			minetest.sound_play("paperflip1", {to_player=player:get_player_name(), gain = 1.0})
			stay_in_formspec = true
		elseif field == "exit" then
			return true
		end
	end
	
	if stay_in_formspec then
		minetest.show_formspec(player:get_player_name(), "simplecrafting_lib:craftguide_"..craft_type, make_formspec(craft_type,player:get_player_name()))
		return true
	end	
end)

simplecrafting_lib.show_crafting_guide = function(craft_type, user)
	if simplecrafting_lib.type[craft_type] then
		minetest.show_formspec(user:get_player_name(), "simplecrafting_lib:craftguide_"..craft_type, make_formspec(craft_type, user:get_player_name()))
	else
		minetest.chat_send_player(user:get_player_name(), "Unable to show crafting guide for " .. craft_type .. ", it has no recipes registered.")
	end
end

--	defines some parameters regarding how the formspec of the guide for a given craft_type is displayed.
--	guide_def 
--	{
--		output_width = 10
--		output_height = 6
--		recipes_per_page = 4
--		append_to_formspec = string
--	}

simplecrafting_lib.set_crafting_guide_def = function(craft_type, guide_def)
	simplecrafting_lib.guide.guide_def[craft_type] = guide_def
end

--	creates a basic crafting guide item
--	guide_item_def has many options.
--	{
--		description = string description the item will get. Defaults to "<description of craft type> Recipes"
--		inventory_image = inventory image to be used with this item. Defaults to the book texture included with simplecrafting_lib
--		guide_color = ColorString. If defined, the inventory image will be tinted with this color.
--		wield_image = image to be used when wielding this item. Defaults to inventory image.
--		groups = groups this item will belong to. Defaults to {book = 1}
--		stack_max = maximum stack size. Defaults to 1.
--		wield_scale = scale of weild_image, defaults to nil (same as standard craftitem def)
--		copy_item_to_book = an item name string (eg, "workshops:smelter"). If the default mod is installed, a recipe will be generated that combines a default:book with copy_item_to_book and returns this guide and copy_item_to_book. In this manner the player can only get a handy portable reference guide if they are already in possession of the thing that the guide is used with. If copy_item_to_book is not defined then no crafting recipe is generated for this guide.
--	}

simplecrafting_lib.register_crafting_guide_item = function(item_name, craft_type, guide_item_def)

	local description
	if guide_item_def.description then
		description = guide_item_def.description
	elseif simplecrafting_lib.get_crafting_info(craft_type).description then
		description = S("@1 Recipes", simplecrafting_lib.get_crafting_info(craft_type).description)
	else
		description = S("@1 Recipes", craft_type)
	end
	
	local inventory_image
	if guide_item_def.inventory_image then
		inventory_image = guide_item_def.inventory_image
		if guide_item_def.guide_color then
			inventory_image = inventory_image .. "^[multiply:" .. guide_item_def.guide_color
		end
	elseif guide_item_def.guide_color then
		inventory_image = "crafting_guide_cover.png^[multiply:" .. guide_item_def.guide_color .. "^crafting_guide_contents.png"
	else
		inventory_image = "crafting_guide_cover.png^crafting_guide_contents.png"
	end

	minetest.register_craftitem(item_name, {
		description = description,
		inventory_image = inventory_image,
		wield_image = guide_item_def.wield_image or inventory_image,
		wield_scale = guide_item_def.wield_scale,
		stack_max = guide_item_def.stack_max or 1,
		groups = guide_item_def.groups or {book = 1},
		on_use = function(itemstack, user)
			simplecrafting_lib.show_crafting_guide(craft_type, user)
		end,
	})
	
	if guide_item_def.copy_item_to_book and minetest.get_modpath("default") then
		minetest.register_craft({
			output = item_name,
			type = "shapeless",
			recipe = {guide_item_def.copy_item_to_book, "default:book"},
			replacements = {{guide_item_def.copy_item_to_book, guide_item_def.copy_item_to_book}}
		})
	end

end