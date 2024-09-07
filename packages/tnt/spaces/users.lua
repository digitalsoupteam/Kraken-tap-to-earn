local uuid = require('uuid')
local json = require("json")
local log = require("log")

local users_space = {}

function users_space.init(box)
    box.schema.sequence.create('user_id_seq')
    local users = box.schema.create_space('users', { engine = 'vinyl' })
    users:format({
        { name = 'user_id',          type = 'integer' },
        { name = 'external_user_id', type = 'uuid' },
        { name = 'is_blocked',       type = 'boolean' },
        { name = 'nickname',         type = 'string' },
        { name = "ref_user_id",      type = "integer", is_nullable = true },
        { name = "wallet",           type = "string",  is_nullable = true },
        { name = 'taps',             type = 'number' },
        { name = "points",           type = "number" },
        { name = 'level',            type = 'number' },
        { name = 'bubbles',          type = 'number' },
        { name = 'tg_id',            type = 'string' },
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
    users:create_index('bubbles', { parts = { { 'bubbles' } }, unique = false })
    users:create_index('tg_id', { parts = { { 'tg_id' } }, unique = true })
    --
    users:create_index('position', { parts = { { 'points' }, { 'user_id' } }, unique = false })
end

--- Create new user
--- @param username string
--- @param ref_user_id number
--- @return number
function users_space.create(box, tg_id, username, ref_user_external_id, referral_initial_points)
    local user = nil
    box.atomic(function()
        local initial_points = 0

        local ref_user_id = users_space.find_refferal_id(box, ref_user_external_id)

        if ref_user_id ~= nil then
            initial_points = referral_initial_points
            box.space.users:update(
                { ref_user_id },
                { { '+', 'points', initial_points } }
            )
        end

        user = box.space.users:insert({
            box.NULL,
            uuid.new(),
            false,
            username,
            ref_user_id,
            nil,
            0,
            initial_points,
            1,
            0,
            tg_id
        })
    end)
    if user == nil then
        error('cant create user')
    end
    return user
end

-- Get user using uuid or number
--- @param user_id string|number
--- @return user | nil
function users_space.get(box, user_id)
    local user
    if type(user_id) == 'number' then
        user = box.space.users.index.user_id:get({ user_id })
    else
        local external_user_id = uuid.fromstr(user_id)
        user = box.space.users.index.external_user_id:get({ external_user_id })
    end
    -- if user == nil then
    --     return nil
    -- end
    return user
end

-- Get user using uuid or number
--- @param tg_id number
--- @return user | nil
function users_space.get_by_tg_id(box, tg_id)
    local user = box.space.users.index.tg_id:get({ tg_id })
    return user
end

-- Get user using uuid or number
--- @param user_id string|number
--- @return user | nil
function users_space.find_refferal_id(box, ref_user_external_id)
    local ref_user_id = nil
    if ref_user_external_id ~= nil then
        local ref_user = users_space.get(box, ref_user_external_id)
        if ref_user ~= nil then
            ref_user_id = ref_user.user_id
        end
    end
    return ref_user_id
end

--- Is user id exist
--- @param user_id string
--- @return boolean
function users_space.exist(box, user_id)
    local user = users_space.get_user(box, user_id)
    return user ~= nil
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
function users_space.update(box, user_id, params)
    log.info('update user: %s with %s', user_id, json.encode(params))
    local user = users_space.get(box, user_id)
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
    -- box.space.users:update({ user.user_id }, update)
    -- return get_user_info(user_id)
end

---Get top 100 Referred users (External)
---@param by_user_id string
---@param limit number
---@return userInfo[]
function users_space.get_top_referrals(box, by_user_id, limit)
    log.info('get top referrals: %s', by_user_id)
    if type(limit) ~= 'number' then
        limit = 100
    end
    local user = users_space.get(box, by_user_id)
    if user == nil then
        error('user not found')
    end
    local users = box.space.users.index.ref_user_id:select({ user.user_id }, { limit = limit, iterator = 'REQ' })
    return users
    -- local results = {}
    -- for i = 1, #users do
    --     results[i] = to_user_info(users[i]:tomap({ names_only = true }), {})
    -- end
    -- return results
end

---Get top 100 users (External)
---@param limit number
---@return userInfo[]
function users_space.get_top_users(box, limit)
    log.info('get top users')
    if type(limit) ~= 'number' then
        limit = 100
    end
    local users = box.space.users.index.points:select({}, { limit = limit, iterator = 'REQ' })
    return users
    -- local results = {}
    -- for i = 1, #users do
    --     results[i] = to_user_info(users[i]:tomap({ names_only = true }), {})
    -- end
    -- return results
end

---Get user around (External)
---@param user_id string
---@param limit number
---@return {above: userInfo[], below: userInfo[]}
function users_space.get_users_around_of(box, user_id, limit)
    log.info('get users around: %s', user_id)
    local user_info = users_space.get_user_info(user_id)
    if user_info == nil then
        error('user not found')
    end
    if type(limit) ~= 'number' then
        limit = 10
    end
    local above = box.space.users.index.position:select({ user_info.points, user_info.id },
        { limit = limit, iterator = 'GT' })
    local below = box.space.users.index.position:select({ user_info.points, user_info.id },
        { limit = limit, iterator = 'LT' })
    return { above = above, below = below }
    -- local results = { above = {}, below = {} }
    -- for i = 1, #above do
    --     results.above[i] = to_user_info(above[i]:tomap({ names_only = true }), {})
    -- end
    -- for i = 1, #below do
    --     results.below[i] = to_user_info(below[i]:tomap({ names_only = true }), {})
    -- end
    -- return results
end


---Get user position
---@param user_info userInfo
---@return number
function users_space.get_position_of(box, user_id, points)
    return box.space.users.index.points:count({ points, user_id }, { iterator = 'GE' })
end

return users_space
