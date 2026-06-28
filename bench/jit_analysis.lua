---@diagnostic disable: need-check-nil
-- JIT behavior analysis script for resty.redis_mux
-- Usage: resty -I lib bench/jit_analysis.lua

local jit = require("jit")
local jit_v = require("jit.v")
local redis_mux = require("resty.redis_mux")
local semaphore_new = ngx.semaphore.new
local timer_at = ngx.timer.at
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local ngx_say = ngx.say

local jit_log_path = "bench/jit_v_output.log"
jit_v.on(jit_log_path)

ngx_say("[*] JIT verbose mode enabled -> bench/jit_v_output.log")

----------------------------------------------------------------------
-- Create and connect manager
----------------------------------------------------------------------

local mgr, err = redis_mux.new({
    host = "127.0.0.1",
    port = 6379,
    capacity = 50,
    connect_timeout = 3000,
    send_timeout = 3000,
    read_timeout = 3000,
})
if not mgr then
    ngx_log(ngx_ERR, "failed to create manager: ", err)
    jit_v.off()
    return
end

local ok, err = mgr:connect()
if not ok then
    ngx_log(ngx_ERR, "failed to connect: ", err)
    jit_v.off()
    return
end

ngx.sleep(0.2)
ngx_say("[*] Manager connected to 127.0.0.1:6379")

----------------------------------------------------------------------
-- Completion tracking
----------------------------------------------------------------------

local total_timers = 10
local done_sem = semaphore_new(0)
local completed = 0

----------------------------------------------------------------------
-- Group A: Basic SET/GET (timers 1-4)
----------------------------------------------------------------------

for i = 1, 4 do
    timer_at(0, function(premature)
        local ok, err = pcall(function()
            local client = mgr:get_client()
            for j = 1, 1000 do
                local key = "bench:a:" .. i .. ":" .. j
                client:set(key, "value_" .. j)
                client:get(key)
            end
        end)
        if not ok then
            ngx_log(ngx_ERR, "timer A-", i, " error: ", err)
        end
        done_sem:post(1)
    end)
end

----------------------------------------------------------------------
-- Group B: Mixed SET/GET/INCR/LPUSH (timers 5-7)
----------------------------------------------------------------------

for i = 5, 7 do
    timer_at(0, function(premature)
        local ok, err = pcall(function()
            local client = mgr:get_client()
            for j = 1, 2000 do
                client:set("bench:b:" .. i .. ":" .. j, j)
                client:get("bench:b:" .. i .. ":" .. j)
                client:incr("bench:counter:" .. i)
                client:lpush("bench:list:" .. i, "item_" .. j)
            end
        end)
        if not ok then
            ngx_log(ngx_ERR, "timer B-", i, " error: ", err)
        end
        done_sem:post(1)
    end)
end

----------------------------------------------------------------------
-- Group C: Pipeline mode (timers 8-10)
----------------------------------------------------------------------

for i = 8, 10 do
    timer_at(0, function(premature)
        local ok, err = pcall(function()
            local client = mgr:get_client()
            for j = 1, 1000 do
                client:init_pipeline(10)
                for k = 1, 10 do
                    client:set("bench:c:" .. i .. ":" .. j .. ":" .. k, "v" .. k)
                end
                client:commit_pipeline()
            end
        end)
        if not ok then
            ngx_log(ngx_ERR, "timer C-", i, " error: ", err)
        end
        done_sem:post(1)
    end)
end

----------------------------------------------------------------------
-- Wait for all timers
----------------------------------------------------------------------

ngx_say("[*] Waiting for ", total_timers, " timers to complete ...")

for i = 1, total_timers do
    local ok, err = done_sem:wait(120)
    if not ok then
        ngx_log(ngx_ERR, "semaphore wait failed: ", err)
    end
    completed = completed + 1
end

----------------------------------------------------------------------
-- Cleanup
----------------------------------------------------------------------

mgr:shutdown()
jit_v.off()

ngx_say("[*] All ", completed, "/", total_timers, " timers done.")
ngx_say("[*] JIT log written to bench/jit_v_output.log")
