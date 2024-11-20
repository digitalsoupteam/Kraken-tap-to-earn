local vshard = require('vshard')
local uuid = require("uuid")
local log = require("log")
local fiber = require("fiber")
local ws = require("websocket")
local json = require("json")
local crud = require("crud")


crud.cfg {
    stats = true,
    stats_driver = 'metrics',
    stats_quantiles = true
}

local AGGREGATION_PERIODS = { 86400, 604800, 2592000, 7776000 }
local SECONDS_IN_DAY = 24 * 60 * 60

local settings = {
    referral_levels = {
        0.1,
        0.035,
    },
    referral_initial_points = 10000,
    days_in_row_limit = 10,
    days_in_row_multiplier = 0.1
}


--- @alias levels {level: number, quota_period: number, quota_amount: number, calm_period: number}
--- @alias user {user_id: string, is_blocked: boolean, level: number, session_until: number, session_taps: number, taps: number, nickname: string, wallet: string}
--- @alias userInfo {id: number, user_id: string, is_blocked: boolean, level: levels, nickname: string, session_start: number, session_left: number, session_until: number, session_taps: number, session_taps_left: number, taps: number, calm_until: number, ref_user: userInfo | nil, ref_user_id: number, days_in_row: number, days: number, days_updated_at: number, points: number, wallet: string}

--- Update levels
--- @param new_levels levels
--- @return levels
function update_levels(id, new_levels)
    local update = {}
    for key, value in pairs(new_levels) do
        if key == 'quota_period' or key == 'quota_amount' or key == 'calm_period' then
            if value ~= nil then
                table.insert(update, { '=', key, value })
            end
        end
    end
    local result, err = crud.upsert_object(
        'levels',
        {
            level = id,
            quota_period = new_levels['quota_period'],
            quota_amount = new_levels['quota_amount'],
            calm_period = new_levels['calm_period'],
        },
        update
    )
    if err ~= nil then
        error(err)
    end
    return {
        level = id,
        quota_period = new_levels['quota_period'],
        quota_amount = new_levels['quota_amount'],
        calm_period = new_levels['calm_period'],
    }
end

function tomap(result)
    local rows = result.rows
    local metadata = result.metadata
    local items = {}
    for i = 1, #rows do
        items[i] = {}
        for j = 1, #metadata do
            local field = metadata[j].name
            if field ~= 'bucket_id' then
                items[i][field] = rows[i][j]
            end
        end
    end
    return items 
end


--- Get or create levels (TODO: cache)
--- @param level_id number
--- @return levels
function get_or_create_levels(level_id)
    local res, err = crud.get('levels', level_id, { mode = 'read' })
    if err ~= nil then
        error(err)
    end
    if #res.rows == 0 then
        return update_levels(level_id, { quota_period = 120, calm_period = 3600, quota_amount = 6000 })
    end
    return tomap(res)[1]
end

--- Is telegram id exist
--- @param tg_id number
--- @return boolean
function check_tg_exist(tg_id)
    return crud.count('tg2user', tg_id) > 0
end

--- Is user id exist
--- @param user_id string
--- @return boolean
function check_user_exist(user_id)
    return crud.count('users', user_id) > 0
end

-- Get user using uuid or number
--- @param user_id string|number
--- @return user | nil
function get_user(user_id)
    -- log.info('get user: %s', json.encode(user_id))
    if type(user_id) == 'string' then
        user_id = uuid.fromstr(user_id)
    end
    -- log.info('user_id: %s', user_id)
    local res, err = crud.get('users', user_id, { mode = 'read' })
    -- log.info('res: %s', json.encode(res))
    if err ~= nil then
        error(err)
    end
    local user = tomap(res)
    if #user== 0 then
        return nil
    end
    return user[1] 
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
    crud.update(users, { { '=', 'user_id', user_id } }, update)
    return get_user_info(user_id)
end

--- Create new user
--- @param username string
--- @param ref_user_id number
--- @return number
function create_new_user(username, ref_user_id)
    local now = os.time()
    local initial_points = 0
    if ref_user_id ~= nil then
        -- log.info('ref_user_id: %s', ref_user_id)
        initial_points = settings.referral_initial_points
        crud.update(
            'users',
            ref_user_id,
            { { '+', 'points', initial_points } },
            { noreturn = true }
        )
        -- log.info('ref_user_id: %s (%s)', ref_user_id, type(ref_user_id))
    end
    local new_user, err = crud.insert_object(
        'users',
        {
            user_id = uuid.new(),
            is_blocked = false,
            level = 1,
            session_taps = 0,
            session_until = 0,
            taps = 0,
            nickname = username,
            ref_user_id = ref_user_id,
            wallet = nil,
            points = initial_points,
            days = 1,
            days_in_row = 1,
            days_updated_at = now
        }
    )
    if err ~= nil then
        error(err)
    end
    return tomap(new_user)[1]
end

--- create anonymous user (External)
--- @param ref_user_external_id string | nil
--- @return userInfo
function create_anonymous_user(ref_user_external_id)
    local ref_user_id = nil
    if ref_user_external_id ~= nil then
        local ref_user = get_user(ref_user_external_id)
        if ref_user == nil then
            error('ref user not found')
        end
        ref_user_id = ref_user.user_id
    end

    local user = create_new_user("unknown kraken", ref_user_id)
    return get_user_info(user.user_id, { fetch_ref_user = true, fetch_position = false })
end

--- Get or create user from telegram id (External)
--- @param id string
--- @param username string | nil
--- @param ref_user_external_id string | nil
--- @return userInfo
function get_or_create_user_from_tg(id, username, ref_user_external_id)
    -- log.info('get or create user from telegram id: %s (%s)', id, username)
    local ref_user_id = nil
    if ref_user_external_id ~= nil then
        local ref_user = get_user(ref_user_external_id)
        if ref_user == nil then
            error('ref user not found')
        end
        ref_user_id = ref_user.user_id
    end
    local res, err = crud.get('tg2user', id)
    if err ~= nil then
        error(err)
    end
    local user
    local user_id
    if username == nil then
        username = 'unknown kraken'
    end
    if #res.rows == 0 then
        -- log.info('create new user from telegram id: %s (%s) %s', id, username, ref_user_id)
        user = create_new_user(username, ref_user_id)
        -- log.info('user: %s', json.encode(user))
        user_id = user.user_id
        crud.insert_object('tg2user', { tg_id = id, user_id = user_id}, { noreturn = true })
    else
        -- log.info('get user from telegram id: %s (%s)', id, username)
        user = tomap(res)[1]
        user_id = user.user_id
    end
    -- log.info('user_id: %s', json.encode(user)) 
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
                crud.update('users', user.user_id, { { '=', 'session_taps', 0 }, { '=', 'session_until', 0 } }, { noreturn = true })
            end
        end
        -- log.info('level: %s for user: %s', json.encode(level), json.encode(user))
        left = level.quota_period
        taps_left = level.quota_amount
    end

    local result = {
        id =  tostring(user.user_id),
        user_id = user.user_id,
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
        result.position = get_position_of(user.user_id, user.points)
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
    return to_user_info(user, { fetch_ref_user = true, fetch_position = false })
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
    local users = tomap(crud.select('users', { { '=', 'ref_user_id', user.user_id } }, { first = limit }))
    local results = {}
    for i = 1, #users do
        results[i] = to_user_info(users[i])
    end
    return results
end

function reverse(list)
    local reversed = {}
    for i = #list, 1, -1 do
        table.insert(reversed, list[i])
    end
    return reversed
end

---Get top 100 users (External)
---@param limit number
---@return userInfo[]
function get_top_users(limit)
    -- log.info('get top users')
    if type(limit) ~= 'number' then
        limit = 100
    end
    local users = tomap(crud.select('users', { { '>', 'points', 0 } }, { first = limit }))
    fiber.yield()
    local results = {}
    for i = 1, #users do
        results[i] = to_user_info(users[i])
    end
    return reverse(results)
end

---Get user around (External)
---@param user_id string
---@param limit number
---@return {above: userInfo[], below: userInfo[]}
function get_users_around_of(user_id, limit)
    -- log.info('get users around: %s', user_id)
    local user_info = get_user_info(user_id)
    if user_info == nil then
        error('user not found')
    end
    if type(limit) ~= 'number' then
        limit = 10
    end
    local above_res, err = crud.select(
        'users', 
        { { '>', 'position', { user_info.points, user_info.user_id } } },
        { first = limit }
    )
    if err ~= nil then
        error(err)
    end
    local above = reverse(tomap(above_res))
    local below_res, err  = crud.select(
        'users',
        { { '<', 'position', { user_info.points, user_info.user_id } } },
        { first = limit }
    )
    if err ~= nil then
        error(err)
    end
    local below = tomap(below_res)
    local results = { above = {}, below = {} }
    for i = 1, #above do
        results.above[i] = to_user_info(above[i])
    end
    for i = 1, #below do
        results.below[i] = to_user_info(below[i])
    end
    return results
end

---Get user position
---@param user_id number
---@param points number
---@return number
function get_position_of(user_id, points)
    return crud.count('users', { { '>=', 'position', { points, user_id } } })
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
            local user_info = get_user_info(user_id, { fetch_ref_user = true })
            if user_info == nil then
                results[i].error = 'user not found'
                return
            else
                results[i].user_info = user_info
                if user_info.session_left == 0 then
                    results[i].error = 'time quota exceeded'
                    return
                elseif user_info.session_taps_left <= 0 then
                    results[i].error = 'taps quota exceeded'
                    return
                else
                    local inserted_taps = 0
                    if user_info.session_taps_left < effective_taps then
                        effective_taps = user_info.session_taps_left
                    end
                    for j = 1, #taps do
                        local tap = taps[j]
                        if tap['x'] == nil or tap['y'] == nil then
                            results[i].error = 'invalid tap'
                            return
                        end
                        inserted_taps = inserted_taps + 1
                    end
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
                        crud.upsert(
                            'points_aggs',
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

                    if user_info.session_taps <= 0 then
                        table.insert(user_updates, { '=', 'session_until', now + user_info.level.quota_period })
                        results[i].user_info['session_until'] = now + user_info.level.quota_period
                    end

                    crud.update(
                        'users',
                        user_info.id,
                        user_updates,
                        { noreturn = true }
                    )

                    -- Referrals
                    -- 1 level
                    local ref1_id = user_info.ref_user_id
                    -- log.info('ref_user: %s', json.encode(user_info))
                    if ref1_id ~= nil then
                        local ref1_points = inserted_points * settings.referral_levels[1]
                        crud.update('users',
                            ref1_id,
                            { { '+', 'points', ref1_points } },
                            { noreturn = true }
                        )
                        -- 2 level
                        local ref2_id = user_info.ref_user.ref_user_id
                        local ref2_points = inserted_points * settings.referral_levels[2]
                        if ref2_id ~= nil then
                            crud.update('users',
                                ref2_id,
                                { { '+', 'points', ref2_points } },
                                { noreturn = true }
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
    end
    return results
end

function fixture()
    vshard.router.bootstrap()
    -- log.info("self-check users")
    local ref_user = create_anonymous_user()
    -- log.info("ref_user: %s", json.encode(ref_user))
    local user1 = get_or_create_user_from_tg('1', 'user1')
    user1 = get_or_create_user_from_tg('1', 'user1')
    local user2 = get_or_create_user_from_tg('2', 'user2', ref_user.user_id)
    local user3 = get_or_create_user_from_tg('3', 'user3', ref_user.user_id)
    local user4 = get_or_create_user_from_tg('4', 'user4')
    local user5 = get_or_create_user_from_tg('5', 'user5', user2.user_id)
    local user6 = get_or_create_user_from_tg('5', 'user5', ref_user.user_id)

    -- log.info("self-check taps")
    user2_taps = {}
    for i = 1, 6000 do
        table.insert(user2_taps, { x = 1, y = 1 })
    end
    register_taps({
        {
            user_id = user2.user_id,
            taps = user2_taps
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
end
