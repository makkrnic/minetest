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

minetest.register_entity("alsim:herbivore", {
  textures = {"alsim_herbivore.png", "alsim_herbivore.png", "alsim_herbivore.png", "alsim_herbivore.png", "alsim_herbivore.png", "alsim_herbivore.png"},
  visual = "cube",
  on_activate = function(self, staticdata)
    local sd = minetest.deserialize(staticdata)
    if sd == nil or not sd.counted then
      stats_update("herbivores_count", 1)
      self.counted = true
    end
  end,
  on_death = function()
    stats_update("herbivores_count", -1)
  end,
  get_staticdata = function()
    return minetest.serialize({counted = true})
  end,
})

minetest.register_craftitem("alsim:herbivore", {
  description = "herbivore",
  inventory_image = "alsim_herbivore.png",
  on_place = function(itemstack, place, pointed_thing)
    minetest.env:add_entity(pointed_thing.above, "alsim:herbivore")
    return itemstack
  end,
})
