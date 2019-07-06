local modpath = minetest.get_modpath(minetest.get_current_modname())

local OptionParser = dofile(modpath .. "/saveload/optparse.lua")
local orderedPairs = dofile(modpath .. "/saveload/orderedpairs.lua")
local parse_graphml_recipes = dofile(modpath .. "/saveload/readrecipegraph.lua")
local write_graphml_recipes = dofile(modpath .. "/saveload/writerecipegraph.lua")


-- Given a list of mods, returns a filter with indices for all registered items
-- that belong to one of those mods and all group names that belong to at least
-- one item in one of those mods.
-- TODO: this doesn't handle multigroup recipe items, such as "flower,yellow"
-- Might be better to reuse methods from postprocessing.lua, they're more expensive but
-- they handle this.
local create_mod_filter = function(mod_list)

	local filter_obj = {}
	if next(mod_list) == nil then
		filter_obj.filter = function() return true end -- if there's nothing in the mod list, make a filter that always returns true
		return filter_obj
	end
	
	local mods = {}
	for _, mod in pairs(mod_list) do
		mods[mod] = true
	end	
	local all_members = {}
	for itemname, itemdef in pairs(minetest.registered_items) do
		local colon_index = string.find(itemname, ":")
		if colon_index then
			local mod = string.sub(itemname, 1, colon_index-1)
			if mods[mod] then
				all_members[itemname] = true
				if itemdef.groups then
					for group, _ in pairs(itemdef.groups) do
						all_members[group] = true
					end
				end
			end
		end			
	end
	filter_obj.filter = function(recipe)
		if recipe.input then
			for item, _ in pairs(recipe.input) do
				if all_members[item] then return true end
			end
		end
		if recipe.output then
			if all_members[recipe.output:get_name()] then return true end
		end
		if recipe.returns then
			for item, _ in pairs(recipe.returns) do
				if all_members[item] then return true end
			end		
		end
	end
	return filter_obj
end

-- Writing recipe dump to a .lua file
---------------------------------------------------------------------------------

-- Writes a single recipe to a table in the output file
local write_recipe = function(file, recipe)
	file:write("\t{\n")
	for key, val in orderedPairs(recipe) do
		if type(val) == "function" then
			minetest.log("error", "[simplecrafting_lib] recipe write: " .. key .. "'s value is a function")
		else
			file:write("\t\t"..key.." = ")
			if key == "output" then
				file:write("\t\"" .. ItemStack(val):to_string() .."\",\n")
			elseif type(val) == "table" then
				file:write("\t{")
				for kk, vv in orderedPairs(val) do
					if type(vv) == "string" then
						file:write("[\"" .. kk .. "\"] = \"" .. tostring(vv) .. "\", ")
					else
						file:write("[\"" .. kk .. "\"] = " .. tostring(vv) .. ", ")
					end
				end
				file:write("},\n")
			elseif type(val) == "string" then
				file:write("\t\"" .. tostring(val) .. "\",\n")
			else
				file:write("\t" .. tostring(val) .. ",\n")
			end	
		end		
	end
	file:write("\t},\n")
end

local write_craft_list = function(file, craft_type, recipe_list_by_out, recipe_filter)
	file:write("-- Craft Type " .. craft_type .. "--------------------------------------------------------\n[\"" .. craft_type .. "\"] = {\n")
	for out, recipe_list in orderedPairs(recipe_list_by_out) do
		file:write("-- Output: " .. out .. "\n")
		for _, recipe in ipairs(recipe_list) do
			if recipe_filter.filter(recipe) then
				write_recipe(file, recipe)
			end
		end
	end
	file:write("},\n")
end

-- Dumps recipes from the existing crafting system into a file that can be used to recreate them.
local save_recipes = function(param, craft_types, recipe_filter)
	local path = minetest.get_worldpath()
	local filename = path .. "/" .. param .. ".lua"
	local file, err = io.open(filename, "w")
	if err ~= nil then
		minetest.log("error", "[simplecrafting_lib] Could not save recipes to \"" .. filename .. "\"")
		return false
	end
	
	file:write("return {\n")
	
	if table.getn(craft_types) == 0 then
		for craft_type, recipe_list in orderedPairs(simplecrafting_lib.type) do
			write_craft_list(file, craft_type, recipe_list.recipes_by_out, recipe_filter)
		end
	else
		for _, craft_type in ipairs(craft_types) do
			if simplecrafting_lib.type[craft_type] then
				write_craft_list(file, craft_type, simplecrafting_lib.type[craft_type].recipes_by_out, recipe_filter)
--			else
--				TODO: error message
			end
		end
	end
	
	file:write("}\n")

	file:flush()
	file:close()
	return true
end

-------------------------------------------------------------------------------------------

local save_recipes_graphml = function(name, craft_types, recipe_filter, show_unused)
	local path = minetest.get_worldpath()
	local filename = path .. "/" .. name .. ".graphml"
	local file, err = io.open(filename, "w")
	if err ~= nil then
		minetest.log("error", "[simplecrafting_lib] Could not save recipes to \"" .. filename .. "\"")
		return false
	end

	if not craft_types or table.getn(craft_types) == 0 then
		write_graphml_recipes(file, simplecrafting_lib.type, recipe_filter, show_unused)
	else
		local recipes = {}
		for _, craft_type in ipairs(craft_types) do
			recipes[craft_type] = simplecrafting_lib.type[craft_type]
		end
		write_graphml_recipes(file, recipes, recipe_filter, show_unused)	
	end

	return true
end

local read_recipes_graphml = function(name)
	local path = minetest.get_worldpath()
	local filename = path .. "/" .. name .. ".graphml"

	local file, err = io.open(filename, "r")
	if err ~= nil then
		minetest.log("error", "[simplecrafting_lib] Could not read recipes from \"" .. filename .. "\"")
		return false
	end
	local myxml = file:read('*all')
	local parse_error
	myxml, parse_error = parse_graphml_recipes(myxml)
	if parse_error then
		minetest.log("error", "Failed to parse graphml " .. filename .. " with error: " .. parse_error)
		return false
	end		
		
	return myxml
end

-------------------------------------------------------------

-- registers all recipes in the provided filename, which is usually a file generated by save_recipes and then perhaps modified by the developer.
local load_recipes = function(param, craft_set, recipe_filter)
	local path = minetest.get_worldpath()
	local filename = path .. "/" .. param .. ".lua"
	local new_recipes = loadfile(filename)
	if new_recipes == nil then
		minetest.log("error", "[simplecrafting_lib] Could not read recipes from \"" .. filename .. "\"")
		return false
	end
	new_recipes = new_recipes()	
	
	for crafting_type, recipes in pairs(new_recipes) do
		if craft_set == nil or craft_set[crafting_type] then
			for _, recipe in pairs(recipes) do
				if recipe_filter.filter(recipe) then
					simplecrafting_lib.register(crafting_type, recipe)
				end
			end
		end
	end	
	return true
end

-- What the function name says it does
local get_recipes_that_are_in_first_recipe_list_but_not_in_second_recipe_list = function(first_recipe_list, second_recipe_list)
	if first_recipe_list == nil then
		return nil
	elseif second_recipe_list == nil then
		return first_recipe_list
	end
	
	local returns

	for _, first_recipe in pairs(first_recipe_list) do
		local found = false
		for _, second_recipe in pairs(second_recipe_list) do
			if simplecrafting_lib.recipe_equals(first_recipe, second_recipe) then
				found = true
				break
			end
		end
		if found ~= true then
			returns = returns or {}
			table.insert(returns, first_recipe)
		end
	end
	
	return returns
end

-- Used in diff_recipes for writing lists of recipes
local write_recipe_lists = function(file, recipe_lists)
	for craft_type, recipe_list in orderedPairs(recipe_lists) do	
		file:write("-- Craft Type " .. craft_type .. "--------------------------------------------------------\n[\"" .. craft_type .. "\"] = {\n")
		for _, recipe in ipairs(recipe_list) do
			write_recipe(file, recipe)
		end
		file:write("},\n")
	end
end

-- compares the recipes in the infile (of the form written by save_recipes) to the recipes in the existing crafting system, and outputs differences to outfile
local diff_recipes = function(infile, outfile)
	local path = minetest.get_worldpath()
	local filename = path .. "/" .. infile .. ".lua"
	local new_recipes = loadfile(filename)
	if new_recipes == nil then
		minetest.log("error", "[simplecrafting_lib] Could not read recipes from \"" .. filename .. "\"")
		return false
	end
	new_recipes = new_recipes()
	
	local new_only_recipes = {}
	local existing_only_recipes = {}
	
	for craft_type, recipe_lists in pairs(simplecrafting_lib.type) do
		if new_recipes[craft_type] ~= nil then
			new_only_recipes[craft_type] = get_recipes_that_are_in_first_recipe_list_but_not_in_second_recipe_list(new_recipes[craft_type], recipe_lists.recipes)
		else
			existing_only_recipes[craft_type] = recipe_lists.recipes
		end
	end
	for craft_type, recipe_lists in pairs(new_recipes) do
		local existing_recipes = simplecrafting_lib.type[craft_type]
		if existing_recipes ~= nil then
			existing_only_recipes[craft_type] = get_recipes_that_are_in_first_recipe_list_but_not_in_second_recipe_list(existing_recipes.recipes, recipe_lists)
		else
			new_only_recipes[craft_type] = recipe_lists
		end
	end
	
	filename = path .. "/" .. outfile .. ".txt"
	local file, err = io.open(filename, "w")
	if err ~= nil then
		minetest.log("error", "[simplecrafting_lib] Could not save recipe diffs to \"" .. filename .. "\"")
		return false
	end
		
	file:write("-- Recipes found only in the external file:\n--------------------------------------------------------\n")
	write_recipe_lists(file, new_only_recipes)
	file:write("\n")

	file:write("-- Recipes found only in the existing crafting database:\n--------------------------------------------------------\n")
	write_recipe_lists(file, existing_only_recipes)
	file:write("\n")
	
	file:flush()
	file:close()
	
	return true
end

---------------------------------------------------------------

function split(inputstr, seperator)
	if inputstr == nil then return {} end
	if seperator == nil then
		seperator = "%s"
	end
	local out={}
	local i=1
	for substring in string.gmatch(inputstr, "([^"..seperator.."]+)") do
		out[i] = substring
		i = i + 1
	end
	return out
end

local saveoptparse = OptionParser{usage="[options] file"}
saveoptparse.add_option{"-h", "--help", action="store_true", dest="help", help = "displays help text"}
saveoptparse.add_option{"-l", "--lua", action="store_true", dest="lua", help="saves recipes as \"(world folder)/<file>.lua\""}
saveoptparse.add_option{"-g", "--graphml", action="store_true", dest="graphml", help="saves recipes as \"(world folder)/<file>.graphml\""}
saveoptparse.add_option{"-t", "--type", action="store", dest="types", help="craft_type to save. Leave unset to save all. Use a comma-delimited list (eg, \"table,furnace\") to save multiple specific craft types."}
saveoptparse.add_option{"-m", "--mod", action="store", dest="mods", help="only recipes with these mods in them will be saved. Leave unset to save all. Use a comma-delimited list with no spaces (eg, \"default,stairs\") to save multiple specific mod types."}
saveoptparse.add_option{"-u", "--unused", action="store_true", dest="unused", help="Include all registered unused items in graphml output (no effect with lua output)."}

minetest.register_chatcommand("recipesave", {
	params = saveoptparse.print_help(),
	description = "Saves recipes to external files",
	func = function(name, param)
		if not minetest.check_player_privs(name, {server = true}) then
			minetest.chat_send_player(name, "You need the \"server\" priviledge to use this command.", false)
			return
		end
	
		local success, options, args = saveoptparse.parse_args(param)
		if not success then
			minetest.chat_send_player(name, options)
			return
		end
		
		if options.help then
			minetest.chat_send_player(name, saveoptparse.print_help())
			return
		end
		
		if table.getn(args) ~= 1 then
			minetest.chat_send_player(name, "A filename argument is needed.")
			return
		end

		if not (options.lua or options.graphml) then
			minetest.chat_send_player(name, "Neither lua nor graphml output was selected, defaulting to lua.")
			options.lua = true
		end
		
		if options.unused and not options.graphml then
			minetest.chat_send_player(name, "Unused items are only included in graphml output, which was not selected.")
		end
		
		local craft_types = split(options.types, ",")
		local recipe_filter = create_mod_filter(split(options.mods, ","))
		
		if options.lua then
			if save_recipes(args[1], craft_types, recipe_filter) then
				minetest.chat_send_player(name, "Lua recipes saved", false)
			else
				minetest.chat_send_player(name, "Failed to save lua recipes", false)
			end
		end
		
		if options.graphml then
			if save_recipes_graphml(args[1], craft_types, recipe_filter, options.unused) then
				minetest.chat_send_player(name, "Graphml recipes saved", false)
			else
				minetest.chat_send_player(name, "Failed to save graphml recipes", false)
			end
		end
	end,
})

-- TODO: combine the load commands too. Include an option to clear craft types being loaded.

local loadoptparse = OptionParser{usage="[options] file"}
loadoptparse.add_option{"-h", "--help", action="store_true", dest="help", help = "displays help text"}
loadoptparse.add_option{"-l", "--lua", action="store_true", dest="lua", help="loads recipes from \"(world folder)/<file>.lua\""}
loadoptparse.add_option{"-g", "--graphml", action="store_true", dest="graphml", help="loads recipes from \"(world folder)/<file>.graphml\""}
loadoptparse.add_option{"-t", "--type", action="store", dest="types", help="craft_type to load. Leave unset to load all. Use a comma-delimited list (eg, \"table,furnace\") to load multiple specific craft types."}
loadoptparse.add_option{"-m", "--mod", action="store", dest="mods", help="only recipes with these mods in them will be loaded. Leave unset to load all. Use a comma-delimited list with no spaces (eg, \"default,stairs\") to load multiple specific mod types."}
--loadoptparse.add_option{"-c", "--clear", action="store_true", dest="clear", help="Clears existing recipes of the craft_types being loaded before loading."}

minetest.register_chatcommand("recipeload", {
	params = loadoptparse.print_help(),
	description = "Loads recipes from external files",
	func = function(name, param)
		if not minetest.check_player_privs(name, {server = true}) then
			minetest.chat_send_player(name, "You need the \"server\" priviledge to use this command.", false)
			return
		end
	
		local success, options, args = loadoptparse.parse_args(param)
		if not success then
			minetest.chat_send_player(name, options)
			return
		end
		
		if options.help then
			minetest.chat_send_player(name, loadoptparse.print_help())
			return
		end
		
		if table.getn(args) ~= 1 then
			minetest.chat_send_player(name, "A single filename argument is needed.")
			return
		end

		if not (options.lua or options.graphml) or (options.lua and options.graphml) then
			minetest.chat_send_player(name, "One of lua or graphml output formats should be selected. Defaulting to lua.")
			options.lua = true
			options.graphml = false
		end
				
		local craft_types = split(options.types, ",")
		local craft_set
		if table.getn(craft_types) > 0 then
			craft_set = {}
			for _, craft_type in pairs(craft_types) do
				craft_set[craft_type] = true
			end
		end
		local recipe_filter = create_mod_filter(split(options.mods, ","))

		if options.graphml then
			local read_recipes = read_recipes_graphml(args[1])
			if read_recipes then
				for _, recipe in pairs(read_recipes) do
					local craft_type = recipe.craft_type
					if (craft_set == nil or craft_set[craft_type]) and recipe_filter.filter(recipe) then
						recipe.craft_type = nil
						simplecrafting_lib.register(craft_type, recipe)
					end
				end
				minetest.chat_send_player(name, "Recipes read from graphml", false)
			else
				minetest.chat_send_player(name, "Failed to read recipes from graphml", false)
			end
		else
			if load_recipes(args[1], craft_set, recipe_filter) then
				minetest.chat_send_player(name, "Recipes loaded from lua", false)
			else
				minetest.chat_send_player(name, "Failed to load recipes from lua", false)
			end
		end
	end,
})

local clearoptparse = OptionParser{usage="[options]"}
clearoptparse.add_option{"-h", "--help", action="store_true", dest="help", help = "displays help text"}
clearoptparse.add_option{"-t", "--type", action="store", dest="types", help = "Clear only these recipe types. Leave unset to clear all. Use a comma-delimited list with no spaces (eg, \"table,furnace\") to load multiple specific craft types."}
minetest.register_chatcommand("recipeclear", {
	params = "",
	description = "Clear all recipes from simplecrafting_lib",
	func = function(name, param)
		if not minetest.check_player_privs(name, {server = true}) then
			minetest.chat_send_player(name, "You need the \"server\" priviledge to use this command.", false)
			return
		end
		
		local success, options, args = clearoptparse.parse_args(param)
		if not success then
			minetest.chat_send_player(name, options)
			return
		end
		
		if options.help then
			minetest.chat_send_player(name, clearoptparse.print_help())
			return
		end

		local craft_types = split(options.types, ",")
		if table.getn(craft_types) > 0 then
			for _, craft_type in pairs(craft_types) do
				if simplecrafting_lib.type[craft_type] == nil then
					minetest.chat_send_player(name, "Craft type " .. craft_type .. " was already clear.", false)
				else
					simplecrafting_lib.type[craft_type] = nil
				end
			end
		else
			simplecrafting_lib.type = {}
		end
		minetest.chat_send_player(name, "Recipes cleared", false)
	end,
})


minetest.register_chatcommand("recipecompare", {
	params="<infile> <outfile>",
	description="Compares existing recipe data to the data in \"(world folder)/<infile>.lua\", outputting the differences to \"(world folder)/<outfile>.txt\"",
	func = function(name, param)
		if not minetest.check_player_privs(name, {server = true}) then
			minetest.chat_send_player(name, "You need the \"server\" priviledge to use this command.", false)
			return
		end

		local params = split(param)
		if #params ~= 2 then
			minetest.chat_send_player(name, "Invalid usage, two filename parameters separted by a space are needed", false)
			return
		end
		
		if diff_recipes(params[1], params[2]) then
			minetest.chat_send_player(name, "Recipes diffed", false)
		else
			minetest.chat_send_player(name, "Failed to diff recipes", false)
		end
	end,
})

minetest.register_chatcommand("recipestats", {
	params="",
	description="Outputs stats about registered recipes",
	func = function(name, param)
		if not minetest.check_player_privs(name, {server = true}) then
			minetest.chat_send_player(name, "You need the \"server\" priviledge to use this command.", false)
			return
		end
		
		for craft_type, recipe_lists in pairs(simplecrafting_lib.type) do
		
			minetest.chat_send_player(name, "recipe type: "..craft_type)
			minetest.chat_send_player(name, tostring(table.getn(recipe_lists.recipes)) .. " recipes")
			local max_inputs = 0
			for _, recipe in pairs(recipe_lists.recipes) do
				local itemcount = 0
				for item, count in pairs(recipe.input) do
					itemcount = itemcount + 1
				end
				max_inputs = math.max(max_inputs, itemcount)
			end
			minetest.chat_send_player(name, "Largest number of input types: " .. tostring(max_inputs))
		end	
	end,
})

-- TODO: need a recipestats command to get general information about recipes