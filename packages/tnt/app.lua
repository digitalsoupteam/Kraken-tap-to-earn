#!/usr/bin/env tarantool
local uuid = require('uuid')
local aggregation_periods = { 86400, 604800, 2592000, 7776000 }

box.cfg {}
box.once('schema', function()
    box.schema.sequence.create('user_id_seq')
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

    local taps_aggs = box.schema.create_space('taps_aggs', { engine = 'vinyl' })
    taps_aggs:format({
        { name = 'user_id',   type = 'number' },
        { name = 'period',    type = 'number' }, -- 86400
        { name = 'timestamp', type = 'number' }, -- now() // 86400 * 86400
        { name = 'count',     type = 'number' },
    })
    taps_aggs:create_index('pk', { parts = { { 'user_id' }, { 'period' }, { 'timestamp' } }, unique = true })
    taps_aggs:create_index('periods', { parts = { { 'user_id' }, { 'period' } }, unique = false })
    taps_aggs:create_index('user_id', { parts = { { 'user_id' } }, unique = false })

    local users = box.schema.create_space('users', { engine = 'vinyl' })
    users:format({
        { name = 'user_id',          type = 'integer' },
        { name = 'external_user_id', type = 'uuid' },
        { name = 'is_blocked',       type = 'boolean' },
        { name = 'level',            type = 'number' },
        { name = 'session_taps',     type = 'number' },
        { name = 'session_until',    type = 'number' },
        { name = 'taps',             type = 'number' },
        { name = 'nickname',         type = 'string' },
    })
    users:create_index('user_id', { sequence = 'user_id_seq' })
    users:create_index('external_user_id', { parts = { { 'external_user_id' } }, unique = true })
    users:create_index('taps', { parts = { { 'taps' } }, unique = false })

    local tg2user = box.schema.create_space('tg2user', { engine = 'vinyl' })
    tg2user:format({
        { name = 'tg_id',   type = 'string' },
        { name = 'user_id', type = 'number' },
    })
    tg2user:create_index('pk', { parts = { { 'tg_id' } }, unique = true })
    tg2user:create_index('user_id', { parts = { { 'user_id' } }, unique = true })

    local sessions = box.schema.create_space('sessions', { engine = 'vinyl' })
    sessions:format({
        { name = 'session_id', type = 'uuid' },
        { name = 'user_id',    type = 'number' },
        { name = 'timestamp',  type = 'number' },
    })
    sessions:create_index('pk', { parts = { { 'session_id' }, { 'user_id' } }, unique = true })

    local levels = box.schema.create_space('levels', { engine = 'vinyl' })
    levels:format({
        { name = 'level',        type = 'number' },
        { name = 'quota_period', type = 'number' },
        { name = 'quota_amount', type = 'number' },
        { name = 'calm_period',  type = 'number' },
    })
    levels:create_index('pk', { parts = { { 'level' } }, unique = true })
end)


--- @alias levels {id: number, quota_period: number, quota_amount: number, calm_period: number}
--- @alias user {user_id: number, external_user_id: string, is_blocked: boolean, level: number, session_until: number, session_taps: number, taps: number, nickname: string}
--- @alias userInfo {id: number, user_id: string, is_blocked: boolean, level: levels, nickname: string, session_start: number, session_left: number, session_until: number, session_taps: number, session_taps_left: number, taps: number, calm_until: number}


--- Update levels
--- @param new_levels levels
--- @return levels
function update_levels(id, new_levels)
    local res = box.space.levels:select({ id })
    if #res == 0 then
        return box.space.levels:insert({
            id,
            new_levels['quota_period'],
            new_levels['quota_amount'],
            new_levels['calm_period'],
        })
    else
        local update = {}
        for key, value in pairs(new_levels) do
            if key == 'quota_period' or key == 'quota_amount' or key == 'calm_period' then
                if value ~= nil then
                    table.insert(update, { '=', key, value })
                end
            end
        end
        return box.space.levels:update({ id }, update)
    end
end

--- Get or create levels
--- @param level_id number
--- @return levels
function get_or_create_levels(level_id)
    local res = box.space.levels:get(level_id)
    if res ~= nil then
        return res
    else
        return update_levels(1, { quota_period = 120, calm_period = 3600, quota_amount = 1000 })
    end
end

--- Is telegram id exist
--- @param tg_id number
--- @return boolean
function check_tg_exist(tg_id)
    local res = box.space.tg2user.index.pk:get(tg_id)
    return #res == 0
end

--- Is user id exist
--- @param user_id string
--- @return boolean
function check_user_exist(user_id)
    local user = get_user(user_id)
    return user ~= nil
end

-- Get user using uuid or number
--- @param user_id string|number
--- @return user
function get_user(user_id)
    local user
    if type(user_id) == 'number' then
        user = box.space.users.index.user_id:get({ user_id })
    else
        local external_user_id = uuid.fromstr(user_id)
        user = box.space.users.index.external_user_id:get({ external_user_id })
    end
    return user
end

--- Update user
--- @param user_id string
--- @param params {is_blocked: boolean, level: number, quota_period: number, quota_amount: number, nickname: string}
--- @return userInfo | nil
function update_user(user_id, params)
    local user = get_user(user_id)
    if user == nil then
        error('user not found')
    end
    local update = {}
    for key, value in pairs(params) do
        if key == 'user_id' then
            error('cannot update user_id')
        end
        if key ~= 'is_blocked' and key ~= 'level' and key ~= 'quota_period' and key ~= 'quota_amount' and key ~= 'nickname' then
            error('invalid key')
        end
        table.insert(update, { '=', key, value })
    end
    if #update == 0 then
        error('nothing to update')
    end
    box.space.users:update({ user.user_id }, update)
    return get_user_info(user_id)
end

--- Create new user
--- @return number
function create_new_user()
    local levels = get_or_create_levels(1)
    local new_user = box.space.users:insert({ box.NULL, uuid.new(), false, 1, 0, 0, 0, '' })
    return new_user[1]
end

--- Get or create user from telegram id
--- @param id string
--- @return userInfo
function get_or_create_user_from_tg(id)
    local res = box.space.tg2user.index.pk:get(id)
    local user_id
    if res == nil then
        user_id = create_new_user()
        box.space.tg2user:insert({ id, user_id })
    else
        user_id = res.user_id
    end
    local user = get_user_info(user_id)
    if user == nil then
        error('user not found')
    end
    return user
end

-- user info from user item
-- @param user user
-- @return userInfo | nil
function to_user_info(user)
    local level = get_or_create_levels(user.level)
    local is_blocked = user.is_blocked
    local nickname = user.nickname
    local now = os.time()
    local left
    local taps_left
    local calm_period = 0
    local calm_left = 0
    local session_start = now

    if now < user.session_until then
        left = user.session_until - now
        taps_left = level.quota_amount - user.session_taps
        session_start = user.session_until - level.quota_period
    elseif user.session_until > 0 and now < (user.session_until + level.calm_period) then
        left = 0
        taps_left = 0
        calm_period = user.session_until + level.calm_period
        calm_left = user.session_until + level.calm_period - now
        session_start = user.session_until - level.quota_period
    else
        if user.session_taps > 0 then
            box.space.users:update({ user.user_id }, { { '=', 'session_taps', 0 }, { '=', 'session_until', 0 } })
            user.session_taps = 0
            user.session_until = 0
        end
        left = level.quota_period
        taps_left = level.quota_amount
    end


    local result = {
        id = user.user_id,
        user_id = tostring(user.external_user_id),
        is_blocked = is_blocked,
        level = level,
        nickname = nickname,
        calm_until = calm_period,
        calm_left = calm_left,
        session_start = session_start,
        session_left = left,
        session_until = user.session_until,
        session_taps = user.session_taps,
        session_taps_left = taps_left,
        taps = user.taps,
    }
    return result
end

-- Get user info
-- @param user_id string
-- @return userInfo | nil
function get_user_info(user_id)
    local user = get_user(user_id)
    if user == nil then
        return nil
    end
    return to_user_info(user)
end

---Get top 100 users
---@param limit number
---@return userInfo[]
function get_top_users(limit)
    if type(limit) ~= 'number' then
        limit = 100
    end
    local users = box.space.users.index.taps:select({}, { limit = limit, iterator = 'REQ' })
    local results = {}
    for i = 1, #users do
        results[i] = to_user_info(users[i])
    end
    return results
end

---Register taps
---@param batch {user_id: string, taps: {x: number, y: number}}[]
---@return {user_info: userInfo, error: nil}[]
function register_taps(batch)
    local results = {}
    local now = os.time()
    for i = 1, #batch do
        results[i] = { nil, nil }
        if type(batch[i]) ~= 'table' or batch[i].user_id == nil or batch[i].taps == nil or #batch[i].taps == 0 or type(batch[i].taps) ~= 'table' then
            results[i].error = 'invalid batch item'
        else
            local user_id = batch[i].user_id
            local taps = batch[i].taps
            local effective_taps = #taps
            local user_info = get_user_info(user_id)
            local inserted_taps = 0
            if user_info == nil then
                results[i].error = 'user not found'
            else
                results[i].user_info = user_info
                if user_info.left == 0 then
                    results[i].error = 'time quota exceeded'
                elseif user_info.session_taps_left == 0 then
                    results[i].error = 'taps quota exceeded'
                else
                    if user_info.session_taps_left < effective_taps then
                        effective_taps = user_info.session_taps_left
                    end
                    for j = 1, #taps do
                        local tap = taps[j]
                        if tap['x'] == nil or tap['y'] == nil then
                            results[i].error = 'invalid tap'
                            break
                        end
                        box.space.taps:insert({ box.NULL, user_info.id, now, tap['x'], tap['y'] })
                        inserted_taps = inserted_taps + 1
                    end
                    for j = 1, #aggregation_periods do
                        local period = aggregation_periods[j]
                        local period_time = math.floor(now / period) * period
                        box.space.taps_aggs:upsert({ user_info.id, period, period_time, inserted_taps },
                            { { '+', 4, inserted_taps } })
                    end

                    local user_updates = {
                        { '+', 'session_taps', inserted_taps },
                        { '+', 'taps',         inserted_taps },
                    }
                    if user_info.session_taps == 0 then
                        table.insert(user_updates, { '=', 'session_until', now + user_info.level.quota_period })
                        results[i].user_info['session_until'] = now + user_info.level.quota_period
                    end

                    box.space.users:update({ user_info.id }, user_updates)
                end
                results[i].user_info['session_taps'] = user_info['session_taps'] + inserted_taps
                results[i].user_info['taps'] = user_info['taps'] + inserted_taps
                results[i].user_info['session_taps_left'] = user_info['session_taps_left'] - inserted_taps
            end
        end
    end
    return results
end

-- vim:ts=4 ss=4 sw=4 expandtab
