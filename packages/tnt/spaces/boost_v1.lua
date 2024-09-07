local boost_v1_space = {}

function boost_v1_space.init(box)
    local boost_v1 = box.schema.create_space('boost_v1', { engine = 'vinyl' })
    boost_v1:format({
        { name = 'boost_v1_id', type = 'uuid' },
        { name = 'user_id',    type = 'number' },
        -- { name = 'timestamp',  type = 'number' },
        { name = 'session_start',  type = 'number' },
        { name = 'session_until',  type = 'number' },
        { name = 'session_taps',  type = 'number' },
        { name = 'session_points',  type = 'number' },
    })
    boost_v1:create_index('pk', { parts = { { 'session_id' }, { 'user_id' } }, unique = true })
    boost_v1:create_index('user_id', { parts = { { 'user_id' } }, unique = false })
end



return boost_v1_space