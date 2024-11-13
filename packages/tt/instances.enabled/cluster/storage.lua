#!/usr/bin/env tarantool
---@diagnostic disable: lowercase-global
local uuid = require("uuid")
local log = require("log")
local fiber = require("fiber")
local ws = require("websocket")
local json = require("json")
local sync = require("sync")


local AGGREGATION_PERIODS = { 86400, 604800, 2592000, 7776000 }
local SECONDS_IN_DAY = 24 * 60 * 60


log.cfg { format = 'json', level = 'verbose' }
box.cfg {
    txn_isolation = 'read-committed',
    readahead = 64 * 1024,
    -- readahead = 1 * 1024 * 1024,
}

box.once('schema', function()
    if box.info.ro then
        return
    end

    local points_aggs = box.schema.create_space('points_aggs', { engine = 'memtx' })
    points_aggs:format({
        { name = 'user_id',   type = 'uuid' },
        { name = 'bucket_id', type = 'number' },
        { name = 'period',    type = 'number' }, -- 86400
        { name = 'timestamp', type = 'number' }, -- now() // 86400 * 86400
        { name = 'count',     type = 'number' },
    })
    points_aggs:create_index('pk', { parts = { { 'user_id' }, { 'period' }, { 'timestamp' } }, unique = true })
    points_aggs:create_index('periods', { parts = { { 'user_id' }, { 'period' } }, unique = false })
    points_aggs:create_index('user_id', { parts = { { 'user_id' } }, unique = false })
    points_aggs:create_index('bucket_id', { parts = { { 'bucket_id' } }, unique = false, type = 'tree' })

    local users = box.schema.create_space('users', { engine = 'memtx' })
    users:format({
        { name = 'user_id',         type = 'uuid' },
        { name = 'bucket_id',       type = 'number' },
        { name = 'is_blocked',      type = 'boolean' },
        { name = 'level',           type = 'number' },
        { name = 'session_taps',    type = 'number' },
        { name = 'session_until',   type = 'number' },
        { name = 'taps',            type = 'number' },
        { name = 'nickname',        type = 'string' },
        { name = "ref_user_id",     type = "uuid",   is_nullable = true },
        { name = "wallet",          type = "string", is_nullable = true },
        { name = "points",          type = "number" },
        { name = "days",            type = "number" },
        { name = "days_in_row",     type = "number" },
        { name = "days_updated_at", type = "number" },
    })
    users:create_index('user_id',
        { parts = { { 'user_id' } }, unique = true })
    users:create_index('wallet', {
        parts = {
            { field = 'wallet', exclude_null = true, is_nullable = true },
        },
        unique = true,
    })
    users:create_index('ref_user_id',
        { parts = { { 'ref_user_id', exclude_null = true }, { 'points' } }, unique = false })
    users:create_index('taps', { parts = { { 'taps' } }, unique = false })
    users:create_index('points', { parts = { { 'points' } }, unique = false })
    users:create_index('position', { parts = { { 'points' }, { 'user_id' } }, unique = false })
    users:create_index('bucket_id', { parts = { { 'bucket_id' } }, unique = false, type = 'tree' })

    local tg2user = box.schema.create_space('tg2user', { engine = 'memtx' })
    tg2user:format({
        { name = 'tg_id',     type = 'string' },
        { name = 'bucket_id', type = 'number' },
        { name = 'user_id',   type = 'uuid' },
    })
    tg2user:create_index('pk', { parts = { { 'tg_id' } }, unique = true })
    tg2user:create_index('user_id', { parts = { { 'user_id' } }, unique = true })
    tg2user:create_index('bucket_id', { parts = { { 'bucket_id' } }, unique = false, type = 'tree' })

    local sessions = box.schema.create_space('sessions', { engine = 'memtx' })
    sessions:format({
        { name = 'session_id', type = 'uuid' },
        { name = 'user_id',    type = 'uuid' },
        { name = 'bucket_id',  type = 'number' },
        { name = 'timestamp',  type = 'number' },
    })
    sessions:create_index('pk', { parts = { { 'session_id' }, { 'user_id' } }, unique = true })
    sessions:create_index('bucket_id', { parts = { { 'bucket_id' } }, unique = false, type = 'tree' })

    local levels = box.schema.create_space('levels', { engine = 'memtx' })
    levels:format({
        { name = 'level',        type = 'number' },
        { name = 'bucket_id',    type = 'number' },
        { name = 'quota_period', type = 'number' },
        { name = 'quota_amount', type = 'number' },
        { name = 'calm_period',  type = 'number' },
    })
    levels:create_index('pk', { parts = { { 'level' } }, unique = true })
    levels:create_index('bucket_id', { parts = { { 'bucket_id' } }, unique = false, type = 'tree' })
end)
