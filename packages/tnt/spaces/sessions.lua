local sessions_space = {}

function sessions_space.init(box)
    local sessions = box.schema.create_space('sessions', { engine = 'vinyl' })
    sessions:format({
        { name = 'session_id', type = 'uuid' },
        { name = 'user_id',    type = 'number' },
        -- { name = 'timestamp',  type = 'number' },
        { name = 'session_start',  type = 'number' },
        { name = 'session_until',  type = 'number' },
        { name = 'session_taps',  type = 'number' },
        { name = 'session_points',  type = 'number' },
    })
    sessions:create_index('pk', { parts = { { 'session_id' }, { 'user_id' } }, unique = true })
    sessions:create_index('user_id', { parts = { { 'user_id' } }, unique = false })
end

function sessions_space.create(box)
    
end


return sessions_space
