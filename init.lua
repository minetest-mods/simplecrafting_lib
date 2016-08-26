crafting = {}
crafting.recipes = {}
crafting.recipes_by_output = {}

local recipes = crafting.recipes
local recipes_by_out = crafting.recipes_by_output

local function itemlist_to_countlist(list)
	local count_list = {}
	for i,v in ipairs(list) do
		if not v:is_empty() then
			local name = v:get_name()
			count_list[name] = (count_list[name] or 0) + v:get_count()
			if minetest.registered_items[name] then
				for group,_ in pairs(minetest.registered_items[name].groups or {}) do
					if not count_list[group] 
					or (count_list[group] 
					and count_list[count_list[group]] < count_list[name]) then
						count_list[group] = name
					end
				end
			end
		end
	end
	return count_list
end

local function get_craft_no(input_list,recipe)
	local no = math.huge
	local work_recipe = {input={},output=table.copy(recipe.output)
		,ret=table.copy(recipe.ret)}
	local input = work_recipe.input
	for k,v in pairs(recipe.input) do
		if not input_list[k] then
			return 0
		end
		if type(input_list[k]) == "string" then
			input[input_list[k]] = (input[input_list[k]] or 0) + v
		else
			input[k] = (input[k] or 0) + v
		end
	end
	for k,v in pairs(input) do
		local max = input_list[k] / v
		if max < 1 then
			return 0
		elseif max < no then
			no = max
		end
	end
	return math.floor(no),work_recipe
end


local function get_craftable_items(input_list)
	local craftable = {}
	local chosen = {}
	for i=1,#recipes do
		local no,recipe = get_craft_no(input_list,recipes[i])
		if no > 0 then
			for j,v in pairs(recipe.output) do
				if craftable[j] and v*no > craftable[j] then
					craftable[j] = v*no
					chosen[j] = recipe
				elseif not craftable[j] and v*no > 0 then
					craftable[#craftable+1] = j
					craftable[j] = v*no
					chosen[j] = recipe
				end
			end
		end
	end
	-- Limit stacks to stack limit
	for i=1,#craftable do
		local item = craftable[i]
		local count = craftable[item]
		local stack = ItemStack(item)
		local max = stack:get_stack_max()
		if count > max then
			count = max - max % chosen[item].output[item]
		end
		stack:set_count(count)
		craftable[i] = stack
		craftable[item] = nil
	end
	return craftable
end

local function refresh_output(inv)
	local itemlist = itemlist_to_countlist(inv:get_list("store"))
	local craftable = get_craftable_items(itemlist)
	inv:set_size("output",#craftable + ((16*5) - (#craftable%(16*5))))
	inv:set_list("output",craftable)
end

local function make_formspec(page,noitems)
	if noitems < page * 80 then
		page = 0
	end
	local inventory = {
		"size[16,12]"
		, "list[context;output;0,0;16,5;" , tostring(page*(16*5)), "]"
		, "list[context;store;4,5.2;8,2;]"
		, "list[current_player;main;4,8;8,4;]"
		, "listring[context;output]"
		, "listring[current_player;main]"
		, "listring[context;store]"
		, "listring[current_player;main]"
	}
	if noitems > (page+1) * 80 then
		inventory[#inventory+1] = "button[14,5.2;1,1;next;>]"
	end
	if page > 0 then
		inventory[#inventory+1] = "button[13,5.2;1,1;prev;<]"
	end
	inventory[#inventory+1] = "label[13,6.2;Page " .. tostring(page) .. "]"

	return table.concat(inventory) , page
end

local function refresh_inv(meta)
	local inv = meta:get_inventory()
	refresh_output(inv)

	local page = meta:get_int("page")
	local form, page = make_formspec(page,inv:get_size("output"))
	meta:set_int("page",page)
	meta:set_string("formspec",form)
end

local function pay_items(inv,crafted,to_inv,to_list,player,no_crafted)
	local name = crafted:get_name()
	local no = no_crafted
	local itemlist = itemlist_to_countlist(inv:get_list("store"))
	local max = 0
	local craft_using
	-- Get recipe which can craft the most
	for i=1,#recipes_by_out[name] do
		local out,recipe = get_craft_no(itemlist,recipes_by_out[name][i])
		if out > 0 and out * recipe.output[name] > max then
			max = out * recipe.output[name]
			craft_using = recipe
		end
	end

	-- Increase amount taken if not a multiple of recipe output
	local output_factor = craft_using.output[name]
	if no % output_factor ~= 0 then
		no = no - (no % output_factor)
		if no + output_factor <= crafted:get_stack_max() then
			no = no + output_factor
		end
	end

	-- Take consumed items
	local input = craft_using.input
	local no_crafts = math.floor(no / output_factor)
	for k,v in pairs(input) do
		inv:remove_item("store",k .. " " .. tostring(no_crafts * v))
	end

	-- Add excess items
	local output = craft_using.output
	for k,v in pairs(output) do
		local to_add 
		if k == name then
			to_add = no - no_crafted
		else
			to_add = no_crafts * v
		end
		if no > 0 then
			local stack = ItemStack(k)
			local max = stack:get_stack_max()
			stack:set_count(max)
			while to_add > 0 do
				if to_add > max then
					to_add = to_add - max
				else
					stack:set_count(to_add)
					to_add = 0
				end
				local excess = to_inv:add_item(to_list,stack)
				if not excess:is_empty() then
					minetest.item_drop(excess,player,player:getpos())
				end
			end
		end
	end
	-- Add return items - copied code from above
	for k,v in pairs(craft_using.ret) do
		local to_add 
		to_add = no_crafts * v
		if no > 0 then
			local stack = ItemStack(k)
			local max = stack:get_stack_max()
			stack:set_count(max)
			while to_add > 0 do
				if to_add > max then
					to_add = to_add - max
				else
					stack:set_count(to_add)
					to_add = 0
				end
				local excess = to_inv:add_item(to_list,stack)
				if not excess:is_empty() then
					minetest.item_drop(excess,player,player:getpos())
				end
			end
		end
	end
end

crafting.register = function(typeof,def)
	def.ret = def.ret or {}
	for k,v in pairs(def.input) do
		local group = string.match(k,"^group:(%S+)$")
		if group then
			def.input[group] = v
			def.input[k] = nil
		end
	end
	recipes[#recipes+1] = def
	for k,v in pairs(def.output) do
		recipes_by_out[k] = recipes_by_out[k] or {} 
		recipes_by_out[k][#recipes_by_out[k]+1] = def
	end
end

local function swap_fix(inv,stack,new_stack,tinv,tlist,player)
	if (not new_stack:is_empty() 
	and new_stack:get_name() ~= stack:get_name())
	or new_stack:get_count() == new_stack:get_stack_max() then
		local excess = tinv:add_item(tlist,new_stack)
		if not excess:is_empty() then
			minetest.item_drop(excess,player,player:getpos())
		end
		-- Whole stack has been taken - calculate how many
		local count = 0
		local no_per_out = 1
		local name = stack:get_name()
		for i=1,#recipes_by_out[name] do
			local out,recipe = get_craft_no(itemlist_to_countlist(inv:get_list("store")),recipes_by_out[name][i])
			if out > 0 and out * recipe.output[name] > count then
				count = out * recipe.output[name]
				no_per_out = recipe.output[name]
			end
		end
		-- Stack limit correction
		local max = stack:get_stack_max()
		if max < count then
			count = max - (max % no_per_out)
		end
		return count
	end
end
		
minetest.register_node("crafting:table",{
	drawtype = "normal",
	tiles = {"default_chest_top.png^default_rail_crossing.png","default_chest_top.png"
		,"default_chest_side.png","default_chest_side.png"
		,"default_chest_side.png","default_chest_side.png"},
	paramtype2 = "facedir",
	is_ground_content = false,
	groups = {oddly_breakable_by_hand = 1,choppy=3},
	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()
		inv:set_size("store", 8*2)
		inv:set_size("output", 16*5)
		meta:set_int("page",0)
		meta:set_string("formspec",make_formspec(0,0))
	end,
	allow_metadata_inventory_move = function(pos,flist,fi,tlist,ti,no,player)
		if tlist == "output" then
			return 0
		end
		return no + 1
	end,
	allow_metadata_inventory_put = function(pos,lname,i,stack,player)
		if lname == "output" then
			return 0
		end
		return stack:get_count()
	end,
	on_metadata_inventory_move = function(pos,flist,fi,tlist,ti,no,player)
		local meta = minetest.get_meta(pos)
		if flist == "output" and tlist == "store" then
			local inv = meta:get_inventory()
			local stack = inv:get_stack(tlist,ti)
			local new_stack = inv:get_stack(flist,fi)
			local count = swap_fix(inv,stack,new_stack,inv
				,"store",player) or no 
			pay_items(inv,stack,inv,"store",player,count)
		end
		refresh_inv(meta)
	end,
	on_metadata_inventory_take = function(pos,lname,i,stack,player)
		local meta = minetest.get_meta(pos)
		if lname == "output" then
			local inv = meta:get_inventory()
			local new_stack = inv:get_stack(lname,i)
			local count = swap_fix(inv,stack,new_stack
				,player:get_inventory(),"main",player) or stack:get_count()

			-- Fix issues with swapping

			pay_items(inv,stack,player:get_inventory(),"main",player,count)
		end
		refresh_inv(meta)
	end,
	on_metadata_inventory_put = function(pos,lname,i,stack,player)
		local meta = minetest.get_meta(pos)
		refresh_inv(meta)
	end,
	on_receive_fields = function(pos,formname,fields,sender)
		local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()
		local page = meta:get_int("page")
		if fields.next then
			page = page + 1
		elseif fields.prev  then
			page = page - 1
		else
			return
		end
		local form, page = make_formspec(page,inv:get_size("output"))
		meta:set_int("page",page)
		meta:set_string("formspec",form)
	end,
	can_dig = function(pos,player)
		local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()
		return inv:is_empty("store")
	end,
	--allow_metadata_inventory_take = function(pos,lname,i,stack,player) end,
})

dofile(minetest.get_modpath("crafting") .. "/recipe.lua")
dofile(minetest.get_modpath("crafting") .. "/legacy.lua")
