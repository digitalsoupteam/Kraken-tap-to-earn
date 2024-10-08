#!/usr/bin/env tarantool
---@diagnostic disable: lowercase-global
local uuid = require('uuid')
local log = require("log")
local fiber = require 'fiber'
local ws = require("websocket")
local json = require("json")

local AGGREGATION_PERIODS = { 86400, 604800, 2592000, 7776000 }
local SECONDS_IN_DAY = 24 * 60 * 60

log.cfg { format = 'json', level = 'verbose' }
box.cfg {
    txn_isolation = 'read-committed',
    readahead = 64 * 1024,
    -- readahead = 1 * 1024 * 1024,
}
box.once('schema', function()
    box.schema.sequence.create('user_id_seq')
    box.schema.sequence.create('tap_id_seq')
    local taps = box.schema.create_space('taps', { engine = 'vinyl' })
    taps:format({
        { name = 'tap_id',    type = 'integer' },
        { name = 'user_id',   type = 'number' },
        { name = 'timestamp', type = 'number' },
        { name = 'x',         type = 'number' },
        { name = 'y',         type = 'number' },
    })
    taps:create_index('pk', { sequence = 'tap_id_seq' })
    taps:create_index('user_id', { parts = { { 'user_id' } }, unique = false })

    local points_aggs = box.schema.create_space('points_aggs', { engine = 'memtx' })
    points_aggs:format({
        { name = 'user_id',   type = 'number' },
        { name = 'period',    type = 'number' }, -- 86400
        { name = 'timestamp', type = 'number' }, -- now() // 86400 * 86400
        { name = 'count',     type = 'number' },
    })
    points_aggs:create_index('pk', { parts = { { 'user_id' }, { 'period' }, { 'timestamp' } }, unique = true })
    points_aggs:create_index('periods', { parts = { { 'user_id' }, { 'period' } }, unique = false })
    points_aggs:create_index('user_id', { parts = { { 'user_id' } }, unique = false })

    local users = box.schema.create_space('users', { engine = 'memtx' })
    users:format({
        { name = 'user_id',          type = 'integer' },
        { name = 'external_user_id', type = 'uuid' },
        { name = 'is_blocked',       type = 'boolean' },
        { name = 'level',            type = 'number' },
        { name = 'session_taps',     type = 'number' },
        { name = 'session_until',    type = 'number' },
        { name = 'taps',             type = 'number' },
        { name = 'nickname',         type = 'string' },
        { name = "ref_user_id",      type = "integer", is_nullable = true },
        { name = "wallet",           type = "string",  is_nullable = true },
        { name = "points",           type = "number" },
        { name = "days",             type = "number" },
        { name = "days_in_row",      type = "number" },
        { name = "days_updated_at",  type = "number" },
    })
    users:create_index('user_id', { sequence = 'user_id_seq' })
    users:create_index('wallet', {
        parts = {
            { field = 'wallet', exclude_null = true, is_nullable = true },
        },
        unique = true,
    })
    users:create_index('external_user_id', { parts = { { 'external_user_id' } }, unique = true })
    users:create_index('ref_user_id',
        { parts = { { 'ref_user_id', exclude_null = true }, { 'points' } }, unique = false })
    users:create_index('taps', { parts = { { 'taps' } }, unique = false })
    users:create_index('points', { parts = { { 'points' } }, unique = false })
    users:create_index('position', { parts = { { 'points' }, { 'user_id' } }, unique = false })

    local tg2user = box.schema.create_space('tg2user', { engine = 'memtx' })
    tg2user:format({
        { name = 'tg_id',   type = 'string' },
        { name = 'user_id', type = 'number' },
    })
    tg2user:create_index('pk', { parts = { { 'tg_id' } }, unique = true })
    tg2user:create_index('user_id', { parts = { { 'user_id' } }, unique = true })

    local sessions = box.schema.create_space('sessions', { engine = 'memtx' })
    sessions:format({
        { name = 'session_id', type = 'uuid' },
        { name = 'user_id',    type = 'number' },
        { name = 'timestamp',  type = 'number' },
    })
    sessions:create_index('pk', { parts = { { 'session_id' }, { 'user_id' } }, unique = true })

    local levels = box.schema.create_space('levels', { engine = 'memtx' })
    levels:format({
        { name = 'level',        type = 'number' },
        { name = 'quota_period', type = 'number' },
        { name = 'quota_amount', type = 'number' },
        { name = 'calm_period',  type = 'number' },
    })
    levels:create_index('pk', { parts = { { 'level' } }, unique = true })
end)


local settings = {
    referral_levels = {
        0.1,
        0.035,
    },
    referral_initial_points = 10000,
    days_in_row_limit = 10,
    days_in_row_multiplier = 0.1
}


--- @alias levels {id: number, quota_period: number, quota_amount: number, calm_period: number}
--- @alias user {user_id: number, external_user_id: string, is_blocked: boolean, level: number, session_until: number, session_taps: number, taps: number, nickname: string, wallet: string}
--- @alias userInfo {id: number, user_id: string, is_blocked: boolean, level: levels, nickname: string, session_start: number, session_left: number, session_until: number, session_taps: number, session_taps_left: number, taps: number, calm_until: number, ref_user: userInfo | nil, ref_user_id: number, days_in_row: number, days: number, days_updated_at: number, points: number, wallet: string}

--- On user update trigger
--- @param old_user user
--- @param new_user user
function on_user_update(old_user, new_user)
    local user = to_user_info(new_user:tomap({ names_only = true }), { fetch_ref_user = false, fetch_position = false })
    broadcast(user)
end

box.space.users:on_replace(on_user_update)

local ws_peers = {}

function on_subscribe(peer)
    for i = 1, #ws_peers do
        if ws_peers[i] == peer then
            return
        end
    end
    table.insert(ws_peers, peer)
end

function on_unsubscribe(peer)
    for i = 1, #ws_peers do
        if ws_peers[i] == peer then
            table.remove(ws_peers, i)
            break
        end
    end
end

function broadcast(msg)
    local payload = json.encode(msg)
    for i = 1, #ws_peers do
        -- log.info('broadcast: %s', payload)
        ws_peers[i]:write(payload)
    end
end

ws.server('ws://0.0.0.0:3000', function(ws_peer)
    on_subscribe(ws_peer)
    while true do
        local msg = ws_peer:read()
        if msg == nil or msg.opcode == nil then
            on_unsubscribe(ws_peer)
            break
        end
    end
end)

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

--- Update user (External)
--- @param user_id string
--- @param params {is_blocked: boolean, level: number, quota_period: number, quota_amount: number, nickname: string}
--- @return userInfo | nil
function update_user(user_id, params)
    -- log.info('update user: %s with %s', user_id, json.encode(params))
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
--- @param username string
--- @param ref_user_id number
--- @return number
function create_new_user(username, ref_user_id)
    -- log.info('create new user: %s', username)
    local now = os.time()
    local initial_points = 0
    if ref_user_id ~= 0 then
        initial_points = settings.referral_initial_points
        box.space.users:update(
            { ref_user_id },
            { { '+', 'points', initial_points } }
        )
    end
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
        nil,
        initial_points,
        1,
        1,
        now
    })
    return new_user[1]
end

--- create anonymous user (External)
--- @param ref_user_external_id string | nil
--- @return userInfo
function create_anonymous_user(ref_user_external_id)
    local ref_user_id = 0
    if ref_user_external_id ~= nil then
        local ref_user = get_user(ref_user_external_id)
        if ref_user == nil then
            error('ref user not found')
        end
        ref_user_id = ref_user.user_id
    end

    local user_id = box.atomic(create_new_user, "unknown kraken", ref_user_id)
    fiber.yield()
    local user = get_user_info(user_id)
    if user == nil then
        error('user not found')
    end
    return user
end

--- Get or create user from telegram id (External)
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
    fiber.yield()
    local user_id
    if res == nil then
        -- log.info('create new user from telegram id: %s (%s)', id, username)
        box.atomic(function()
            user_id = create_new_user(username, ref_user_id)
            box.space.tg2user:insert({ id, user_id })
        end)
    else
        -- log.info('get user from telegram id: %s (%s)', id, username)
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
---@param opts {fetch_ref_user?: boolean, fetch_position?: boolean} | nil
-- @return userInfo | nil
function to_user_info(user, opts)
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
            -- do not update ref_user
            if type(opts) == 'table' and opts['fetch_ref_user'] == true then
                box.space.users:update({ user.user_id }, { { '=', 'session_taps', 0 }, { '=', 'session_until', 0 } })
            end
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
        ref_user = nil,
        ref_user_id = user.ref_user_id,
        wallet = user.wallet,
        points = user.points,
        days = user.days,
        days_in_row = user.days_in_row,
        days_updated_at = user.days_updated_at,
    }
    if opts ~= nil and opts['fetch_position'] == true then
        result.position = get_position_of(user)
    end
    if opts ~= nil and opts['fetch_ref_user'] == true and user.ref_user_id ~= nil then
        result.ref_user = get_user_info(user.ref_user_id, {})
    end
    return result
end

---Get user details (External)
---@param user_id string | number
---@return userInfo | nil
function get_user_details(user_id)
    local user = get_user(user_id)
    if user == nil then
        return nil
    end
    return to_user_info(user, { fetch_ref_user = true, fetch_position = true })
end

---Get user info
---@param user_id string | number
---@param opts {fetch_ref_user?: boolean, fetch_position?: boolean} | nil
---@return userInfo | nil
function get_user_info(user_id, opts)
    local user = get_user(user_id)
    if user == nil then
        return nil
    end
    return to_user_info(user, opts)
end

---Get top 100 Referred users (External)
---@param by_user_id string
---@param limit number
---@return userInfo[]
function get_top_referrals(by_user_id, limit)
    -- log.info('get top referrals: %s', by_user_id)
    if type(limit) ~= 'number' then
        limit = 100
    end
    local user = get_user(by_user_id)
    if user == nil then
        error('user not found')
    end
    fiber.yield()
    local users = box.space.users.index.ref_user_id:select({ user.user_id }, { limit = limit, iterator = 'REQ' })
    local results = {}
    for i = 1, #users do
        results[i] = to_user_info(users[i]:tomap({ names_only = true }), {})
    end
    return results
end

---Get top 100 users (External)
---@param limit number
---@return userInfo[]
function get_top_users(limit)
    -- log.info('get top users')
    if type(limit) ~= 'number' then
        limit = 100
    end
    local users = box.space.users.index.points:select({}, { limit = limit, iterator = 'REQ' })
    fiber.yield()
    local results = {}
    for i = 1, #users do
        results[i] = to_user_info(users[i]:tomap({ names_only = true }), {})
    end
    return results
end

---Get user around (External)
---@param user_id string
---@param limit number
---@return {above: userInfo[], below: userInfo[]}
function get_users_around_of(user_id, limit)
    -- log.info('get users around: %s', user_id)
    local user_info = get_user_info(user_id)
    fiber.yield()
    if user_info == nil then
        error('user not found')
    end
    if type(limit) ~= 'number' then
        limit = 10
    end
    local above = box.space.users.index.position:select({ user_info.points, user_info.id },
        { limit = limit, iterator = 'GT' })
    fiber.yield()
    local below = box.space.users.index.position:select({ user_info.points, user_info.id },
        { limit = limit, iterator = 'LT' })
    fiber.yield()
    local results = { above = {}, below = {} }
    for i = 1, #above do
        results.above[i] = to_user_info(above[i]:tomap({ names_only = true }), {})
    end
    for i = 1, #below do
        results.below[i] = to_user_info(below[i]:tomap({ names_only = true }), {})
    end
    return results
end

---Get user position
---@param user_info userInfo
---@return number
function get_position_of(user_info)
    return box.space.users.index.points:count({ user_info.points, user_info.id }, { iterator = 'GE' })
end

---Validate taps batch item
---@param batch {user_id: string, taps: {x: number, y: number}}[]
---@return boolean
function validate_batch(batch)
    for i = 1, #batch do
        if type(batch[i]) ~= 'table' then
            return false
        end
        if batch[i].user_id == nil then
            return false
        end
        if batch[i].taps == nil then
            return false
        end
        if #batch[i].taps == 0 then
            return false
        end
        if type(batch[i].taps) ~= 'table' then
            return false
        end
    end
    return true
end

---Register taps (External)
---@param batch {user_id: string, taps: {x: number, y: number}}[]
---@return {user_info: userInfo, error: nil}[]
function register_taps(batch)
    -- log.info('register taps (%d)', #batch)
    local results = {}
    local now = os.time()
    for i = 1, #batch do
        results[i] = { nil, nil }
        if validate_batch(batch) == false then
            results[i].error = 'invalid batch item'
        else
            local user_id = batch[i].user_id
            local taps = batch[i].taps
            local effective_taps = #taps
            local user_info = get_user_info(user_id, { fetch_ref_user = false, fetch_position = false })
            fiber.yield()
            if user_info == nil then
                results[i].error = 'user not found'
            else
                results[i].user_info = user_info
                if user_info.session_left == 0 then
                    results[i].error = 'time quota exceeded'
                elseif user_info.session_taps_left == 0 then
                    results[i].error = 'taps quota exceeded'
                else
                    local inserted_taps = 0
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
                    box.atomic(function()
                        local limited_days = user_info.days_in_row
                        if limited_days > settings.days_in_row_limit then
                            limited_days = settings.days_in_row_limit
                        end
                        local days_multiplier = limited_days * settings.days_in_row_multiplier
                        local inserted_points = inserted_taps + inserted_taps * days_multiplier
                        local days = user_info.days
                        local days_in_row = user_info.days_in_row
                        local days_updated_at = user_info.days_updated_at

                        for j = 1, #AGGREGATION_PERIODS do
                            local period = AGGREGATION_PERIODS[j]
                            local period_time = math.floor(now / period) * period
                            box.space.points_aggs:upsert(
                                { user_info.id, period, period_time, inserted_points },
                                { { '+', 4, inserted_points } }
                            )
                        end

                        local user_updates = {
                            { '+', 'session_taps', inserted_taps },
                            { '+', 'taps',         inserted_taps },
                            { '+', 'points',       inserted_points },
                        }

                        if now > days_updated_at + SECONDS_IN_DAY then -- wait one day
                            days = days + 1                            -- total counter

                            if now > days_updated_at + SECONDS_IN_DAY * 2 then
                                days_in_row = 1               -- if more 2 days, reset to default
                            else
                                days_in_row = days_in_row + 1 -- if less 2 days, endless increment
                            end

                            days_updated_at = now -- save checkpoint

                            table.insert(user_updates, { '=', 'days', days })
                            table.insert(user_updates, { '=', 'days_in_row', days_in_row })
                            table.insert(user_updates, { '=', 'days_updated_at', days_updated_at })
                        end

                        if user_info.session_taps == 0 then
                            table.insert(user_updates, { '=', 'session_until', now + user_info.level.quota_period })
                            results[i].user_info['session_until'] = now + user_info.level.quota_period
                        end

                        box.space.users:update({ user_info.id }, user_updates)

                        -- Referrals
                        -- 1 level
                        local ref1_id = user_info.ref_user_id
                        if ref1_id ~= 0 then
                            local ref1_points = inserted_points * settings.referral_levels[1]
                            box.space.users:update(
                                { ref1_id },
                                { { '+', 'points', ref1_points } }
                            )
                            -- 2 level
                            local ref2_id = user_info.ref_user.ref_user_id
                            local ref2_points = inserted_points * settings.referral_levels[2]
                            if ref2_id ~= 0 then
                                box.space.users:update(
                                    { ref2_id },
                                    { { '+', 'points', ref2_points } }
                                )
                            end
                        end
                        results[i].user_info['session_taps'] = user_info['session_taps'] + inserted_taps
                        results[i].user_info['taps'] = user_info['taps'] + inserted_taps
                        results[i].user_info['points'] = user_info['points'] + inserted_points
                        results[i].user_info['session_taps_left'] = user_info['session_taps_left'] - inserted_taps
                    end)
                end
            end
        end
    end
    return results
end

box.once('fixtures', function()
    -- log.info("self-check users")
    local ref_user = create_anonymous_user()
    box.space.users:update({ ref_user.id },
        { { '=', 'external_user_id', uuid.fromstr('e92148b9-0c2c-4b15-869a-d248149d0f55') } })
    ref_user.user_id = 'e92148b9-0c2c-4b15-869a-d248149d0f55'
    local user1 = get_or_create_user_from_tg('1', 'user1')
    local user2 = get_or_create_user_from_tg('2', 'user2', ref_user.user_id)
    local user3 = get_or_create_user_from_tg('3', 'user3', ref_user.user_id)
    local user4 = get_or_create_user_from_tg('4', 'user4')
    local user5 = get_or_create_user_from_tg('5', 'user5', user2.user_id)
    local user6 = get_or_create_user_from_tg('5', 'user5', ref_user.user_id)

    -- log.info("self-check taps")
    register_taps({
        {
            user_id = user2.user_id,
            taps = {
                { x = 1, y = 1 },
                { x = 1, y = 1 },
                { x = 1, y = 1 },
                { x = 1, y = 1 },
                { x = 1, y = 1 },
            }
        },
        {
            user_id = user3.user_id,
            taps = {
                { x = 1, y = 1 },
                { x = 1, y = 1 },
                { x = 1, y = 1 },
            }
        },
        {
            user_id = user4.user_id,
            taps = {
                { x = 1, y = 1 },
                { x = 1, y = 1 }
            }
        },
        {
            user_id = user5.user_id,
            taps = {
                { x = 1, y = 1 },
                { x = 1, y = 1 },
                { x = 1, y = 1 },
            }
        },
    })

    -- log.info("self-check top users")
    get_top_users(100)

    -- log.info("self-check top referrals")
    get_top_referrals(ref_user.user_id, 100)

    -- log.info("self-check users around")
    get_users_around_of(ref_user.user_id, 100)
end)
-- vim:ts=4 ss=4 sw=4 expandtab
