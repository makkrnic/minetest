math.randomseed(os.time())

minetest.register_node("alsim:plant", {
  tiles = {"alsim_plant.png"},
  groups = {snappy=1,choppy=2,flammable=3,falling_node=1,oddly_breakable_by_hand=3},
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
