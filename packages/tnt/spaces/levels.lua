local levels_space = {}

function levels_space.init(box)
    local levels = box.schema.create_space('levels', { engine = 'vinyl' })
    levels:format({
        { name = 'level',        type = 'number' },
        { name = 'quota_period', type = 'number' },
        { name = 'quota_amount', type = 'number' },
        { name = 'calm_period',  type = 'number' },
    })
    levels:create_index('pk', { parts = { { 'level' } }, unique = true })
end



--- Get or create levels
--- @param level_id number
--- @return levels
function levels_space.get_or_create(box, level_id)
    local res = box.space.levels:get(level_id)
    if res ~= nil then
        return res
    else
        return levels_space.update(box, 1, { quota_period = 120, calm_period = 3600, quota_amount = 6000 })
    end
end


-- --- Update levels
-- --- @param new_levels levels
-- --- @return levels
-- function levels_space.update(box, id, new_levels)
--     local res = box.space.levels:select({ id })
--     if #res == 0 then
--         return box.space.levels:insert({
--             id,
--             new_levels['quota_period'],
--             new_levels['quota_amount'],
--             new_levels['calm_period'],
--         })
--     else
--         local update = {}
--         for key, value in pairs(new_levels) do
--             if key == 'quota_period' or key == 'quota_amount' or key == 'calm_period' then
--                 if value ~= nil then
--                     table.insert(update, { '=', key, value })
--                 end
--             end
--         end
--         return box.space.levels:update({ id }, update)
--     end
-- end

return levels_space
