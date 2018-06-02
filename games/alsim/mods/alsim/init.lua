math.randomseed(os.time())
local mod_storage = minetest.get_mod_storage()
local stats

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

local player
local huds = {}

minetest.register_on_joinplayer(function(the_player)
  player = the_player

  local privs = minetest.get_player_privs(player:get_player_name())
  privs["fly"] = true
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

  if what == "plants_count" then
    mod_storage:set_int("plants_count", stats[what])
  end

  update_hud(player)
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

minetest.register_abm({
  name = "alsim_plant_reproduction",
  nodenames = {"alsim:plant"},
  interval = 10.0,
  chance = 10,
  action = function(pos, node, active_object_count, active_object_count_wider)
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
  new_pos = pos
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

local passive_energy_consumption = 0.001
local walking_energy_consumption = 0.4
local jumping_energy_consumption = 3

local energy_in_plant = 500

local herbivore_view_distance = 10

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
  collisionbox = {-0.49, -0.49, -0.49, 0.49, 0.49, 0.49, 0.49},
  physical = true,
  automatic_rotation = 0.1,
  automatic_face_movement_dir = 0.0,

  -- New entities will have energy 500. Maximum is 1000, and when
  -- 0 is reached, they die.
  energy = 400.0,

  _counted = false,
  on_activate = function(self, staticdata)
    if not self._counted then
      stats_update("herbivores_count", 1)
      self._counted = true
    end

    self.object:setacceleration({x = 0, y = -10, z = 0})
  end,
  on_death = function()
    stats_update("herbivores_count", -1)
  end,

  state = "stand",
  target = nil,
  hunt_target = nil,
  path = nil,
  path_step_index = 1,

  set_target = function(self, target)
    print('setting target...')
    print('path: '..tostring(self.path))
    -- dbg(self.path == nil)
    if target ~= nil then
      local path = minetest.find_path(self.object:getpos(), target, 4 * herbivore_view_distance, 1, 1, 'A*')
      if path == nil then
        -- if we are trying to find a path towards a 'plant' node we must put the target one block above
        local alt_target = {x = target.x, y = target.y + 1, z = target.z}
        path = minetest.find_path(self.object:getpos(), alt_target, 4 * herbivore_view_distance, 1, 1, 'A*')
      end
      if path ~= nil then
        self.path = path
        self.target = target
        self.path_step_index = 1
      else
        -- target can't be reached
        self.target = nil
        self.hunt_target = nil
      end
    end
  end,

  set_hunt_target = function(self, target)
    self.hunt_target = target
    self:set_target(target)
  end,

  pick_hunt_target = function(self)
    print('picking hunt target...')
    local huntable = find_nodes_around(self.object:getpos(), herbivore_view_distance, {"alsim:plant"})
    if table.getn(huntable) == 0 then
      if self.target == nil then
        self:set_target(pick_random_target(self.object:getpos(), 20, 5))
      end
      return nil
    else
      local selfpos = self.object:getpos()
      for _, pos in pairs(huntable) do
        direct, blocking = minetest.line_of_sight(selfpos, pos, 1)

        -- print("Direct: "..minetest.serialize(direct))
        -- print("pos2 : "..minetest.serialize(pos))
        -- print("Block: "..minetest.serialize(blocking))
        if direct or blocking.x == pos.x and blocking.y == pos.y and blocking.z == pos.z then
          --print("Picking hunt target")
          self:set_hunt_target(pos)
          break
        end
      end
    end

    return self.target
  end,

  jump = function(self)
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
    end

    if self:step_reached() then
      print('step reached')
      print('target: '..minetest.serialize(self.target))
      print('path: '..minetest.serialize(self.path))
      print('path index: '..minetest.serialize(self.path_step_index))
      self:advance_step()
    end

    if self.energy <= 0 then
      self:die()
    end

    self:decide_next_action()
  end,

  advance_step = function(self)
    if self.path ~= nil then
      local steps_count = table.getn(self.path)
      print('steps count: '..steps_count)

      if self.path_step_index < steps_count then
        print('advancing...')
        self.path_step_index = self.path_step_index + 1
      end
    end
  end,

  decide_next_action = function(self)
    --print("energy: "..self.energy)
    if self.state == "hunt" and self:target_reached() then
      self:go_to_state("eat")
    elseif self.state == "eat" and self.hunt_target == nil then
      -- how did this happen
      self:go_to_state("hunt")
    elseif self.energy <= 400 then
      self:go_to_state("hunt")
    else
      local rn = math.random(1, 1000)

      if rn <= 30 then
        self:go_to_state("wander")
      end
    end
  end,

  target_reached = function(self, tolerance)
    if tolerance == nil then
      tolerance = 0.1
    end

    if self.target == nil then
      return false
    end

    local dist = vector.distance(self.object:getpos(), self.target)
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

  go_to_state = function(self, target_state)
    if target_state == "hunt" then
      -- check if the target somehow got removed (eaten)
      local target_node = nil
      print('hunt target: '..pretty(self.hunt_target))
      if self.hunt_target ~= nil then
        target_node = minetest.get_node_or_nil(self.hunt_target)
        --dbg()
      end

      -- if needed, pick a new hunt target
      print('target: '..pretty(target_node))
      print('current state: '..pretty(self.state))
      if self.state ~= "hunt" or target_node == nil or target_node.name ~= "alsim:plant" then
        print('started hunting')
        if self:pick_hunt_target() == nil then
          -- no huntables found, wander
          self:go_to_state("wander")
        else
          self.state = "hunt"
        end
      end
    elseif target_state == "wander" and self.state ~= "wander" then
      self:set_target(pick_random_target(self.object:getpos(), 40, 5))
      self.state = "wander"
    elseif target_state == "eat" then
      if self.state ~= "eat" then
        self.state = "eat"
      end
    end
  end,

  advance_towards_target = function(self)
    local local_target = self.target
    if self.path ~= nil then
      local_target = self.path[self.path_step_index]
    end
    local sp = self.object:getpos()
    local vec = {x=local_target.x-sp.x, y=local_target.y-sp.y, z=local_target.z-sp.z}
    local yaw = atan2(vec.x, vec.z) + math.pi/2

    self.object:setyaw(yaw)

    local x = math.sin(yaw) * 5
    local z = math.cos(yaw) * -5
    self.object:setvelocity({x = x, y = self.object:getvelocity().y, z = z})

    if vec.y > 0.2 then
      self:jump()
    end
  end,

  die = function(self)
    self.on_death()
    self.object:remove()
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
