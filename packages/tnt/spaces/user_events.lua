local user_events_space = {}

function user_events_space.init(box)
    local user_events = box.schema.create_space('user_events', { engine = 'vinyl' })
    user_events:format({
        { name = 'user_id', type = 'integer' },
        { name = 'latest_bubble_id',    type = 'number' },
        { name = "latest_session_id",  type = "number" },
        { name = 'latest_activated_boost_id',   type = 'number' },
        { name = 'latest_dropped_boost_id', type = 'number' },
        { name = 'latest_bubble_pvp_id', type = 'number' },
        { name = 'latest_bubble_pvp_player_id', type = 'number' },
    })
    user_events:create_index('user_id', { sequence = 'user_id_seq' })
end


return user_events_space