local taps_space = {}

function taps_space.init(box)
    box.schema.sequence.create('tap_id_seq')
    local taps = box.schema.create_space('taps', { engine = 'memtx' })
    taps:format({
        { name = 'tap_id',    type = 'integer' },
        { name = 'user_id',   type = 'number' },
        { name = 'timestamp', type = 'number' },
        { name = 'x',         type = 'number' },
        { name = 'y',         type = 'number' },
    })
    taps:create_index('pk', { sequence = 'tap_id_seq' })
    taps:create_index('user_id', { parts = { { 'user_id' } }, unique = false })
end

return taps_space