local MP = minetest.get_modpath(minetest.get_current_modname())
local S, NS = dofile(MP.."/intllib.lua")

-- TODO: support to put a guide formspec inside a tab that's part of a larger set of formspecs

simplecrafting_lib.guide = {}
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
	simplecrafting_lib.guide.groups["soil"] = "default:dirt"
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
simplecrafting_lib.register_postprocessing_callback(initialize_group_examples) -- run once after server has loaded all other mods

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

local function get_output_list(craft_type, player_name, search_filter)
	local guide_def = get_guide_def(craft_type)
	local is_recipe_included = guide_def.is_recipe_included

	local outputs = {}
	for item, recipes in pairs(simplecrafting_lib.type[craft_type].recipes_by_out) do
		-- if the item is not excluded from the crafting guide entirely by group membership
		for _, recipe in ipairs(recipes) do
			-- and there is no is_recipe_included callback, or at least one recipe passes the is_recipe_included callback
			if ((is_recipe_included == nil) or (is_recipe_included(recipe, player_name)))
				and (search_filter == "" or string.find(item, search_filter))
			then
				-- then this output is included in this guide
				table.insert(outputs, item)
				break
			end
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
	simplecrafting_lib.guide.playerdata[craft_type][player_name] = {["input_page"] = 0, ["output_page"] = 0, ["selection"] = 0, ["search"] = ""}
	return simplecrafting_lib.guide.playerdata[craft_type][player_name]
end

simplecrafting_lib.make_guide_formspec = function(craft_type, player_name)
	local guide_def = get_guide_def(craft_type)
	local width = guide_def.output_width or default_width
	local height = guide_def.output_height or default_height
	local recipes_per_page = guide_def.recipes_per_page or default_recipes_per_page
	local is_recipe_included = guide_def.is_recipe_included

	local groups = simplecrafting_lib.guide.groups
	local playerdata = get_playerdata(craft_type, player_name)
	local outputs = get_output_list(craft_type, player_name, playerdata.search)

	local description = simplecrafting_lib.get_crafting_info(craft_type).description
	local displace_y = 0
	if description then
		displace_y = 0.5
	end
	
	local size = "size[" .. width .. "," .. height + recipes_per_page + 0.7 + displace_y .."]"

	local formspec = {
		size,
	}

	if description then
		-- title of the page
		table.insert(formspec, "label[" .. width/2-0.5 .. ",0;"..description.."]")
	end
	
	if minetest.get_modpath("default") then
		table.insert(formspec, default.gui_bg .. default.gui_bg_img .. default.gui_slots)
	end

	local buttons_per_page = width*height

	-- products that this craft guide can show recipes for
	for i = 1, buttons_per_page do
		local current_item_index = i + playerdata.output_page * buttons_per_page
		local current_item = outputs[current_item_index]
		if current_item then
			table.insert(formspec, "item_image_button[" ..
				(i-1)%width .. "," .. math.floor((i-1)/width) + displace_y ..
				";1,1;" .. current_item .. ";product_" .. current_item_index ..
				";]")
		else
			table.insert(formspec, "item_image_button[" ..
				(i-1)%width .. "," .. math.floor((i-1)/width) + displace_y ..
				";1,1;;;]")
		end
	end

	local middle_buttons_height = height + displace_y

	-- search bar
	table.insert(formspec,
		"field_close_on_enter[search_filter;false]"
		.."field[".. 0.3 ..",".. middle_buttons_height+0.25 ..";2.5,1;search_filter;;"..minetest.formspec_escape(playerdata.search).."]"
		.."image_button[".. 2.5 ..",".. middle_buttons_height ..";0.8,0.8;crafting_guide_search.png;apply_search;]"
		.."tooltip[search_filter;"..S("Enter substring to search item identifiers for").."]"
		.."tooltip[apply_search;"..S("Apply search to outputs").."]"
	)

	-- If there are more possible outputs that can be displayed at once, show next/previous buttons for the output list
	if #outputs > buttons_per_page then
		table.insert(formspec,
			"image_button[".. 3.3 ..",".. middle_buttons_height ..";0.8,0.8;simplecrafting_lib_prev.png;previous_output;]"
			.."label[" .. 3.95 .. "," .. middle_buttons_height .. ";".. playerdata.output_page + 1 .."]"
			.."image_button[".. 4.1 ..",".. middle_buttons_height ..";0.8,0.8;simplecrafting_lib_next.png;next_output;]"
			.."tooltip[next_output;"..S("Next page of outputs").."]"
			.."tooltip[previous_output;"..S("Previous page of outputs").."]"
		)
	end

	if playerdata.selection <= 0 or playerdata.selection > #outputs then
		-- No output selected
		table.insert(formspec,  "item_image[" .. 5 .. "," .. middle_buttons_height .. ";1,1;]")
		playerdata.selection = 0
	else
		-- Output selected, show an image of it
		table.insert(formspec, "item_image[" .. 5 .. "," .. middle_buttons_height .. ";1,1;" ..
			outputs[playerdata.selection] .. "]")
	end

	-- Everything below here is for displaying recipes for the selected output
	local recipes
	if playerdata.selection > 0 then
		-- Get a list of the recipes we'll want to display
		if is_recipe_included then
			recipes = {}
			for _, recipe in ipairs(simplecrafting_lib.type[craft_type].recipes_by_out[outputs[playerdata.selection]]) do
				if is_recipe_included(recipe) then
					table.insert(recipes, recipe)
				end
			end
		else
			recipes = simplecrafting_lib.type[craft_type].recipes_by_out[outputs[playerdata.selection]]
		end
	end

	if recipes == nil then
		-- No recipes to display.
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
	
		table.insert(formspec,
			"image_button[".. width-1.6 ..",".. middle_buttons_height ..";0.8,0.8;simplecrafting_lib_prev.png;previous_input;]"
			.."label[" .. width-0.95 .. "," .. middle_buttons_height .. ";".. playerdata.input_page + 1 .."]"
			.."image_button[".. width-0.8 ..",".. middle_buttons_height ..";0.8,0.8;simplecrafting_lib_next.png;next_input;]"
			.."tooltip[next_input;"..S("Next page of recipes for this output").."]"
			.."tooltip[previous_input;"..S("Previous page of recipes for this output").."]"
		)
	end
	
	local x_out = 0
	local y_out = middle_buttons_height + 1
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
				table.insert(recipe_formspec, "item_image_button["..x_out..","..y_out..";1,1;"..input..";recipe_button_"..recipe_button_count..";\n\n      "..count.."]"
						.."tooltip[recipe_button_"..recipe_button_count..";"..count.." "..itemdesc.."]")
			elseif not string.match(input, ",") then
				local itemdesc = "Group: "..input
				table.insert(recipe_formspec, "item_image_button["..x_out..","..y_out..";1,1;"..groups[input]..";recipe_button_"..recipe_button_count..";\n  G\n        "..count.."]"
					.."tooltip[recipe_button_"..recipe_button_count..";"..count.." "..itemdesc.."]")
			else
				-- it's one of those weird multi-group items, like dyes.
				local multimatch = find_multi_group(input)
				local itemdesc = "Groups: "..input
				table.insert(recipe_formspec, "item_image_button["..x_out..","..y_out..";1,1;"..multimatch..";recipe_button_"..recipe_button_count..";\n  G\n        "..count.."]"
					.."tooltip[recipe_button_"..recipe_button_count..";"..count.." "..itemdesc.."]")
			end
			recipe_button_count = recipe_button_count + 1
			x_out = x_out + 1
		end

		-------------------------------- Outputs
		x_out = width - 1

		local output_name = recipe.output:get_name()
		local output_count = recipe.output:get_count()
		local itemdesc = minetest.registered_items[output_name].description -- we know this item exists otherwise a recipe wouldn't have been found
		table.insert(recipe_formspec, "item_image_button["..x_out..","..y_out..";1,1;"..output_name..";recipe_button_"..recipe_button_count..";\n\n      "..output_count.."]"
			.."tooltip[recipe_button_"..recipe_button_count..";"..output_count.." "..itemdesc.."]")
		recipe_button_count = recipe_button_count + 1
		x_out = x_out - 1

		if recipe.returns then
			for returns, count in pairs(recipe.returns) do
				local itemdef = minetest.registered_items[returns]
				local itemdesc = returns
				if itemdef then
					itemdesc = itemdef.description
				end	
				table.insert(recipe_formspec, "item_image_button["..x_out..","..y_out..";1,1;"..returns..";recipe_button_"..recipe_button_count..";\n\n      "..count.."]"
					.."tooltip[recipe_button_"..recipe_button_count..";"..count.." "..itemdesc.."]")
				recipe_button_count = recipe_button_count + 1
				x_out = x_out - 1
			end
		end

		if minetest.get_modpath("default") then
			table.insert(recipe_formspec, "image["..x_out..","..y_out..";1,1;gui_furnace_arrow_bg.png^[transformR270]")
		else
			table.insert(recipe_formspec, "label["..x_out..","..y_out..";=>]")
		end

		x_out = 0
		y_out = y_out + 1
		for _, button in pairs(recipe_formspec) do
			table.insert(formspec, button)
		end
	end
	
	if guide_def.append_to_formspec then
		table.insert(formspec, guide_def.append_to_formspec)
	end
	return table.concat(formspec), size
end

simplecrafting_lib.handle_guide_receive_fields = function(craft_type, player, fields)
	local guide_def = get_guide_def(craft_type)
	local width = guide_def.output_width or default_width
	local height = guide_def.output_height or default_height
	local player_name = player:get_player_name()
	local playerdata = get_playerdata(craft_type, player_name)
	local outputs = get_output_list(craft_type, player_name, playerdata.search)
	
	local stay_in_formspec = false

	for field, value in pairs(fields) do
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
			
		elseif field == "search_filter" then
			value = string.lower(value)
			if playerdata.search ~= value then
				playerdata.search = value
				playerdata.output_page = 0
				playerdata.input_page = 0
				playerdata.selection = 0
			end
					
		elseif field == "apply_search" or fields.key_enter_field == "search_filter"then
			stay_in_formspec = true
			
		elseif field == "quit" then
			if playerdata.on_exit then
				playerdata.on_exit()
			end
			return false
		end
	end
	
	return stay_in_formspec
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if string.sub(formname, 1, 30) ~= "simplecrafting_lib:craftguide_" then return false end

	local craft_type = string.sub(formname, 31)
	
	if simplecrafting_lib.handle_guide_receive_fields(craft_type, player, fields) then
		minetest.show_formspec(player:get_player_name(),
			"simplecrafting_lib:craftguide_"..craft_type,
			simplecrafting_lib.make_guide_formspec(craft_type,player:get_player_name())
		)
	end
	return true
end)

simplecrafting_lib.show_crafting_guide = function(craft_type, user, on_exit)
	if simplecrafting_lib.type[craft_type] then
		get_playerdata(craft_type, user:get_player_name()).on_exit = on_exit
		minetest.show_formspec(user:get_player_name(),
			"simplecrafting_lib:craftguide_"..craft_type,
			simplecrafting_lib.make_guide_formspec(craft_type, user:get_player_name())
		)
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
--		is_recipe_included = function(recipe, player_name) -- return true to include this recipe in the guide, if not defined then all recipes are included
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
--		wield_scale = scale of wield_image, defaults to nil (same as standard craftitem def)
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