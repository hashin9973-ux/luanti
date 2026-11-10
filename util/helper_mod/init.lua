local mode = core.settings:get("helper_mode")

if mode == "devtest" then

	-- Provide feedback to script by creating files in world path
	core.after(0, function()
		io.close(io.open(core.get_worldpath() .. "/startup", "w"))
	end)
	local function callback(test_ok)
		if not test_ok then
			io.close(io.open(core.get_worldpath() .. "/test_failure", "w"))
		end
		io.close(io.open(core.get_worldpath() .. "/done", "w"))
		core.request_shutdown("", false, 2)
	end
	-- If tests are enabled exit when they're done, otherwise exit on player join
	if core.settings:get_bool("devtest_unittests_autostart") and core.global_exists("unittests") then
		unittests.on_finished = callback
	else
		core.register_on_joinplayer(function() callback(true) end)
	end

elseif mode == "pbr_visual" then

	-- Build a deterministic stone room for the automated POM image comparison.
	local worldpath = core.get_worldpath()
	local ready_path = worldpath .. "/pbr_visual_ready"
	local captured_path = worldpath .. "/pbr_visual_capture_done"

	local function write_marker(path)
		local file, err = io.open(path, "w")
		if not file then
			core.log("error", "[pbr_visual] Unable to write " .. path .. ": " .. tostring(err))
			return false
		end
		file:write("ok\\n")
		file:close()
		return true
	end

	local function wait_for_capture()
		local file = io.open(captured_path, "r")
		if file then
			file:close()
			core.request_shutdown("PBR visual capture complete", false, 1)
			return
		end
		core.after(0.2, wait_for_capture)
	end

	core.register_on_joinplayer(function(player)
		local scene_created = false
		core.emerge_area(
			{x = -10, y = -8, z = -10},
			{x = 10, y = 8, z = 12},
			function(_, action, calls_remaining)
				if action == core.EMERGE_ERRORED then
					write_marker(worldpath .. "/pbr_visual_error")
					return
				end
				if calls_remaining ~= 0 or scene_created then
					return
				end
				scene_created = true

				-- Clear and construct the same room each run. The front wall is
				-- intentionally viewed at an oblique angle so height displacement
				-- produces a measurable UV/pixel difference.
				for x = -8, 8 do
					for y = -4, 4 do
						for z = -8, 8 do
							core.set_node({x = x, y = y, z = z}, {name = "air"})
						end
					end
				end
				for x = -8, 8 do
					for y = -4, 4 do
						core.set_node({x = x, y = y, z = 7}, {name = "basenodes:stone"})
					end
				end
				for x = -8, 8 do
					for z = -8, 7 do
						core.set_node({x = x, y = -4, z = z}, {name = "basenodes:stone"})
					end
				end
				for y = -3, 4 do
					for z = -8, 7 do
						core.set_node({x = -8, y = y, z = z}, {name = "basenodes:stone"})
						core.set_node({x = 8, y = y, z = z}, {name = "basenodes:stone"})
					end
				end

				core.set_timeofday(0.5)
				player:set_pos({x = 0, y = 0, z = 0})
				player:set_look_horizontal(0.35)
				player:set_look_vertical(0)
				player:set_physics_override({speed = 0, jump = 0, gravity = 0})

				core.after(2, function()
					if write_marker(ready_path) then
						wait_for_capture()
					end
				end)
			end
		)
	end)

elseif mode == "mapgen" then

	-- Stress-test mapgen by constantly generating new area
	local csize = tonumber(core.settings:get("chunksize")) * core.MAP_BLOCKSIZE
	local MINP, MAXP = vector.new(0, -csize, 0), vector.new(csize*3, csize*2, csize)
	local DIR = "x"
	local pstart = vector.new(0, 0, 0)
	local next_, callback
	next_ = function(arg)
		print("emerging " .. core.pos_to_string(pstart))
		core.emerge_area(
			vector.add(pstart, MINP), vector.add(pstart, MAXP),
			callback, arg
		)
	end
	local trig = {}
	callback = function(blockpos, action, calls_rem, n)
		if action == core.EMERGE_ERRORED then
			print("emerge errored!")
			return
		end
		if calls_rem <= 20 and not trig[n] then
			trig[n] = true
			pstart[DIR] = pstart[DIR] + (MAXP[DIR] - MINP[DIR])
			next_(n + 1)
		end
	end
	core.after(0, next_, 1)

elseif mode == "error" then

	local n = tonumber(core.settings:get("error_type"))
	local modpath = core.get_modpath(core.get_current_modname())
	if n == 1 then
		print("=> error during startup <=")
		error("intentional")
	elseif n == 2 then
		print("=> error on first step <=")
		core.after(0, error, "intentional")
	elseif n == 3 then
		print("=> error in async script <=")
		core.register_async_dofile(modpath .. "/error.lua")
	elseif n == 4 then
		print("=> error in mapgen script <=")
		core.register_mapgen_script(modpath .. "/error.lua")
	elseif n == 5 then
		print("=> error in mapgen env callback <=")
		core.register_mapgen_script(modpath .. "/mapgen_error.lua")
		core.after(0, function()
			-- emerge something to trigger it
			core.emerge_area(vector.new(0,0,0), vector.new(1,1,1), function(pos, action)
				print("action=" .. action)
			end)
		end)
	elseif n == 6 then
		print("=> error in emerge_area callback <=")
		core.after(0, function()
			core.emerge_area(vector.new(0,0,0), vector.new(1,1,1), function()
				error("intentional")
			end)
		end)
	else
		assert(false)
	end

end
