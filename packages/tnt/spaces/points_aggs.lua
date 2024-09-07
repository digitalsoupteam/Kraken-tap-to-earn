local points_aggs_space = {}

function points_aggs.init(box)
    local points_aggs = box.schema.create_space('points_aggs', { engine = 'vinyl' })
    points_aggs:format({
        { name = 'user_id',   type = 'number' },
        { name = 'period',    type = 'number' }, -- 86400
        { name = 'timestamp', type = 'number' }, -- now() // 86400 * 86400
        { name = 'count',     type = 'number' },
    })
    points_aggs:create_index('pk', { parts = { { 'user_id' }, { 'period' }, { 'timestamp' } }, unique = true })
    points_aggs:create_index('periods', { parts = { { 'user_id' }, { 'period' } }, unique = false })
    points_aggs:create_index('user_id', { parts = { { 'user_id' } }, unique = false })
end

return points_aggs
