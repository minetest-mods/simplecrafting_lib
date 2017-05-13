-- Attempts to add the items in count_list to the inventory.
-- Returns a count list containing the items that couldn't be added.
simplecrafting_lib.add_items = function(inv, listname, count_list)
	local leftover_list = {}
	
	for item, count in pairs(count_list) do
		local leftover = inv:add_item(listname, ItemStack({name=item, count=count}))
		if leftover:get_count() > 0 then
			leftover_list[leftover:get_name()] = leftover:get_count()
		end
	end
	return leftover_list
end

-- Attempts to add the items in count_list to the inventory.
-- If it succeeds, returns true.
-- If it fails, the inventory is not modified and returns false.
simplecrafting_lib.add_items_if_room = function(inv, listname, count_list)
	local old_list = inv:get_list(listname) -- record current inventory
	
	for item, count in pairs(count_list) do
		local leftover = inv:add_item(listname, ItemStack({name=item, count=count}))
		if leftover:get_count() > 0 then
			inv:set_list(listname, old_list) -- reset inventory
			return false
		end
	end
	return true
end

-- Returns true if there's room in the inventory for all of the items in the count list,
-- false otherwise.
simplecrafting_lib.room_for_items = function(inv, listname, count_list)
	local old_list = inv:get_list(listname) -- record current inventory
	
	for item, count in pairs(count_list) do
		local leftover = inv:add_item(listname, ItemStack({name=item, count=count}))
		if leftover:get_count() > 0 then
			inv:set_list(listname, old_list) -- reset inventory
			return false
		end
	end
	inv:set_list(listname, old_list) -- reset inventory
	return true
end

-- removes the items in the count_list (formatted as per recipe standards)
-- from the inventory. Returns true on success, false on failure. Does not
-- affect the inventory on failure (removal is atomic)
simplecrafting_lib.remove_items = function(inv, listname, count_list)
	local can_remove = true
	for item, count in pairs(count_list) do
		if not inv:contains_item(listname, ItemStack({name=item, count=count})) then
			can_remove = false
			break
		end
	end
	if can_remove then
		for item, count in pairs(count_list) do
			inv:remove_item(listname, ItemStack({name=item, count=count}))
		end	
		return true
	end
	return false
end

-- Drops the contents of a count_list at the given location in the world
simplecrafting_lib.drop_items = function(pos, count_list)
	for item, count in pairs(count_list) do
		minetest.add_item(pos, ItemStack({name=item, count=count}))
	end
end
