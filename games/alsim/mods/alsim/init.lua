--[[
	Copyright (c) 2016 Scott Lembcke and Howling Moon Software
	
	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:
	
	The above copyright notice and this permission notice shall be included in
	all copies or substantial portions of the Software.
	
	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.
	
	TODO:
	* Print short function arguments as part of stack location.
	* Bug: sometimes doesn't advance to next line (same line event reported multiple times).
	* Do coroutines work as expected?
]]


-- Use ANSI color codes in the prompt by default.
local COLOR_RED = ""
local COLOR_BLUE = ""
local COLOR_GRAY = ""
local COLOR_RESET = ""

local function pretty(obj, max_depth)
	if max_depth == nil then max_depth = 1 end

	-- Returns true if a table has a __tostring metamethod.
	local function coerceable(tbl)
		local meta = getmetatable(tbl)
		return (meta and meta.__tostring)
	end

	local depth = 1
	local function recurse(obj)
		if type(obj) == "string" then
			-- Dump the string so that escape sequences are printed.
			return string.format("%q", obj)
		elseif type(obj) == "table" and not coerceable(obj) then
			if pairs(obj)(obj) == nil then
				return '{}' -- Always print empty tables.
			end
			if depth > max_depth then
				return tostring(obj)
			end

			local str = "{"
			depth = depth + 1

			for k, v in pairs(obj) do
				local pair = pretty(k, 0).." = "..recurse(v)
				str = str..(str == "{" and pair or ", "..pair)
			end

			depth = depth - 1
			return str.."}"
		else
			-- tostring() can fail if there is an error in a __tostring metamethod.
			local success, value = pcall(function() return tostring(obj) end)
			return (success and value or "<!!error in __tostring metamethod!!>")
		end
	end

	return recurse(obj)
end

local help_message = [[
[return] - re-run last command
c(ontinue) - continue execution
s(tep) - step forward by one line (into functions)
n(ext) - step forward by one line (skipping over functions)
f(inish) - step forward until exiting the inspected frame
u(p) - inspect the next frame up the stack
d(own) - inspect the next frame down the stack
p(rint) [expression] - execute the expression and print the result
e(val) [statement] - execute the statement
t(race) - print the stack trace
l(ocals) - print the function arguments, locals and upvalues.
h(elp) - print this message
q(uit) - halt execution]]

-- The stack level that cmd_* functions use to access locals or info
-- The structure of the code very carefully ensures this.
local LOCAL_STACK_LEVEL = 6

-- Extra stack frames to chop off.
-- Used for things like dbgcall() or the overridden assert/error functions
local stack_top = 0

-- The current stack frame index.
-- Changed using the up/down commands
local stack_offset = 0

local dbg

-- Default dbg.read function
local function dbg_read(prompt)
	dbg.write(prompt)
	return io.read()
end

-- Default dbg.write function
local function dbg_write(str, ...)
	if select("#", ...) == 0 then
		io.write(str or "<NULL>")
	else
		io.write(string.format(str, ...))
	end
end

-- Default dbg.writeln function.
local function dbg_writeln(str, ...)
	dbg.write((str or "").."\n", ...)
end

local cwd = '^' .. os.getenv('PWD') .. '/'
local home = '^' .. os.getenv('HOME') .. '/'
local function format_stack_frame_info(info)
	local path = info.source:sub(2)
	path = path:gsub(cwd, './'):gsub(home, '~/')
	if #path > 50 then
		path = '...' .. path:sub(-47)
	end
	local fname = (info.name or string.format("<%s:%d>", path, info.linedefined))
	return string.format(COLOR_BLUE.."%s:%d"..COLOR_RESET.." in '%s'", path, info.currentline, fname)
end

local repl

-- Return false for stack frames without a source file,
-- which includes C frames and pre-compiled Lua bytecode.
local function frame_has_file(info)
	return info.what == "main" or info.source:match("^@[%.%/]") ~= nil
end

local function hook_factory(repl_threshold)
	return function(offset)
		return function(event, _)
			local info = debug.getinfo(2)
			local has_file = frame_has_file(info)
			
			if event == "call" and has_file then
				offset = offset + 1
			elseif event == "return" and has_file then
				if offset <= repl_threshold then
					-- TODO this is what causes the duplicated lines
					-- Don't remember why this is even here...
					--repl()
				else
					offset = offset - 1
				end
			elseif event == "line" and offset <= repl_threshold then
				repl()
			end
		end
	end
end

local hook_step = hook_factory(1)
local hook_next = hook_factory(0)
local hook_finish = hook_factory(-1)

local function local_bind(offset, name, value)
	local level = stack_offset + offset + LOCAL_STACK_LEVEL

	-- Mutating a local?
	do local i = 1; repeat
		local var = debug.getlocal(level, i)
		if name == var then
			return debug.setlocal(level, i, value)
		end
		i = i + 1
	until var == nil end

	-- Mutating an upvalue?
	local func = debug.getinfo(level).func
	do local i = 1; repeat
		local var = debug.getupvalue(func, i)
		if name == var then
			return debug.setupvalue(func, i, value)
		end
		i = i + 1
	until var == nil end

	dbg.writeln(COLOR_RED.."Error: "..COLOR_RESET.."Unknown local variable: "..name)
end

-- Create a table of all the locally accessible variables.
-- Globals are not included when running the locals command, but are when running the print command.
local function local_bindings(offset, include_globals)
	local level = stack_offset + offset + LOCAL_STACK_LEVEL
	local func = debug.getinfo(level).func
	local bindings = {}
	local i

	-- Retrieve the upvalues
	i = 1; while true do
		local name, value = debug.getupvalue(func, i)
		if not name then break end
		bindings[name] = value
		i = i + 1
	end

	-- Retrieve the locals (overwriting any upvalues)
	i = 1; while true do
		local name, value = debug.getlocal(level, i)
		if not name then break end
		bindings[name] = value
		i = i + 1
	end

	-- Retrieve the varargs (works in Lua 5.2 and LuaJIT)
	local varargs = {}
	i = 1; while true do
		local name, value = debug.getlocal(level, -i)
		if not name then break end
		varargs[i] = value
		i = i + 1
	end
	if i > 1 then bindings["..."] = varargs end

	if include_globals then
		-- In Lua 5.2, you have to get the environment table from the function's locals.
		local env = (_VERSION <= "Lua 5.1" and getfenv(func) or bindings._ENV)
		return setmetatable(bindings, {__index = env or _G})
	else
		return bindings
	end
end --189

-- Compile an expression with the given variable bindings.
local function compile_chunk(block, env)
	local source = "debugger.lua REPL"
	local chunk = nil
	
	if _VERSION <= "Lua 5.1" then
		chunk = loadstring(block, source)
		if chunk then setfenv(chunk, env) end
	else
		-- The Lua 5.2 way is a bit cleaner
		chunk = load(block, source, "t", env)
	end
	
	if chunk then
		return chunk
	else
		dbg.writeln(COLOR_RED.."Error: Could not compile block:\n"..COLOR_RESET..block)
		return nil
	end
end

-- Wee version differences
local unpack = unpack or table.unpack
local pack = table.pack or function(...)
	return {n = select("#", ...), ...}
end

function cmd_step()
	stack_offset = stack_top
	return true, hook_step
end

function cmd_next()
	stack_offset = stack_top
	return true, hook_next
end

function cmd_finish()
	local offset = stack_top - stack_offset
	stack_offset = stack_top
	return true, offset < 0 and hook_factory(offset - 1) or hook_finish
end

local function cmd_print(expr)
	local env = local_bindings(1, true)
	local chunk = compile_chunk("return "..expr, env)
	if chunk == nil then return false end
	
	-- Call the chunk and collect the results.
	local results = pack(pcall(chunk, unpack(rawget(env, "...") or {})))

	-- The first result is the pcall error.
	if not results[1] then
		dbg.writeln(COLOR_RED.."Error:"..COLOR_RESET.." %s", results[2])
	else
		local output = ""
		for i = 2, results.n do
			output = output..(i ~= 2 and ", " or "")..pretty(results[i], 3)
		end
		if output == "" then
			output = COLOR_GRAY.."<no result>"
		end
		dbg.writeln(COLOR_BLUE..expr..COLOR_RED.." => "..COLOR_RESET..output)
	end
	
	return false
end

local function cmd_eval(code)
	local index = local_bindings(1, true)
	local env = setmetatable({}, {
		__index = index,
		__newindex = function(env, name, value)
			local_bind(4, name, value)
		end
	})

	local chunk = compile_chunk(code, env)
	if chunk == nil then return false end

	-- Call the chunk and collect the results.
	local success, err = pcall(chunk, unpack(rawget(index, "...") or {}))
	if success then
		-- Look for assigned variable names.
		local names = code:match("^([^{=]+)%s?=[^=]")
		if names then
			stack_offset = stack_offset + 1
			cmd_print(names)
			stack_offset = stack_offset - 1
		end
	else
		dbg.writeln(COLOR_RED.."Error:"..COLOR_RESET.." %s", err)
	end
end

local function cmd_up()
	local offset = stack_offset
	local info
	repeat -- Find the next frame with a file.
		offset = offset + 1
		info = debug.getinfo(offset + LOCAL_STACK_LEVEL)
	until not info or frame_has_file(info)

	if info then
		stack_offset = offset
	else
		info = debug.getinfo(stack_offset + LOCAL_STACK_LEVEL)
		dbg.writeln(COLOR_BLUE.."Already at the top of the stack."..COLOR_RESET)
	end

	dbg.writeln("Inspecting frame: "..format_stack_frame_info(info))
	return false
end

local function cmd_down()
	local offset = stack_offset
	local info
	repeat -- Find the next frame with a file.
		offset = offset - 1
		if offset < stack_top then info = nil; break end
		info = debug.getinfo(offset + LOCAL_STACK_LEVEL)
	until frame_has_file(info)

	if info then
		stack_offset = offset
	else
		info = debug.getinfo(stack_offset + LOCAL_STACK_LEVEL)
		dbg.writeln(COLOR_BLUE.."Already at the bottom of the stack."..COLOR_RESET)
	end

	dbg.writeln("Inspecting frame: "..format_stack_frame_info(info))
	return false
end

local function cmd_trace()
	local location = format_stack_frame_info(debug.getinfo(stack_offset + LOCAL_STACK_LEVEL))
	local offset = stack_offset - stack_top
	local message = string.format("Inspecting frame: %d - (%s)", offset, location)
	local str = debug.traceback(message, stack_top + LOCAL_STACK_LEVEL)
	
	-- Iterate the lines of the stack trace so we can highlight the current one.
	local line_num = -2
	while str and #str ~= 0 do
		local line, rest = string.match(str, "([^\n]*)\n?(.*)")
		str = rest
		
		if line_num >= 0 then line = tostring(line_num)..line end
		dbg.writeln((line_num + stack_top == stack_offset) and COLOR_BLUE..line..COLOR_RESET or line)
		line_num = line_num + 1
	end
	
	return false
end

local function cmd_locals()
	local bindings = local_bindings(1, false)
	
	-- Get all the variable binding names and sort them
	local keys = {}
	for k, _ in pairs(bindings) do table.insert(keys, k) end
	table.sort(keys)
	
	for _, k in ipairs(keys) do
		local v = bindings[k]
		
		-- Skip the debugger object itself, temporaries and Lua 5.2's _ENV object.
		if not rawequal(v, dbg) and k ~= "_ENV" and k ~= "(*temporary)" then
			dbg.writeln("\t"..COLOR_BLUE.."%s "..COLOR_RED.."=>"..COLOR_RESET.." %s", k, pretty(v, 0))
		end
	end
	
	return false
end

local last_cmd = false

local function match_command(line)
	local commands = {
		["c"] = function() return true end,
		["s"] = cmd_step,
		["n"] = cmd_next,
		["f"] = cmd_finish,
		["p (.*)"] = cmd_print,
		["e (.*)"] = cmd_eval,
		["u"] = cmd_up,
		["d"] = cmd_down,
		["t"] = cmd_trace,
		["l"] = cmd_locals,
		["h"] = function() dbg.writeln(help_message); return false end,
		["q"] = function() os.exit(0) end,
	}
	
	for cmd, cmd_func in pairs(commands) do
		local matches = {string.match(line, "^("..cmd..")$")}
		if matches[1] then
			return cmd_func, select(2, unpack(matches))
		end
	end
end

-- Try loading a chunk with a leading return.
local function is_expression(block)
	if _VERSION <= "Lua 5.1" then
		return loadstring("return "..block, "") ~= nil
	end
	return load("return "..block, "", "t") ~= nil
end

-- Run a command line
-- Returns true if the REPL should exit and the hook function factory
local function run_command(line)
	-- Continue without caching the command if you hit control-d.
	if line == nil then
		dbg.writeln()
		return true
	end

	-- Re-execute the last command if you press return.
	if line == "" then
		line = last_cmd or "h"
	end

	local command, command_arg = match_command(line)
	if command then
		-- Some commands are not worth repeating.
		if not line:match("^[hlt]$") then
			last_cmd = line
		end
		-- unpack({...}) prevents tail call elimination so the stack frame indices are predictable.
		return unpack({command(command_arg)})
	end

	if #line == 1 then
		dbg.writeln(COLOR_RED.."Error:"..COLOR_RESET.." command '%s' not recognized.\nType 'h' and press return for a command list.", line)
		return false
	end

	-- Evaluate the chunk appropriately.
	if is_expression(line) then cmd_print(line) else cmd_eval(line) end
end

repl = function()
	dbg.writeln(format_stack_frame_info(debug.getinfo(LOCAL_STACK_LEVEL - 3 + stack_top)))
	
	repeat
		local success, done, hook = pcall(run_command, dbg.read(COLOR_RED.."debugger.lua> "..COLOR_RESET))
		if success then
			debug.sethook(hook and hook(0), "crl")
		else
			local message = string.format(COLOR_RED.."INTERNAL DEBUGGER.LUA ERROR. ABORTING\n:"..COLOR_RESET.." %s", done)
			dbg.writeln(message)
			error(message)
		end
	until done
end

-- Make the debugger object callable like a function.
dbg = setmetatable({}, {
	__call = function(self, condition, offset)
		if condition then return end
		
		offset = (offset or 0)
		stack_offset = offset
		stack_top = offset
		
		debug.sethook(hook_next(1), "crl")
		return
	end,
})

-- Expose the debugger's IO functions.
dbg.read = dbg_read
dbg.write = dbg_write
dbg.writeln = dbg_writeln
dbg.pretty = pretty

-- Works like error(), but invokes the debugger.
function dbg.error(err, level)
	level = level or 1
	dbg.writeln(COLOR_RED.."Debugger stopped on error:"..COLOR_RESET.."(%s)", pretty(err))
	dbg(false, level)
	
	error(err, level)
end

-- Works like assert(), but invokes the debugger on a failure.
function dbg.assert(condition, message)
	if not condition then
		dbg.writeln(COLOR_RED.."Debugger stopped on "..COLOR_RESET.."assert(..., %s)", message)
		dbg(false, 1)
	end
	
	assert(condition, message)
end

-- Works like pcall(), but invokes the debugger on an error.
function dbg.call(f, ...)
	local catch = function(err)
		dbg.writeln(COLOR_RED.."Debugger stopped on error: "..COLOR_RESET..pretty(err))
		dbg(false, 2)

		return err
	end
	if select('#', ...) > 0 then
		local args = {...}
		return xpcall(function()
			return f(unpack(args))
		end, catch)
	end
	return xpcall(f, catch)
end

-- Error message handler that can be used with lua_pcall().
function dbg.msgh(...)
	dbg.write(...)
	dbg(false, 1)
	
	return ...
end

-- Detect Lua version.
if jit then -- LuaJIT
	dbg.writeln(COLOR_RED.."debugger.lua: Loaded for "..jit.version..COLOR_RESET)
elseif "Lua 5.1" <= _VERSION and _VERSION <= "Lua 5.3" then
	dbg.writeln(COLOR_RED.."debugger.lua: Loaded for ".._VERSION..COLOR_RESET)
else
	dbg.writeln(COLOR_RED.."debugger.lua: Not tested against ".._VERSION..COLOR_RESET)
	dbg.writeln(COLOR_RED.."Please send me feedback!"..COLOR_RESET)
end

-- Assume stdin/out are TTYs unless we can use LuaJIT's FFI to properly check them.
local stdin_isatty = true
local stdout_isatty = true

-- Conditionally enable the LuaJIT FFI.
local ffi = (jit and require("ffi"))
if ffi then
	ffi.cdef[[
		bool isatty(int);
		void free(void *ptr);
		
		char *readline(const char *);
		int add_history(const char *);
	]]
	
	stdin_isatty = ffi.C.isatty(0)
	stdout_isatty = ffi.C.isatty(1)
end

-- Conditionally enable color support.
local color_maybe_supported = (stdout_isatty and os.getenv("TERM") and os.getenv("TERM") ~= "dumb")
if color_maybe_supported and not os.getenv("DBG_NOCOLOR") then
	COLOR_RED = string.char(27) .. "[31m"
	COLOR_BLUE = string.char(27) .. "[34m"
	COLOR_GRAY = string.char(27) .. "[38;5;59m"
	COLOR_RESET = string.char(27) .. "[0m"
end

if stdin_isatty and not os.getenv("DBG_NOREADLINE") then
	pcall(function()
		local linenoise = require 'linenoise'

		-- Load command history from ~/.lua_history
		local hist_path = os.getenv('HOME') .. '/.lua_history'
		linenoise.historyload(hist_path)
		linenoise.historysetmaxlen(50)

		local function autocomplete(env, input, matches)
			for name, _ in pairs(env) do
				if name:match('^' .. input .. '.*') then
					linenoise.addcompletion(matches, name)
				end
			end
		end

		-- Auto-completion for locals and globals
		linenoise.setcompletion(function(matches, input)
			-- First, check the locals and upvalues.
			local env = local_bindings(1, true)
			autocomplete(env, input, matches)

			-- Then, check the implicit environment.
			env = getmetatable(env).__index
			autocomplete(env, input, matches)
		end)

		dbg.read = function(prompt)
			local str = linenoise.linenoise(prompt)
			if str and not str:match "^%s*$" then
				linenoise.historyadd(str)
				linenoise.historysave(hist_path)
			end
			return str
		end
		dbg.writeln(COLOR_RED.."debugger.lua: Linenoise support enabled."..COLOR_RESET)
	end)

	-- Conditionally enable LuaJIT readline support.
	pcall(function()
		if dbg.read == nil and ffi then
			local readline = ffi.load("readline")
			dbg.read = function(prompt)
				local cstr = readline.readline(prompt)
				if cstr ~= nil then
					local str = ffi.string(cstr)
					if string.match(str, "[^%s]+") then
						readline.add_history(cstr)
					end

					ffi.C.free(cstr)
					return str
				else
					return nil
				end
			end
			dbg.writeln(COLOR_RED.."debugger.lua: Readline support enabled."..COLOR_RESET)
		end
	end)
end



-- END DEBUGGER

math.randomseed(os.time())
local mod_storage = minetest.get_mod_storage()
local stats

-- constants definition
local herbivore_initial_energy = 500
local herbivore_passive_energy_consumption = 0.001
local herbivore_walking_energy_consumption = 0.4
local herbivore_jumping_energy_consumption = 3
local herbivore_speed = 5

local carnivore_initial_energy = 600
local carnivore_passive_energy_consumption = 0.01
local carnivore_walking_energy_consumption = 0.5
local carnivore_jumping_energy_consumption = 3
local carnivore_speed = 4.8

local plants_count_cap = 10000
local plants_spread_interval = 3
local plants_spread_chance = 100

local energy_in_plant = 500
local energy_in_herbivore = 800

local herbivore_view_distance = 15
local carnivore_view_distance = 10

local herbivore_force_hunt_threshold = 400
local herbivore_force_mate_threshold = 700

local carnivore_force_hunt_threshold = 600
local carnivore_force_mate_threshold = 1000

local not_moving_threshold = 2
local not_moving_tick_threshold = 200

local initial_plants_count = 400
local initial_herbivores_count = 10
local initial_carnivores_count = 10


-- debugging overrides
-- initial_plants_count = 1
-- initial_herbivores_count = 0
-- initial_carnivores_count = 0
--herbivore_speed = 0
--carnivore_speed = 0

-- initial_plants_count = 600
-- initial_herbivores_count = 20
-- 
-- herbivore_walking_energy_consumption = 0.3
-- herbivore_jumping_energy_consumption = 2
-- herbivore_speed = 6
-- energy_in_plant = 800
-- energy_in_herbivore = 500
-- 
-- 
-- carnivore_speed = 4.5



function init()
  -- local tmpStats = minetest.deserialize(mod_storage:get_string("stats"))
  -- if tmpStats == nil then
  --   tmpStats = {
  --     plants_count = 0,
  --     carnivores_count = 0,
  --     herbivores_count = 0,
  --   }
  -- else
  --   if tmpStats["plants_count"] == nil then tmpStats["plants_count"] = 0 end
  --   if tmpStats["carnivores_count"] == nil then tmpStats["carnivores_count"] = 0 end
  --   if tmpStats["herbivores_count"] == nil then tmpStats["herbiivores_count"] = 0 end
  -- end
  local tmpStats = {
    herbivores_count = 0,
    carnivores_count = 0,
  }

  local pc = mod_storage:get_int("plants_count")
  if pc == nil then pc = 0 end
  tmpStats["plants_count"] = pc

  stats = tmpStats
end

init()


local file = io.open(os.time() .. "_stats", "w")
file:write("#time plants herbivores carnivores")

local time_index = 0

function stats_write()
  time_index = time_index + 1
  file:write(time_index .. " " .. stats["plants_count"] .. " " .. stats["herbivores_count"] .. " " .. stats["carnivores_count"] .. "\n")
  file:flush()
  minetest.after(1.0, stats_write)
end

minetest.after(1.0, stats_write)

local first_gen = mod_storage:get_int("agents_spawned")

local map_top = 45

local gen_min = -30
local gen_max = 45

if first_gen ~= 1 then
  minetest.after(5.0, function()
    print('creating plants')
    local plants_generated = 0
    while plants_generated < initial_plants_count do
      local x = (math.floor(math.random() * 100000) % (gen_max - gen_min)) + gen_min
      local z = (math.floor(math.random() * 100000) % (gen_max - gen_min)) + gen_min

      local pos = {x = x, y = map_top, z = z}

      minetest.set_node(pos, {name = "alsim:plant"})
      minetest.check_for_falling(pos)

      plants_generated = plants_generated + 1
    end

    minetest.after(3.0, function()
      print('creating agents')
      local herbivores_generated = 0
      while herbivores_generated < initial_herbivores_count do
        local x = (math.floor(math.random() * 100000) % (gen_max - gen_min)) + gen_min
        local z = (math.floor(math.random() * 100000) % (gen_max - gen_min)) + gen_min

        local pos = {x = x, y = map_top, z = z}

        minetest.add_entity(pos, "alsim:herbivore")

        herbivores_generated = herbivores_generated + 1
      end

      minetest.after(3.0, function()
        print('creating carnivores')
        local carnivores_generated = 0
        while carnivores_generated < initial_carnivores_count do
          local x = (math.floor(math.random() * 100000) % (gen_max - gen_min)) + gen_min
          local z = (math.floor(math.random() * 100000) % (gen_max - gen_min)) + gen_min

          local pos = {x = x, y = map_top, z = z}

          minetest.add_entity(pos, "alsim:carnivore")

          carnivores_generated = carnivores_generated + 1
        end
      end)
    end)
  end)
end

mod_storage:set_int("agents_spawned", 1)

local player
local huds = {}

minetest.register_on_joinplayer(function(the_player)
  player = the_player

  local privs = minetest.get_player_privs(player:get_player_name())
  privs["fly"] = true
  privs["noclip"] = true
  privs["give"] = true
  privs["fast"] = true
  minetest.set_player_privs(player:get_player_name(), privs)

  local stats_hud_title = player:hud_add({
    hud_elem_type = "text",
    position      = {x = 1,    y = 0.05},
    offset        = {x = -100, y = 0},
    alignment     = {x = 0,    y = 0},
    scale         = {x = 100,  y = 100},
    number        = 0xFFFFFF,
    text          = "Stats",
  })

  local stats_hud_plants = player:hud_add({
    hud_elem_type = "text",
    position      = {x = 1,    y = 0.05},
    offset        = {x = -150, y = 20},
    alignment     = -1,
    scale         = {x = 100,  y = 100},
    number        = 0xFFFFFF,
    text          = "Plants: "..stats["plants_count"],
  })
  huds["plants_count"] = stats_hud_plants

  local stats_hud_herbivores = player:hud_add({
    hud_elem_type = "text",
    position      = {x = 1,    y = 0.05},
    offset        = {x = -150, y = 40},
    alignment     = -1,
    scale         = {x = 100,  y = 100},
    number        = 0xFFFFFF,
    text          = "Herbivores: "..stats["herbivores_count"],
  })
  huds["herbivores_count"] = stats_hud_herbivores

  local stats_hud_carnivores = player:hud_add({
    hud_elem_type = "text",
    position      = {x = 1,    y = 0.05},
    offset        = {x = -150, y = 60},
    alignment     = -1,
    scale         = {x = 100,  y = 100},
    number        = 0xFFFFFF,
    text          = "Carnivores: "..stats["carnivores_count"],
  })
  huds["carnivores_count"] = stats_hud_carnivores
end)

function update_hud(player)
  if huds["plants_count"] ~= nil then
    player:hud_change(huds["plants_count"], "text", "Plants: "..stats["plants_count"])
  end

  if huds["herbivores_count"] ~= nil then
    player:hud_change(huds["herbivores_count"], "text", "Herbivores: "..stats["herbivores_count"])
  end

  if huds["carnivores_count"] ~= nil then
    player:hud_change(huds["carnivores_count"], "text", "Carnivores: "..stats["carnivores_count"])
  end
end

function stats_update(what, change)
  if stats[what] == nil then stats[what] = 0 end

  stats[what] = stats[what] + change

  -- only plants count should be saved as other types (herbivores and carnivores)
  -- are (re)counted on initialization
  if what == "plants_count" then
    mod_storage:set_int("plants_count", stats[what])
  end

  update_hud(player)
  print(minetest.write_json(stats))
end

minetest.register_chatcommand("get_stats", {
  func = function(name, param)
    for ent,count in pairs(stats) do
      print("stats for "..ent..": "..count)
    end
  end
})

minetest.register_node("alsim:plant", {
  tiles = {"alsim_plant.png"},
  groups = {snappy=1,choppy=2,flammable=3,falling_node=1,oddly_breakable_by_hand=3},
  on_construct = function(pos)
    stats_update("plants_count", 1)
  end,
  on_destruct = function(pos)
    stats_update("plants_count", -1)
  end,
})

-- minetest.register_ore({
-- 	ore_type       = "scatter",
-- 	ore            = "alsim:plant",
-- 	wherein        = "default:dirt_with_grass",
-- 	clust_scarcity = 10 * 10 * 20,
-- 	clust_num_ores = 8,
-- 	clust_size     = 3,
-- 	y_min          = -31000,
-- 	y_max          = 31000,
-- })

minetest.register_abm({
  name = "alsim_plant_reproduction",
  nodenames = {"alsim:plant"},
  interval = plants_spread_interval,
  chance = plants_spread_chance,
  action = function(pos, node, active_object_count, active_object_count_wider)
    -- check if plants count cap has been reached
    if plants_count_cap ~= 0 and stats.plants_count >= plants_count_cap then
      return
    end
    -- x offset
    pos.x = pos.x + (math.floor(math.random() * 100) % 11) - 5
    -- y offset
    pos.z = pos.z + (math.floor(math.random() * 100) % 11) - 5

    -- only spawn new plants if there is nothing else there
    local new_node
    local i = 0
    local max_height_diff = 4
    while true do
      if i >= max_height_diff then
        return
      end

      new_node = minetest.get_node_or_nil(pos)
      if new_node == nil then
        break
      elseif new_node.name ~= "air" then
        pos.y = pos.y + 1
      else
        break
      end

      i = i + 1
    end

    minetest.set_node(pos, {name = "alsim:plant"})
    minetest.check_for_falling(pos)
  end
})

function pick_random_target(pos, max_distance, max_y_distance) -- 1/2 Manhattan distance
  local new_pos = {x = pos.x, y = pos.y, z = pos.z}

  -- only choose target not higher/lower than max_y_distance
  local target_node
  local max_iter = 10
  local current_iter = 0
  while true do
    if current_iter >= max_iter then
      print('target not found. returning nil')
      return nil
    end

    new_pos.x = pos.x + (math.random(-max_distance, max_distance))
    new_pos.z = pos.z + (math.random(-max_distance, max_distance))

    local i = -max_y_distance
    while true do
      if i > max_y_distance then
        break
      end

      target_node = minetest.get_node_or_nil(new_pos)
      if target_node == nil then
        break
      elseif target_node.name ~= "air" then
        new_pos.y = new_pos.y + 1
      else
        return new_pos
      end

      i = i + 1
    end
    current_iter = current_iter + 1
  end
end

function atan2(x, y)
  if x > 0 then
    return math.atan(y/x)
  elseif x < 0 and y >= 0 then
    return math.atan(y/x) + math.pi
  elseif x < 0 and y < 0 then
    return math.atan(y/x) - math.pi
  elseif x == 0 and y > 0 then
    return math.pi/2
  elseif x == 0 and y < 0 then
    return -math.pi/2
  else
    return 0
  end
end

function find_nodes_around(pos, distance, nodenames)
  local minp = {
    x = pos.x - distance,
    y = pos.y - distance,
    z = pos.z - distance,
  }

  local maxp = {
    x = pos.x + distance,
    y = pos.y + distance,
    z = pos.z + distance,
  }

  return minetest.find_nodes_in_area(minp, maxp, nodenames)
end

minetest.register_entity("alsim:herbivore", {
  textures = {"alsim_herbivore.png", "alsim_herbivore.png", "alsim_herbivore.png", "alsim_herbivore.png", "alsim_herbivore.png", "alsim_herbivore_front.png"},
  visual = "cube",
  collisionbox = {-0.499, -0.499, -0.499, 0.499, 0.499, 0.499, 0.499},
  physical = true,
  automatic_rotation = 0.1,
  automatic_face_movement_dir = 0.0,

  -- New entities will have energy 500. Maximum is 1000, and when
  -- 0 is reached, they die.
  energy = herbivore_initial_energy,

  _counted = false,
  previous_pos = nil,
  on_activate = function(self, staticdata)
    self.previous_pos = self.object:getpos()
    if not self._counted then
      stats_update("herbivores_count", 1)
      self._counted = true
    end

    self.object:setacceleration({x = 0, y = -10, z = 0})
  end,
  on_death = function(self)
    stats_update("herbivores_count", -1)
    self.dead = true
    if self.target_mate ~= nil then
      self.target_mate.target_mate = nil
      self.target_mate = nil
    end
  end,

  not_moving_tick_count = 0,
  dead = false,
  state = "stand",
  target = nil,
  hunt_target = nil,
  path = nil,
  target_mate = nil,
  force_wander = 0,

  set_target = function(self, target)
    -- dbg(self.path == nil)
    if target ~= nil then
      self.target = target
    else
      self.target = nil
      self.hunt_target = nil
      self.path = nil
    end
  end,

  set_hunt_target = function(self, target)
    self.hunt_target = target
    self:set_target(target)
  end,

  pick_hunt_target = function(self)
    local huntable = find_nodes_around(self.object:getpos(), herbivore_view_distance, {"alsim:plant"})
    if table.getn(huntable) == 0 then
      if self.target == nil then
        self:set_target(pick_random_target(self.object:getpos(), herbivore_view_distance, 5))
      end
      self.force_wander = 100
      return nil
    else
      local selfpos = self.object:getpos()
      for _, pos in pairs(huntable) do
        local direct, blocking = minetest.line_of_sight(selfpos, pos, 1)

        if direct or blocking.x == pos.x and blocking.y == pos.y and blocking.z == pos.z then
          if math.random() < 0.2 then
            self:set_hunt_target(pos)
            break
          end
        end
      end
    end

    return self.target
  end,

  jump = function(self)
    local sp = self.object:getpos()
    if not self.is_blocking({x = sp.x, y = sp.y - 1, z = sp.z}) then
      return
    end

    local v = self.object:getvelocity()
    v.y = 5
    self.object:setvelocity(v)
    self.energy = self.energy - herbivore_jumping_energy_consumption
  end,

  on_step = function(self, dtime)
    self.energy = self.energy - herbivore_passive_energy_consumption
    self.object:setacceleration({x = 0, y = -10, z = 0})

    local rn = math.random(1, 1000)

    if self.state == "stand" then
    elseif self.state == "wander" or self.state == "hunt" and self.hunt_target == nil then
      if self.target ~= nil then
        if self:target_reached() then
          self.state = "stand"
          self:set_target(nil)
        else
          self:advance_towards_target()
        end
      end
    elseif self.state == "eat" then
      if self.hunt_target ~= nil then
        local target_node = minetest.get_node_or_nil(self.hunt_target)
        if target_node ~= nil and target_node.name == "alsim:plant"then
          -- minetest.dig_node(self.hunt_target)
          minetest.remove_node(self.hunt_target)
          self.energy = self.energy + energy_in_plant
          self:go_to_state("wander")
        end
      end
    elseif self.state == "hunt" then
      --print("hunting")
      self:advance_towards_target()
    elseif self.state == "find_mate" then
      self:advance_towards_target()
    elseif self.state == "mate" then
      if self:target_reached() then
        self:stop()

        -- some energy is lost in reproduction
        local child_energy = (self.energy + self.target_mate.energy) / 3.0
        self.energy = self.energy / 3.0
        self.target_mate.energy = self.target_mate.energy / 3.0

        local pos = self.object:getpos()
        pos.y = pos.y + 1
        local child = minetest.add_entity(pos, self.name)
        if child ~= nil then
          child = child:get_luaentity()
          child.energy = child_energy
        end
        self.target_mate:go_to_state("wander")
        self:go_to_state("wander")
      end
    elseif self.state == "mate_passive" then
      self:stop()
    end

    if self.energy <= 0 then
      self:die()
    end

    local current_pos = self.object:getpos()

    if math.abs(vector.distance(self.previous_pos, current_pos)) < not_moving_threshold then
      self.not_moving_tick_count = self.not_moving_tick_count + 1
    else
      self.not_moving_tick_count = 0
    end

    self.previous_pos = current_pos


    self:decide_next_action()
  end,

  decide_next_action = function(self)
    if self.not_moving_tick_count > not_moving_tick_threshold then
      self.force_wander = 30
      self.not_moving_tick_count = 0
      self:set_target(nil)
      self:jump()
    end

    --print("energy: "..self.energy)
    if self.force_wander > 0 then
      self.force_wander = self.force_wander - 1
      self:go_to_state("wander")
    elseif self.state == "hunt" and self:target_reached() then
      self:go_to_state("eat")
    elseif self.state == "eat" and self.hunt_target == nil then
      -- how did this happen
      self:go_to_state("hunt")
    elseif self.energy <= 400 then
      self:go_to_state("hunt")
    elseif self.state == "hunt" and self.energy < 8000 then
      self:go_to_state("hunt")
    elseif self.energy > herbivore_force_mate_threshold  then
      self:go_to_state("find_mate")
    elseif self.state == "find_mate" and (self.target_mate == nil or self.target_mate.dead)  then
      self.target_mate = nil
      self:go_to_state("wander")
    elseif self.state == "find_mate" and self:target_reached() then
      self:go_to_state("mate")
    elseif self.state ~= "wander" then
      self:go_to_state("wander")
    end
  end,

  target_reached = function(self, tolerance)
    if tolerance == nil then
      tolerance = 1.0
    end

    local local_target = self.target
    if self.target_mate ~= nil then
      local_target = self.target_mate.object:getpos()
    end

    if local_target == nil then
      return false
    end

    local dist = vector.distance(self.object:getpos(), local_target)
    return dist < (tolerance + 1)
  end,

  find_mate = function(self)
    if self.target_mate == nil then
      local objects = minetest.get_objects_inside_radius(self.object:getpos(), 50)
      local selected
      local _, obj
      for _, obj in ipairs(objects) do
        if obj ~= nil then
          local current = obj:get_luaentity()
          if current ~= nil and current ~= self and current.name == self.name then
            selected = current
            self.target_mate = selected

            if selected:receive_mate_call(self) then
              return true
            end
          end
        end
      end
    else
      return true
    end

    return false
  end,

  receive_mate_call = function(self, other)
    -- print('Received mate call from '..pretty(other))
    if self.state == "wander" or (self.state == "find_mate" and (self.target_mate == nil or self.target_mate == other)) then
      self.target_mate = other
      self:go_to_state('find_mate')
      return true
    end

    return false
  end,

  go_to_state = function(self, target_state)
    if target_state ~= 'wander' then
      self.force_wander = 0
    end

    if target_state == "hunt" then
      -- check if the target somehow got removed (eaten)
      local target_node = nil
      --print('hunt target: '..pretty(self.hunt_target))
      if self.hunt_target ~= nil then
        target_node = minetest.get_node_or_nil(self.hunt_target)
        --dbg()
      end

      -- if needed, pick a new hunt target
      if self.state ~= "hunt" or target_node == nil or target_node.name ~= "alsim:plant" then
        if self:pick_hunt_target() == nil then
          -- no huntables found, wander
          self:go_to_state("wander")
        else
          self.state = "hunt"
        end
      end
    elseif target_state == "wander" and (self.state ~= "wander" or self.target == nil) then
      self:set_target(pick_random_target(self.object:getpos(), herbivore_view_distance, 5))
      if self.target_mate ~= nil then
        self.target_mate.target_mate = nil
        self.target_mate = nil
      end
      self.state = "wander"
    elseif target_state == "eat" then
      if self.state ~= "eat" then
        self.state = "eat"
      end
    elseif target_state == "find_mate" then
      if not self:find_mate() then
        -- print('unable to find mate. wandering for a bit...')
        -- self.force_wander = 20
        self.state = "hunt"
      else
        self.state = "find_mate"
        self:set_target(nil)
      end
    elseif target_state == "mate" then
      if self.target_mate ~= nil then
        self.state = "mate"
        self.target_mate:go_to_state("mate_passive")
      end
    elseif target_state == "mate_passive" then
      self.state = "mate_passive"
    end
  end,

  stop = function(self)
    self.object:setvelocity({x = 0, y = self.object:getvelocity().y, z = 0})
  end,

  is_blocking = function(pos)
    local n = minetest.get_node_or_nil(pos)
    if n ~= nil and n.name ~= "air" then
      return true
    end
    return false
  end,

  advance_towards_target = function(self)
    local local_target = self.target
    if self.target_mate ~= nil then
      local_target = self.target_mate.object:getpos()
    end

    if local_target == nil then
      return
    end
    local sp = self.object:getpos()
    local vec = {x=local_target.x-sp.x, y=local_target.y-sp.y, z=local_target.z-sp.z}
    local yaw = atan2(vec.x, vec.z) + math.pi/2

    self.object:setyaw(yaw)


    if   self.is_blocking({x = sp.x - 1, y = sp.y, z = sp.z})
      or self.is_blocking({x = sp.x - 1, y = sp.y, z = sp.z - 1})
      or self.is_blocking({x = sp.x - 1, y = sp.y, z = sp.z + 1})
      or self.is_blocking({x = sp.x, y = sp.y, z = sp.z - 1})
      or self.is_blocking({x = sp.x, y = sp.y, z = sp.z + 1})
      or self.is_blocking({x = sp.x + 1, y = sp.y, z = sp.z})
      or self.is_blocking({x = sp.x + 1, y = sp.y, z = sp.z - 1})
      or self.is_blocking({x = sp.x + 1, y = sp.y, z = sp.z + 1}) then
      self:jump()
    end

    local x = math.sin(yaw) * herbivore_speed
    local z = math.cos(yaw) * -herbivore_speed
    self.object:setvelocity({x = x, y = self.object:getvelocity().y, z = z})

    -- if vec.y > 0.5 then
    --   self:jump()
    -- end

    self.energy = self.energy - herbivore_walking_energy_consumption
  end,

  die = function(self)
    self:on_death()
    self.object:remove()
  end,

  on_punch = function(self)
    minetest.chat_send_all(pretty(self))
    print(pretty(self))
  end,

  on_rightclick = function(self)
    minetest.chat_send_all(pretty(self))
    print(pretty(self))
    dbg()
  end
})

minetest.register_entity("alsim:carnivore", {
  textures = {"alsim_carnivore.png", "alsim_carnivore.png", "alsim_carnivore.png", "alsim_carnivore.png", "alsim_carnivore.png", "alsim_carnivore_front.png"},
  visual = "cube",
  collisionbox = {-0.499, -0.499, -0.499, 0.499, 0.499, 0.499, 0.499},
  physical = true,
  automatic_rotation = 0.1,
  automatic_face_movement_dir = 0.0,

  energy = carnivore_initial_energy,

  _counted = false,
  previous_pos = nil,
  on_activate = function(self, staticdata)
    self.previous_pos = self.object:getpos()
    if not self._counted then
      stats_update("carnivores_count", 1)
      self._counted = true
    end

    self.object:setacceleration({x = 0, y = -10, z = 0})
  end,
  on_death = function(self)
    stats_update("carnivores_count", -1)
    self.dead = true
    if self.target_mate ~= nil then
      self.target_mate.target_mate = nil
      self.target_mate = nil
    end
  end,

  not_moving_tick_count = 0,
  dead = false,
  state = "stand",
  target = nil,
  target_hunt = nil,
  path = nil,
  target_mate = nil,
  force_wander = 0,

  set_target = function(self, target)
    -- dbg(self.path == nil)
    if target ~= nil then
      self.target = target
    else
      self.target = nil
      self.target_hunt = nil
    end
  end,

  set_hunt_target = function(self, target)
    self.target_hunt = target
    self:set_target(target)
  end,

  pick_hunt_target = function(self)
    if self.target_hunt == nil then
      local objects = minetest.get_objects_inside_radius(self.object:getpos(), carnivore_view_distance)
      local _, obj
      for _, obj in ipairs(objects) do
        if obj ~= nil then
          local current = obj:get_luaentity()
          if current ~= nil and current.name == "alsim:herbivore" then
            if math.random() < 0.2 then
              self.target_hunt = current
              return true
            end
          end
        end
      end
    else
      return true
    end

    return false
  end,

  jump = function(self)
    local sp = self.object:getpos()
    if not self.is_blocking({x = sp.x, y = sp.y - 1, z = sp.z}) then
      return
    end

    local v = self.object:getvelocity()
    v.y = 5
    self.object:setvelocity(v)
    self.energy = self.energy - carnivore_jumping_energy_consumption
  end,

  eat = function(self, target)
    if target == nil or target.dead then
    else
      target:die()
      self.energy = self.energy + energy_in_herbivore
    end
  end,

  on_step = function(self, dtime)
    self.energy = self.energy - carnivore_passive_energy_consumption
    self.object:setacceleration({x = 0, y = -10, z = 0})

    local rn = math.random(1, 1000)

    if self.state == "stand" and rn < 300 then
      self:go_to_state("wander")
    elseif self.state == "wander" or self.state == "hunt" and self.target_hunt == nil then
      if self.target ~= nil then
        if self:target_reached() then
          self.state = "stand"
          self:set_target(nil)
        else
          self:advance_towards_target()
        end
      end
    elseif self.state == "eat" then
      if self.target_hunt ~= nil then
        self:eat(self.target_hunt)
        self.target_hunt = nil
        self:go_to_state("wander")
      end
    elseif self.state == "hunt" then
      --print("hunting")
      self:advance_towards_target()
    elseif self.state == "find_mate" then
      self:advance_towards_target()
    elseif self.state == "mate" then
      if self:target_reached() then
        self:stop()

        -- some energy is lost in reproduction
        local child_energy = (self.energy + self.target_mate.energy) / 3.0
        self.energy = self.energy / 3.0
        self.target_mate.energy = self.target_mate.energy / 3.0

        local pos = self.object:getpos()
        pos.y = pos.y + 1
        local child = minetest.add_entity(pos, self.name)
        if child ~= nil then
          child = child:get_luaentity()
          child.energy = child_energy
        end
        self.target_mate:go_to_state("wander")
        self:go_to_state("wander")
      end
    elseif self.state == "mate_passive" then
      self:stop()
    end

    if self.energy <= 0 then
      self:die()
    end

    local current_pos = self.object:getpos()

    if math.abs(vector.distance(self.previous_pos, current_pos)) < not_moving_threshold then
      self.not_moving_tick_count = self.not_moving_tick_count + 1
    else
      self.not_moving_tick_count = 0
    end

    self.previous_pos = current_pos


    self:decide_next_action()
  end,

  decide_next_action = function(self)
    if self.not_moving_tick_count > not_moving_tick_threshold then
      self.force_wander = 30
      self.not_moving_tick_count = 0
      self:jump()
      self:set_target(nil)
    end

    if self.target_hunt ~= nil and self.target_hunt.dead then
      self.target_hunt = nil
    end

    if self.target_mate ~= nil and self.target_mate.dead then
      self.target_mate = nil
    end

    -- if target is far away, pick a a new one
    -- local td = self:target_distance()
    -- if td ~= nil and td > carnivore_view_distance * 1.5 then
    --   self:set_target(nil)
    --   self.target_hunt = nil
    -- end

    if self.force_wander > 0 then
      self.force_wander = self.force_wander - 1
      self:go_to_state("wander")
    elseif self.state == "hunt" and self:target_reached() then
      self:go_to_state("eat")
    elseif self.state == "eat" and self.target_hunt == nil then
      self:go_to_state("hunt")
    elseif self.energy <= 400 then
      self:go_to_state("hunt")
    elseif self.state == "hunt" and self.energy < 8000 then
      self:go_to_state("hunt")
    elseif self.energy > carnivore_force_mate_threshold  then
      self:go_to_state("find_mate")
    elseif self.state == "find_mate" and self.target_mate == nil then
      self:go_to_state("wander")
    elseif self.state == "find_mate" and self:target_reached() then
      self:go_to_state("mate")
    elseif self.state ~= "wander" then
      self:go_to_state("wander")
    end
  end,

  target_distance = function(self)
    local local_target = self.target
    if self.target_mate ~= nil then
      local_target = self.target_mate.object:getpos()
    end

    if self.target_hunt ~= nil then
      local_target = self.target_hunt.object:getpos()
    end

    if local_target == nil then
      return nil
    end

    return vector.distance(self.object:getpos(), local_target)
  end,

  target_reached = function(self, tolerance)
    if tolerance == nil then
      tolerance = 1.0
    end

    local dist = self:target_distance()
    if dist == nil then
      return false
    end

    return dist < (tolerance + 1)
  end,

  find_mate = function(self)
    if self.target_mate == nil then
      local objects = minetest.get_objects_inside_radius(self.object:getpos(), 50)
      local selected
      local _, obj
      for _, obj in ipairs(objects) do
        if obj ~= nil then
          local current = obj:get_luaentity()
          if current ~= nil and current ~= self and current.name == self.name then
            selected = current
            self.target_mate = selected

            if selected:receive_mate_call(self) then
              return true
            end
          end
        end
      end
    else
      return true
    end

    return false
  end,

  receive_mate_call = function(self, other)
    -- print('Received mate call from '..pretty(other))
    if self.state == "wander" or (self.state == "find_mate" and (self.target_mate == nil or self.target_mate == other)) then
      self.target_mate = other
      self:go_to_state('find_mate')
      return true
    end

    return false
  end,

  go_to_state = function(self, target_state)
    if target_state ~= 'wander' then
      self.force_wander = 0
    end

    if target_state == "hunt" then
      -- check if the target somehow got removed (eaten)

      -- if needed, pick a new hunt target
      if self.state ~= "hunt" or self.target_hunt == nil or self.target_hunt.dead then
        if self:pick_hunt_target() then
          self.state = "hunt"
        else
          -- no huntables found, wander
          self:go_to_state("wander")
        end
      end
    elseif target_state == "wander" and (self.state ~= "wander" or self.target == nil) then
      self:set_target(pick_random_target(self.object:getpos(), carnivore_view_distance, 5))
      if self.target_mate ~= nil then
        self.target_mate.target_mate = nil
        self.target_mate = nil
      end
      self.state = "wander"
    elseif target_state == "eat" then
      if self.state ~= "eat" then
        self.state = "eat"
      end
    elseif target_state == "find_mate" then
      if not self:find_mate() then
        -- print('unable to find mate. wandering for a bit...')
        -- self.force_wander = 20
        self.state = "hunt"
      else
        self.state = "find_mate"
        self:set_target(nil)
      end
    elseif target_state == "mate" then
      if self.target_mate ~= nil then
        self.state = "mate"
        self.target_mate:go_to_state("mate_passive")
      end
    elseif target_state == "mate_passive" then
      self.state = "mate_passive"
    end
  end,

  stop = function(self)
    self.object:setvelocity({x = 0, y = self.object:getvelocity().y, z = 0})
  end,

  is_blocking = function(pos)
    local n = minetest.get_node_or_nil(pos)
    if n ~= nil and n.name ~= "air" then
      return true
    end
    return false
  end,

  advance_towards_target = function(self)
    local local_target = self.target
    if self.target_mate ~= nil then
      local_target = self.target_mate.object:getpos()
    end

    if self.target_hunt ~= nil then
      local_target = self.target_hunt.object:getpos()
    end

    if local_target == nil then
      return
    end
    local sp = self.object:getpos()
    local vec = {x=local_target.x-sp.x, y=local_target.y-sp.y, z=local_target.z-sp.z}
    local yaw = atan2(vec.x, vec.z) + math.pi/2

    self.object:setyaw(yaw)


    if   self.is_blocking({x = sp.x - 1, y = sp.y, z = sp.z})
      or self.is_blocking({x = sp.x - 1, y = sp.y, z = sp.z - 1})
      or self.is_blocking({x = sp.x - 1, y = sp.y, z = sp.z + 1})
      or self.is_blocking({x = sp.x, y = sp.y, z = sp.z - 1})
      or self.is_blocking({x = sp.x, y = sp.y, z = sp.z + 1})
      or self.is_blocking({x = sp.x + 1, y = sp.y, z = sp.z})
      or self.is_blocking({x = sp.x + 1, y = sp.y, z = sp.z - 1})
      or self.is_blocking({x = sp.x + 1, y = sp.y, z = sp.z + 1}) then
      self:jump()
    end

    local x = math.sin(yaw) *  carnivore_speed
    local z = math.cos(yaw) * -carnivore_speed
    self.object:setvelocity({x = x, y = self.object:getvelocity().y, z = z})

    self.energy = self.energy - carnivore_walking_energy_consumption
  end,

  die = function(self)
    self:on_death()
    self.object:remove()
  end,

  on_punch = function(self)
    minetest.chat_send_all(pretty(self))
    print(pretty(self))
  end,

  on_rightclick = function(self)
    minetest.chat_send_all(pretty(self))
    print(pretty(self))
    dbg()
  end
})

minetest.register_craftitem("alsim:herbivore", {
  description = "herbivore",
  inventory_image = "alsim_herbivore_front.png",
  on_place = function(itemstack, place, pointed_thing)
    minetest.env:add_entity(pointed_thing.above, "alsim:herbivore")
    return itemstack
  end,
})

minetest.register_craftitem("alsim:carnivore", {
  description = "carnivore",
  inventory_image = "alsim_carnivore_front.png",
  on_place = function(itemstack, place, pointed_thing)
    minetest.env:add_entity(pointed_thing.above, "alsim:carnivore")
    return itemstack
  end,
})
