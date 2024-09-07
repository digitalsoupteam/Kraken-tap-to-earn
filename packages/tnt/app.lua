#!/usr/bin/env tarantool
---@diagnostic disable: lowercase-global
local uuid = require('uuid')
local log = require("log")
local ws = require("websocket")
local json = require("json")

local taps_space = require("spaces.taps")
local points_aggs_space = require("spaces.points_aggs")
local users_space = require("spaces.users")
local user_score_space = require("spaces.user_score")
local user_events_space = require("spaces.user_events")
local daily_bonus_space = require("spaces.daily_bonus")
local tg2user_space = require("spaces.tg2user")
local sessions_space = require("spaces.sessions")
local boost_v1_space = require("spaces.boost_v1")
local levels_space = require("spaces.levels")

local AGGREGATION_PERIODS = { 86400, 604800, 2592000, 7776000 }
local SECONDS_IN_DAY = 24 * 60 * 60

local settings = {
    referral_levels = {
        0.25,
        0.0625,
    },
    referral_initial_points = 20000,
    days_in_row_limit = 10,
    days_in_row_multiplier = 1.1
}
if settings.days_in_row_multiplier < 1 then
    error('days_in_row_multiplier must be >= 1')
end

log.cfg { format = 'json', level = 'verbose' }
box.cfg {}
box.once('schema', function()
    taps_space.init(box)
    points_aggs_space.init(box)
    users_space.init(box)
    user_score_space.init(box)
    user_events_space.init(box)
    daily_bonus_space.init(box)
    tg2user_space.init(box)
    sessions_space.init(box)
    boost_v1_space.init(box)
    levels_space.init(box)
end)


-- --- @alias levels {id: number, quota_period: number, quota_amount: number, calm_period: number}
-- --- @alias user {user_id: number, external_user_id: string, is_blocked: boolean, level: number, session_until: number, session_taps: number, taps: number, nickname: string, wallet: string}
-- --- @alias userInfo {id: number, user_id: string, is_blocked: boolean, level: levels, nickname: string, session_start: number, session_left: number, session_until: number, session_taps: number, session_taps_left: number, taps: number, calm_until: number, ref_user: userInfo | nil, ref_user_id: number, days_in_row: number, days: number, days_updated_at: number, points: number, wallet: string}

-- --- On user update trigger
-- --- @param old_user user
-- --- @param new_user user
-- function on_user_update(old_user, new_user)
--     local user = to_user_info(new_user:tomap({ names_only = true }), { fetch_ref_user = true, fetch_position = true })
--     broadcast(user)
-- end

-- box.space.users:on_replace(on_user_update)

-- local ws_peers = {}

-- function on_subscribe(peer)
--     for i = 1, #ws_peers do
--         if ws_peers[i] == peer then
--             return
--         end
--     end
--     table.insert(ws_peers, peer)
-- end

-- function on_unsubscribe(peer)
--     for i = 1, #ws_peers do
--         if ws_peers[i] == peer then
--             table.remove(ws_peers, i)
--             break
--         end
--     end
-- end

-- function broadcast(msg)
--     local payload = json.encode(msg)
--     for i = 1, #ws_peers do
--         log.info('broadcast: %s', payload)
--         ws_peers[i]:write(payload)
--     end
-- end

-- ws.server('ws://0.0.0.0:3000', function(ws_peer)
--     on_subscribe(ws_peer)
--     while true do
--         local msg = ws_peer:read()
--         if msg == nil or msg.opcode == nil then
--             on_unsubscribe(ws_peer)
--             break
--         end
--     end
-- end)



function get_or_create_user(tg_id, username, ref_user_external_id)
    local user = nil

    if username == nil then
        username = "unknown kraken"
    end

    if tg_id ~= nil then
        user = spaces_facade.get_user_by_tg(box, tg_id)
    end

    if user == nil then
        user = spaces_facade.create_user(box, tg_id, username, ref_user_external_id)
    end

    return user
end

-- -- user info from user item
-- -- @param user user
-- ---@param opts {fetch_ref_user?: boolean, fetch_position?: boolean} | nil
-- -- @return userInfo | nil
-- function to_user_info(user, opts)
--     local level = get_or_create_levels(user.level)
--     local is_blocked = user.is_blocked
--     local nickname = user.nickname
--     local now = os.time()
--     local left
--     local taps_left
--     local calm_period = 0
--     local calm_left = 0
--     local session_start = now

--     if now < user.session_until then
--         left = user.session_until - now
--         taps_left = level.quota_amount - user.session_taps
--         session_start = user.session_until - level.quota_period
--     elseif user.session_until > 0 and now < (user.session_until + level.calm_period) then
--         left = 0
--         taps_left = 0
--         calm_period = user.session_until + level.calm_period
--         calm_left = user.session_until + level.calm_period - now
--         session_start = user.session_until - level.quota_period
--     else
--         if user.session_taps > 0 then
--             user.session_taps = 0
--             user.session_until = 0
--             -- do not update ref_user
--             if type(opts) == 'table' and opts['fetch_ref_user'] ~= nil then
--                 box.space.users:update({ user.user_id }, { { '=', 'session_taps', 0 }, { '=', 'session_until', 0 } })
--             end
--         end
--         left = level.quota_period
--         taps_left = level.quota_amount
--     end

--     local result = {
--         id = user.user_id,
--         user_id = tostring(user.external_user_id),
--         is_blocked = is_blocked,
--         level = level,
--         nickname = nickname,
--         calm_until = calm_period,
--         calm_left = calm_left,
--         session_start = session_start,
--         session_left = left,
--         session_until = user.session_until,
--         session_taps = user.session_taps,
--         session_taps_left = taps_left,
--         taps = user.taps,
--         ref_user = nil,
--         ref_user_id = user.ref_user_id,
--         wallet = user.wallet,
--         points = user.points,
--         days = user.days,
--         days_in_row = user.days_in_row,
--         days_updated_at = user.days_updated_at,
--     }
--     if opts ~= nil and opts['fetch_position'] ~= nil then
--         result.position = get_position_of(user)
--     end
--     if opts ~= nil and opts['fetch_ref_user'] ~= nil and user.ref_user_id ~= nil then
--         result.ref_user = get_user_info(user.ref_user_id, {})
--     end
--     return result
-- end

-- ---Get user details (External)
-- ---@param user_id string | number
-- ---@return userInfo | nil
-- function get_user_details(user_id)
--     local user = get_user(user_id)
--     if user == nil then
--         return nil
--     end
--     return to_user_info(user, { fetch_ref_user = true, fetch_position = true })
-- end

-- ---Get user info
-- ---@param user_id string | number
-- ---@param opts {fetch_ref_user?: boolean, fetch_position?: boolean} | nil
-- ---@return userInfo | nil
-- function get_user_info(user_id, opts)
--     local user = get_user(user_id)
--     if user == nil then
--         return nil
--     end
--     return to_user_info(user, opts)
-- end


-- ---Validate taps batch item
-- ---@param batch {user_id: string, taps: {x: number, y: number}}[]
-- ---@return boolean
-- function validate_batch(batch)
--     for i = 1, #batch do
--         if type(batch[i]) ~= 'table' then
--             return false
--         end
--         if batch[i].user_id == nil then
--             return false
--         end
--         if batch[i].taps == nil then
--             return false
--         end
--         if #batch[i].taps == 0 then
--             return false
--         end
--         if type(batch[i].taps) ~= 'table' then
--             return false
--         end
--     end
--     return true
-- end

-- ---Register taps (External)
-- ---@param batch {user_id: string, taps: {x: number, y: number}}[]
-- ---@return {user_info: userInfo, error: nil}[]
-- function register_taps(batch)
--     log.info('register taps (%d)', #batch)
--     local results = {}
--     local now = os.time()
--     for i = 1, #batch do
--         results[i] = { nil, nil }
--         if validate_batch(batch) == false then
--             results[i].error = 'invalid batch item'
--         else
--             local user_id = batch[i].user_id
--             local taps = batch[i].taps
--             local effective_taps = #taps
--             local user_info = get_user_info(user_id, { fetch_ref_user = true, fetch_position = true })
--             if user_info == nil then
--                 results[i].error = 'user not found'
--             else
--                 results[i].user_info = user_info
--                 if user_info.session_left == 0 then
--                     results[i].error = 'time quota exceeded'
--                 elseif user_info.session_taps_left == 0 then
--                     results[i].error = 'taps quota exceeded'
--                 else
--                     local inserted_taps = 0
--                     if user_info.session_taps_left < effective_taps then
--                         effective_taps = user_info.session_taps_left
--                     end
--                     for j = 1, #taps do
--                         local tap = taps[j]
--                         if tap['x'] == nil or tap['y'] == nil then
--                             results[i].error = 'invalid tap'
--                             break
--                         end
--                         box.space.taps:insert({ box.NULL, user_info.id, now, tap['x'], tap['y'] })
--                         inserted_taps = inserted_taps + 1
--                     end
--                     box.atomic(function()
--                         local limited_days = user_info.days_in_row
--                         if limited_days > settings.days_in_row_limit then
--                             limited_days = settings.days_in_row_limit
--                         end
--                         local days_multiplier = limited_days * settings.days_in_row_multiplier
--                         local inserted_points = inserted_taps * days_multiplier
--                         local days = user_info.days
--                         local days_in_row = user_info.days_in_row
--                         local days_updated_at = user_info.days_updated_at

--                         for j = 1, #AGGREGATION_PERIODS do
--                             local period = AGGREGATION_PERIODS[j]
--                             local period_time = math.floor(now / period) * period
--                             box.space.points_aggs:upsert(
--                                 { user_info.id, period, period_time, inserted_points },
--                                 { { '+', 4, inserted_points } }
--                             )
--                         end

--                         local user_updates = {
--                             { '+', 'session_taps', inserted_taps },
--                             { '+', 'taps',         inserted_taps },
--                             { '+', 'points',       inserted_points },
--                         }

--                         if now > days_updated_at + SECONDS_IN_DAY then -- wait one day
--                             days = days + 1                            -- total counter

--                             if now > days_updated_at + SECONDS_IN_DAY * 2 then
--                                 days_in_row = 1               -- if more 2 days, reset to default
--                             else
--                                 days_in_row = days_in_row + 1 -- if less 2 days, endless increment
--                             end

--                             days_updated_at = now -- save checkpoint

--                             table.insert(user_updates, { '=', 'days', days })
--                             table.insert(user_updates, { '=', 'days_in_row', days_in_row })
--                             table.insert(user_updates, { '=', 'days_updated_at', days_updated_at })
--                         end

--                         if user_info.session_taps == 0 then
--                             table.insert(user_updates, { '=', 'session_until', now + user_info.level.quota_period })
--                             results[i].user_info['session_until'] = now + user_info.level.quota_period
--                         end

--                         box.space.users:update({ user_info.id }, user_updates)

--                         -- Referrals
--                         -- 1 level
--                         local ref1_id = user_info.ref_user_id
--                         if ref1_id ~= 0 then
--                             local ref1_points = inserted_points * settings.referral_levels[1]
--                             box.space.users:update(
--                                 { ref1_id },
--                                 { { '+', 'points', ref1_points } }
--                             )
--                             -- 2 level
--                             local ref2_id = user_info.ref_user.ref_user_id
--                             local ref2_points = inserted_points * settings.referral_levels[2]
--                             if ref2_id ~= 0 then
--                                 box.space.users:update(
--                                     { ref2_id },
--                                     { { '+', 'points', ref2_points } }
--                                 )
--                             end
--                         end
--                         results[i].user_info['session_taps'] = user_info['session_taps'] + inserted_taps
--                         results[i].user_info['taps'] = user_info['taps'] + inserted_taps
--                         results[i].user_info['points'] = user_info['points'] + inserted_points
--                         results[i].user_info['session_taps_left'] = user_info['session_taps_left'] - inserted_taps
--                     end)
--                 end
--             end
--         end
--     end
--     return results
-- end

-- box.once('fixtures', function()
--     log.info("self-check users")
--     local ref_user = create_anonymous_user()
--     box.space.users:update({ ref_user.id },
--         { { '=', 'external_user_id', uuid.fromstr('e92148b9-0c2c-4b15-869a-d248149d0f55') } })
--     ref_user.user_id = 'e92148b9-0c2c-4b15-869a-d248149d0f55'
--     local user1 = get_or_create_user_from_tg('1', 'user1')
--     local user2 = get_or_create_user_from_tg('2', 'user2', ref_user.user_id)
--     local user3 = get_or_create_user_from_tg('3', 'user3', ref_user.user_id)
--     local user4 = get_or_create_user_from_tg('4', 'user4')
--     local user5 = get_or_create_user_from_tg('5', 'user5', user2.user_id)
--     local user6 = get_or_create_user_from_tg('5', 'user5', ref_user.user_id)

--     log.info("self-check taps")
--     register_taps({
--         {
--             user_id = user2.user_id,
--             taps = {
--                 { x = 1, y = 1 },
--                 { x = 1, y = 1 },
--                 { x = 1, y = 1 },
--                 { x = 1, y = 1 },
--                 { x = 1, y = 1 },
--             }
--         },
--         {
--             user_id = user3.user_id,
--             taps = {
--                 { x = 1, y = 1 },
--                 { x = 1, y = 1 },
--                 { x = 1, y = 1 },
--             }
--         },
--         {
--             user_id = user4.user_id,
--             taps = {
--                 { x = 1, y = 1 },
--                 { x = 1, y = 1 }
--             }
--         },
--         {
--             user_id = user5.user_id,
--             taps = {
--                 { x = 1, y = 1 },
--                 { x = 1, y = 1 },
--                 { x = 1, y = 1 },
--             }
--         },
--     })

--     log.info("self-check top users")
--     get_top_users(100)

--     log.info("self-check top referrals")
--     get_top_referrals(ref_user.user_id, 100)

--     log.info("self-check users around")
--     get_users_around_of(ref_user.user_id, 100)
-- end)
-- -- vim:ts=4 ss=4 sw=4 expandtab
