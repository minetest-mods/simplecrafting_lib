minetest.register_chatcommand("/saverecipes", {
	params = "<file>",
	description = "Save the current recipes to \"(world folder)/schems/<file>.lua\"",
	func = function(name, param)
		if param == "" then
			minetest.chat_send_player(name, "Invalid usage, filename parameter needed", false)
			return
		end
		
		simplecrafting_lib.save_by_out(param)

		minetest.chat_send_player(name, "Recipes saved", false)
	end,
})

--[[
Ordered table iterator
From http://lua-users.org/wiki/SortedIteration
]]

function __genOrderedIndex( t )
    local orderedIndex = {}
    for key in pairs(t) do
        table.insert( orderedIndex, key )
    end
    table.sort( orderedIndex )
    return orderedIndex
end

function orderedNext(t, state)
    -- Equivalent of the next function, but returns the keys in the alphabetic
    -- order. We use a temporary ordered key table that is stored in the
    -- table being iterated.

    local key = nil
    --print("orderedNext: state = "..tostring(state) )
    if state == nil then
        -- the first time, generate the index
        t.__orderedIndex = __genOrderedIndex( t )
        key = t.__orderedIndex[1]
    else
        -- fetch the next value
        for i = 1,table.getn(t.__orderedIndex) do
            if t.__orderedIndex[i] == state then
                key = t.__orderedIndex[i+1]
            end
        end
    end

    if key then
        return key, t[key]
    end

    -- no more value to return, cleanup
    t.__orderedIndex = nil
    return
end

function orderedPairs(t)
    -- Equivalent of the pairs() function on tables. Allows to iterate
    -- in order
    return orderedNext, t, nil
end


simplecrafting_lib.save_by_out = function(param)

	local path = minetest.get_worldpath()
	local filename = path .. "/" .. param .. ".lua"
	local file, err = io.open(filename, "w")
	if err ~= nil then
		minetest.log("error", "[simplecrafting_lib] Could not save recipes to \"" .. filename .. "\"")
		return
	end
	
	file:write("return {\n")
	for craft_type, recipe_list in pairs(simplecrafting_lib.type) do
		file:write("-- Craft Type " .. craft_type .. "--------------------------------------------------------\n" .. craft_type .. " = {\n")
		for out, recipe_list in orderedPairs(recipe_list.recipes_by_out) do
			file:write("\t{[\"" .. out .. "\"] = {\n")
			for _, recipe in ipairs(recipe_list) do
				file:write("\t\t{\n")
				for key, val in pairs(recipe) do
					file:write("\t\t\t"..key.." = ")
					if type(val) == "table" then
						file:write("\t{")
						for kk, vv in pairs(val) do
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
						file:write(tostring(val) .. ",\n")
					end			
				end
				file:write("\t\t},\n")
			end
			file:write("\t},\n")
		end
		file:write("},\n")
	end
	file:write("}\n")

	file:flush()
	file:close()

end