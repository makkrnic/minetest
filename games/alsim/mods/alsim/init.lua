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
      minetest.chat_send_all("stats for "..ent..": "..count)
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

function pick_random_target(pos, max_distance) -- 1/2 Manhattan distance
  new_pos = pos
  new_pos.x = pos.x - max_distance + (2 * math.random(1, max_distance))
  new_pos.z = pos.z - max_distance + (2 * math.random(1, max_distance))

  -- only choose target not higher/lower than max_distance
  local target_node
  --while true do
    local i = 0
    while true do
      if i > max_distance then
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

minetest.register_entity("alsim:herbivore", {
  textures = {"alsim_herbivore.png", "alsim_herbivore.png", "alsim_herbivore.png", "alsim_herbivore.png", "alsim_herbivore.png", "alsim_herbivore_front.png"},
  visual = "cube",
  collisionbox = {-0.49, -0.49, -0.49, 0.49, 0.49, 0.49, 0.49},
  physical = true,
  automatic_rotation = 0.1,
  automatic_face_movement_dir = 0.0,

  -- New entities will have energy 500. Maximum is 1000, and when
  -- 0 is reached, they die.
  energy = 500.0,

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
  on_step = function(self, dtime)
    self.energy = self.energy - passive_energy_consumption
    self.object:setacceleration({x = 0, y = -10, z = 0})

    local rn = math.random(1, 1000)

    if self.state == "stand" then
      if rn <= 30 then
        self.state = "walk"
        self.target = pick_random_target(self.object:getpos(), 40)
      end
    elseif self.state == "walk" then
      if rn <= 3 then
        self.state = "stand"
      end

      if self.target ~= nil then
        local sp = self.object:getpos()
        local vec = {x=self.target.x-sp.x, y=self.target.y-sp.y, z=self.target.z-sp.z}
        local yaw = atan2(vec.x, vec.z) + math.pi/2

        self.object:setyaw(yaw)

        local x = math.sin(yaw) * 5
        local z = math.cos(yaw) * -5
        self.object:setvelocity({x = x, y = self.object:getvelocity().y, z = z})
      end

      local v = self.object:getvelocity()
      if rn < 50 and v.y == 0 then
        -- jump
        v.y = 5
        self.object:setvelocity(v)
        self.energy = self.energy - jumping_energy_consumption
      end

      self.energy = self.energy - walking_energy_consumption
    end

    if self.energy <= 0 then
      self:die()
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
