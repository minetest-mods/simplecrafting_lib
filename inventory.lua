-- Returns nil if there's no leftovers
-- Otherwise returns a countlist of leftovers
local add_count_list = function(inv, listname, count_list)
	local leftover_list	
	for item, count in pairs(count_list) do
		local stack_max = ItemStack(item):get_stack_max()
		while count > 0 do
			local to_add = math.min(count, stack_max)
			local leftover = inv:add_item(listname, ItemStack({name=item, count=to_add}))
			local leftover_count = leftover:get_count()
			if leftover_count > 0 then
				leftover_list = leftover_list or {}
				leftover_list[item] = (leftover_list[item] or 0) + leftover_count + count
				break
			end
			count = count - to_add
		end
	end
	return leftover_list
end

-- Attempts to add the items in count_list to the inventory.
-- Returns a count list containing the items that couldn't be added.
simplecrafting_lib.add_items = function(inv, listname, count_list)
	return add_count_list(inv, listname, count_list) or {}
end

-- Attempts to add the items in count_list to the inventory.
-- If it succeeds, returns true.
-- If it fails, the inventory is not modified and returns false.
simplecrafting_lib.add_items_if_room = function(inv, listname, count_list)
	local old_list = inv:get_list(listname) -- record current inventory
	if not add_count_list(inv, listname, count_list) then
		inv:set_list(listname, old_list) -- reset inventory
		return false
	end
	return true
end

-- Returns true if there's room in the inventory for all of the items in the count list,
-- false otherwise.
simplecrafting_lib.room_for_items = function(inv, listname, count_list)
	local old_list = inv:get_list(listname) -- record current inventory
	local result = add_count_list(inv, listname, count_list)
	inv:set_list(listname, old_list) -- reset inventory
	return result ~= nil
end

-- removes the items in the count_list (formatted as per recipe standards)
-- from the inventory. Returns true on success, false on failure. Does not
-- affect the inventory on failure (removal is atomic)
simplecrafting_lib.remove_items = function(inv, listname, count_list)
	local old_list = inv:get_list(listname) -- record current inventory
	for item, count in pairs(count_list) do
		while count > 0 do
			-- We need to do this loop because we may be wanting to remove more items than
			-- a single stack of that item can hold.
			-- https://github.com/minetest/minetest/issues/8883
			local stack_to_remove = ItemStack({name=item, count=count})
			stack_to_remove:set_count(math.min(count, stack_to_remove:get_stack_max()))
			local removed = inv:remove_item(listname, stack_to_remove)
			if removed:is_empty() then
				-- ran out of things to take. Reset the inventory and return false
				inv:set_list(listname, old_list)
				return false
			end
			count = count - removed:get_count()
		end
	end	
	return true
end

-- Drops the contents of a count_list at the given location in the world
simplecrafting_lib.drop_items = function(pos, count_list)
	for item, count in pairs(count_list) do
		local stack_max = ItemStack(item):get_stack_max()
		while count > 0 do
			local to_add = math.min(count, stack_max)
			minetest.add_item(pos, ItemStack({name=item, count=to_add}))
			count = count - to_add
		end
	end
end
