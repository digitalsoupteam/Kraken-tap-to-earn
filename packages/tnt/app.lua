#!/usr/bin/env tarantool
local uuid = require('uuid')
local log = require("log")
local json = require('json')
local aggregation_periods = { 86400, 604800, 2592000, 7776000 }

log.cfg { format = 'json', level = 'verbose' }
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
        { name = "ref_user_id",      type = "integer" },
        { name = "wallet",           type = "string" },
        { name = "points",           type = "number" },
        { name = "days",             type = "number" },
        { name = "days_in_row",      type = "number" },
        { name = "last_day_timestamp", type = "number" },
    })
    users:create_index('user_id', { sequence = 'user_id_seq' })
    users:create_index('external_user_id', { parts = { { 'external_user_id' } }, unique = true })
    users:create_index('ref_user_id', { parts = { { 'ref_user_id' }, { 'taps' } }, unique = false })
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


local settings = {
    referrer_bps = 2500,
    max_bps = 10000,
}


--- @alias levels {id: number, quota_period: number, quota_amount: number, calm_period: number}
--- @alias user {user_id: number, external_user_id: string, is_blocked: boolean, level: number, session_until: number, session_taps: number, taps: number, nickname: string, wallet: string}
--- @alias userInfo {id: number, user_id: string, is_blocked: boolean, level: levels, nickname: string, session_start: number, session_left: number, session_until: number, session_taps: number, session_taps_left: number, taps: number, calm_until: number, ref_user: userInfo | nil}


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
        return update_levels(1, { quota_period = 120, calm_period = 3600, quota_amount = 6000 })
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
--- @return user | nil
function get_user(user_id)
    local user
    if type(user_id) == 'number' then
        user = box.space.users.index.user_id:get({ user_id })
    else
        local external_user_id = uuid.fromstr(user_id)
        user = box.space.users.index.external_user_id:get({ external_user_id })
    end
    if user == nil then
        return nil
    end
    return user:tomap({ names_only = true })
end

local allowed_update_keys = {
    'is_blocked',
    'level',
    'quota_period',
    'quota_amount',
    'nickname',
    'wallet',
}

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
        if key == "wallet" and user.wallet ~= nil then
            error('cannot update wallet')
        end
        for i = 1, #allowed_update_keys do
            if allowed_update_keys[i] == key then
                break
            end
            if i == #allowed_update_keys then
                error('invalid key')
            end
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
--- @param create_new_user string
--- @param ref_user_id number | nil
--- @return number
function create_new_user(username, ref_user_id)
    local levels = get_or_create_levels(1)
    local now = os.time()
    local new_user = box.space.users:insert({
        box.NULL,
        uuid.new(),
        false,
        1,
        0,
        0,
        0,
        username,
        ref_user_id,
        '',
        0,
        1,
        1,
        now
    })
    return new_user[1]
end

--- create anonymous user
--- @param ref_user_external_id string | nil
--- @return userInfo
function create_anonymous_user(ref_user_external_id)
    local ref_user_id = 0
    log.info('create anonymous user')
    if ref_user_external_id ~= nil then
        log.info('ref_user_external_id: %s', ref_user_external_id)
        local ref_user = get_user(ref_user_external_id)
        if ref_user == nil then
            error('ref user not found')
        end
        ref_user_id = ref_user.user_id
    end

    local user_id = create_new_user("unknown kraken", ref_user_id)
    local user = get_user_info(user_id)
    if user == nil then
        error('user not found')
    end
    return user
end

--- Get or create user from telegram id
--- @param id string
--- @param username string
--- @param ref_user_external_id string | nil
--- @return userInfo
function get_or_create_user_from_tg(id, username, ref_user_external_id)
    local ref_user_id = 0
    if ref_user_external_id ~= nil then
        local ref_user = get_user(ref_user_external_id)
        if ref_user == nil then
            error('ref user not found')
        end
        ref_user_id = ref_user.user_id
    end
    local res = box.space.tg2user.index.pk:get(id)
    local user_id
    if res == nil then
        user_id = create_new_user(username, ref_user_id)
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
-- @param skip_ref_user boolean
-- @return userInfo | nil
function to_user_info(user, skip_ref_user)
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
            user.session_taps = 0
            user.session_until = 0
            box.space.users:update({ user.user_id }, { { '=', 'session_taps', 0 }, { '=', 'session_until', 0 } })
        end
        left = level.quota_period
        taps_left = level.quota_amount
    end

    local days = user.days
    local days_in_row = user.days_in_row
    local last_day_timestamp = user.last_day_timestamp

    local seconds_in_day = 24 * 60 * 60

    if now > last_day_timestamp + seconds_in_day then: -- wait one day
        days += 1 -- total counter

        if now > last_day_timestamp + seconds_in_day * 2 then: 
            days_in_row = 1 -- if more 2 days, reset to default
        else:                                                      
            days_in_row += 1 -- if less 2 days, endless increment 
        end

        last_day_timestamp = now -- save checkpoint

        box.space.users:update({ user.user_id }, { { '=', 'days', days }, { '=', 'days_in_row', days_in_row }, { '=', 'last_day_timestamp', last_day_timestamp } })
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
        ref_user = nil,
        wallet = user.wallet,
        points = user.points,
        days = days,
        days_in_row = days_in_row,
        last_day_timestamp = last_day_timestamp,
    }
    if skip_ref_user ~= true and user.ref_user_id ~= nil then
        local ref_user = get_user_info(user.ref_user_id, true)
        result.ref_user = ref_user
    end
    return result
end

---Get user info
---@param user_id string | number
---@param skip_ref_user boolean | nil
---@return userInfo | nil
function get_user_info(user_id, skip_ref_user)
    local user = get_user(user_id)
    if user == nil then
        return nil
    end
    return to_user_info(user, skip_ref_user)
end

---Get top 100 Referred users
---@param by_user_id string
---@param limit number
---@return userInfo[]
function get_top_referrals(by_user_id, limit)
    if type(limit) ~= 'number' then
        limit = 100
    end
    local user = get_user(by_user_id)
    if user == nil then
        error('user not found')
    end
    local users = box.space.users.index.ref_user_id:select({ user.user_id }, { limit = limit, iterator = 'REQ' })
    local results = {}
    for i = 1, #users do
        results[i] = to_user_info(users[i]:tomap({ names_only = true }), true)
    end
    return results
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
        results[i] = to_user_info(users[i]:tomap({ names_only = true }), true)
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
                if user_info.session_left == 0 then
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

                    local limitedDays = user.days_in_row > 10 ? 10 : user.days_in_row -- 10 days limit
                    local daysMultiplier = limitedDays * 0.1 -- 10%
                    local inserted_points = inserted_taps + inserted_taps * daysMultiplier

                    local user_updates = {
                        { '+', 'session_taps', inserted_taps },
                        { '+', 'taps',         inserted_taps },
                        { '+', 'points',       inserted_points },
                    }
                    if user_info.session_taps == 0 then
                        table.insert(user_updates, { '=', 'session_until', now + user_info.level.quota_period })
                        results[i].user_info['session_until'] = now + user_info.level.quota_period
                    end

                    box.space.users:update({ user_info.id }, user_updates)
                    if user_info.ref_user ~= nil then
                        box.space.users:update(
                            { user_info.ref_user.id },
                            { { '+', 'points', inserted_points * settings.referrer_bps / 10000 } }
                        )
                    end
                end
                results[i].user_info['session_taps'] = user_info['session_taps'] + inserted_taps
                results[i].user_info['taps'] = user_info['taps'] + inserted_taps
                results[i].user_info['points'] = user_info['points'] + inserted_points
                results[i].user_info['session_taps_left'] = user_info['session_taps_left'] - inserted_taps
            end
        end
    end
    return results
end

-- vim:ts=4 ss=4 sw=4 expandtab
