crafting.register("table",{
	input = {
		["default:stone"] = 1,
		["default:lava_source"] = 1,
	},
	output = {
		["default:obsidian"] = 2,
	},
	ret = {
		["default:stone"] = 1,
	},
})

for i=1,100 do
	crafting.register("table",{
		input = {
			["default:dirt_with_grass"] = 1,
		},
		output = {
			["invalid:thing" .. tostring(i)] = 1,
		},
	})
end
