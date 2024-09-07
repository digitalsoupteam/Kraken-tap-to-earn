local users_space = {}

function users_space.init(box)
    local daily_bonus = box.schema.create_space('daily_bonus', { engine = 'vinyl' })
    daily_bonus:format({
        { name = 'user_id', type = 'integer' },
        { name = 'total_days',    type = 'number' },
        { name = "days_in_row",  type = "number" },
        { name = 'days_updated_at',   type = 'number' },
    })
    daily_bonus:create_index('user_id', { sequence = 'user_id_seq' })
end

return users_space