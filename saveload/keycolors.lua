local write_new_color_file = false
local last_assigned_hue = math.random()
local last_assigned_saturation = math.random()
local golden_ratio_conjugate = 0.618033988749895 -- for spreading out the random colours more evenly, reducing clustering

local key_color_map
local path = minetest.get_worldpath()
local color_filename = path .. "/simplecrafting_key_colors.lua"
local color_file = loadfile(color_filename)
if color_file ~= nil then
	key_color_map = color_file()
else
	key_color_map = {}
end

-- HSV values in [0..1[
-- returns {r, g, b} values from 0 to 255
local hsv_to_rgb = function(h, s, v)
	local h_i = math.floor(h*6)
	local f = h*6 - h_i
	local p = v * (1 - s)
	local q = v * (1 - f*s)
	local t = v * (1 - (1 - f) * s)
	local r, g, b
	if h_i==0 then r, g, b = v, t, p
	elseif h_i==1 then r, g, b = q, v, p
	elseif h_i==2 then r, g, b = p, v, t
	elseif h_i==3 then r, g, b = p, q, v
	elseif h_i==4 then r, g, b = t, p, v
	elseif h_i==5 then r, g, b = v, p, q
	end
	return {math.floor(r*255), math.floor(g*255), math.floor(b*255)}
end

simplecrafting_lib.get_key_color = function(key)
	if not key_color_map[key] then
		last_assigned_hue = last_assigned_hue + golden_ratio_conjugate
		last_assigned_hue = last_assigned_hue % 1
		last_assigned_saturation = last_assigned_saturation + golden_ratio_conjugate
		last_assigned_saturation = last_assigned_saturation % 1
		local color_vec = hsv_to_rgb(last_assigned_hue, last_assigned_saturation/2 + 0.5, 1)
		color = "#"..string.format('%02X', color_vec[1])..string.format('%02X', color_vec[2])..string.format('%02X', color_vec[3])
		key_color_map[key] = color
		write_new_color_file = true
		return color
	else
		return key_color_map[key]
	end			
end

simplecrafting_lib.save_key_colors = function()
	if write_new_color_file then
		local color_file, err = io.open(color_filename, "w")
		if err == nil then
			color_file:write("return "..dump(key_color_map))
			color_file:flush()
			color_file:close()
			write_new_color_file = false
		end
	end
end