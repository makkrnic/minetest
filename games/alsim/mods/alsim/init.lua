math.randomseed(os.time())
local mod_storage = minetest.get_mod_storage()
local stats

-- constants definition
local passive_energy_consumption = 0.001
local walking_energy_consumption = 0.4
local jumping_energy_consumption = 3
local herbivore_speed = 5

local carnivore_passive_energy_consumption = 0.1
local carnivore_walking_energy_consumption = 1
local carnivore_jumping_energy_consumption = 5
local carnivore_speed = 6

local plants_count_cap = 15000

local energy_in_plant = 500
local energy_in_herbivore = 800

local herbivore_view_distance = 10
local carnivore_view_distance = 10

local herbivore_force_hunt_threshold = 400
local herbivore_force_mate_threshold = 700

local carnivore_force_hunt_threshold = 400
local carnivore_force_mate_threshold = 700

local not_moving_threshold = 2
local not_moving_tick_threshold = 200

local initial_plants_count = 200
local initial_herbivores_count = 30
local initial_carnivores_count = 10


-- debugging overrides
-- initial_plants_count = 0
-- initial_herbivores_count = 0
-- initial_carnivores_count = 0

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


local file = io.open(os.time() .. "_stats.json", "w")
file:write("{")
minetest.register_on_shutdown(function()
  file:write("}")
end)

local time_index = 0

function stats_write()
  time_index = time_index + 1
  file:write(time_index .. ": " .. minetest.write_json(stats) .. ",\n")
  file:flush()
  minetest.after(1.0, stats_write)
end

minetest.after(1.0, stats_write)

local first_gen = mod_storage:get_int("agents_spawned")

local map_top = 45

local gen_min = -30
local gen_max = 45

if first_gen ~= 1 then
  minetest.after(3.0, function()
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
  interval = 10.0,
  chance = 10,
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
  local new_pos = pos
  new_pos.x = pos.x - max_distance + (2 * math.random(1, max_distance))
  new_pos.z = pos.z - max_distance + (2 * math.random(1, max_distance))

  -- only choose target not higher/lower than max_y_distance
  local target_node
  --while true do
    local i = -max_y_distance
    while true do
      if i > max_y_distance then
        break
      end

      target_node = minetest.get_node_or_nil(new_pos)
      if target_node == nil then
        return new_pos
      elseif target_node.name ~= "air" then
        new_pos.y = new_pos.y + 1
        return new_pos
      else
        break
      end

      i = i + 1
    end
  --end

  return new_pos
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
  energy = 400.0,

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
  path_step_index = 1,
  target_mate = nil,
  force_wander = 0,

  set_target = function(self, target)
    -- dbg(self.path == nil)
    if target ~= nil then
      -- if self.path == nil then
      --   local path = minetest.find_path(self.object:getpos(), target, 2 * herbivore_view_distance, 1, 1, 'A*')
      --   if path == nil then
      --     -- if we are trying to find a path towards a 'plant' node we must put the target one block above
      --     local alt_target = {x = target.x, y = target.y + 1, z = target.z}
      --     path = minetest.find_path(self.object:getpos(), alt_target, 2 * herbivore_view_distance, 1, 1, 'A*')
      --   end
      --   if path ~= nil then
          -- self.path = path
          self.target = target
      --     self.path_step_index = 1
      --   else
      --     -- target can't be reached
      --     self.target = nil
      --     self.hunt_target = nil
      --   end
      -- end
    else
      self.target = nil
      self.hunt_target = nil
      self.path = nil
      self.path_step_index = 1
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
        self:set_target(pick_random_target(self.object:getpos(), 20, 5))
      end
      self.force_wander = 100
      return nil
    else
      local selfpos = self.object:getpos()
      for _, pos in pairs(huntable) do
        local direct, blocking = minetest.line_of_sight(selfpos, pos, 1)

        if direct or blocking.x == pos.x and blocking.y == pos.y and blocking.z == pos.z then
          self:set_hunt_target(pos)
          break
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
    self.energy = self.energy - jumping_energy_consumption
  end,

  on_step = function(self, dtime)
    self.energy = self.energy - passive_energy_consumption
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

      self.energy = self.energy - walking_energy_consumption
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

    if self:step_reached() then
      self:advance_step()
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

  advance_step = function(self)
    if self.path ~= nil then
      local steps_count = table.getn(self.path)

      if self.path_step_index < steps_count then
        self.path_step_index = self.path_step_index + 1
      end
    end
  end,

  decide_next_action = function(self)
    if self.not_moving_tick_count > not_moving_tick_threshold then
      self.force_wander = 30
      self.not_moving_tick_count = 0
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

  step_reached = function(self, tolerance)
    -- default values
    if tolerance == nil then
      tolerance = 0.1
    end

    local local_target = self.target
    if self.path ~= nil then
      local_target = self.path[self.path_step_index]
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
    elseif target_state == "wander" and self.state ~= "wander" then
      self:set_target(pick_random_target(self.object:getpos(), 40, 5))
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
    if self.path ~= nil then
      local_target = self.path[self.path_step_index]
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

    local x = math.sin(yaw) * 5
    local z = math.cos(yaw) * -5
    self.object:setvelocity({x = x, y = self.object:getvelocity().y, z = z})

    -- if vec.y > 0.5 then
    --   self:jump()
    -- end

    self.energy = self.energy - walking_energy_consumption
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

  -- New entities will have energy 500. Maximum is 1000, and when
  -- 0 is reached, they die.
  energy = 800.0,

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
  path_step_index = 1,
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
      local objects = minetest.get_objects_inside_radius(self.object:getpos(), 50)
      local _, obj
      for _, obj in ipairs(objects) do
        if obj ~= nil then
          local current = obj:get_luaentity()
          if current ~= nil and current.name == "alsim:herbivore" then
            self.target_hunt = current
            return true
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

      self.energy = self.energy - carnivore_walking_energy_consumption
    elseif self.state == "eat" then
      if self.target_hunt ~= nil then
        -- minetest.dig_node(self.hunt_target)
        if self.target_hunt.dead then
          self.target_hunt = nil
        else
          self.target_hunt:die()
          self.energy = self.energy + energy_in_herbivore
        end
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

    if self:step_reached() then
      self:advance_step()
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

  advance_step = function(self)
    if self.path ~= nil then
      local steps_count = table.getn(self.path)

      if self.path_step_index < steps_count then
        self.path_step_index = self.path_step_index + 1
      end
    end
  end,

  decide_next_action = function(self)
    if self.not_moving_tick_count > not_moving_tick_threshold then
      self.force_wander = 30
      self.not_moving_tick_count = 0
    end

    if self.force_wander > 0 then
      self.force_wander = self.force_wander - 1
      self:go_to_state("wander")
    elseif self.state == "hunt" and self:target_reached() then
      self:go_to_state("eat")
    elseif self.state == "eat" and (self.target_hunt == nil or self.target_hunt.dead) then
      self.target_hunt = nil
      self:go_to_state("hunt")
    elseif self.energy <= 400 then
      self:go_to_state("hunt")
    elseif self.state == "hunt" and self.energy < 8000 then
      self:go_to_state("hunt")
    elseif self.energy > carnivore_force_mate_threshold  then
      self:go_to_state("find_mate")
    elseif self.state == "find_mate" and (self.target_mate == nil or self.target_mate.dead)  then
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

    if self.target_hunt ~= nil then
      local_target = self.target_hunt.object:getpos()
    end

    if local_target == nil then
      return false
    end

    local dist = vector.distance(self.object:getpos(), local_target)
    return dist < (tolerance + 1)
  end,

  step_reached = function(self, tolerance)
    -- default values
    if tolerance == nil then
      tolerance = 0.1
    end

    local local_target = self.target
    if self.path ~= nil then
      local_target = self.path[self.path_step_index]
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

      -- if needed, pick a new hunt target
      if self.state ~= "hunt" or self.target_hunt == nil or self.target_hunt.dead then
        if self:pick_hunt_target() then
          self.state = "hunt"
        else
          -- no huntables found, wander
          self:go_to_state("wander")
        end
      end
    elseif target_state == "wander" and self.state ~= "wander" then
      self:set_target(pick_random_target(self.object:getpos(), 40, 5))
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

    if self.path ~= nil then
      local_target = self.path[self.path_step_index]
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
