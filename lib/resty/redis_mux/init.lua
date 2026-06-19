-- Redis connection multiplexer for ngx_lua cosocket API.
-- Shares a single TCP connection across all concurrent requests
-- within one nginx worker, using read/write-separated light threads.
--
-- Entry point: require "resty.redis_mux"
-- Returns module with .new(opts) factory, .ConnectionManager and .Client classes.

local type = type

-- Ensure ngx.semaphore is available (may be injected by resty.core
-- or provided as standalone ngx.semaphore module)
if not ngx.semaphore or not ngx.semaphore.new then
    pcall(require, "resty.core")
end
if not ngx.semaphore or not ngx.semaphore.new then
    local ok, sem_module = pcall(require, "ngx.semaphore")
    if ok and type(sem_module) == "table" and sem_module.new then
        ngx.semaphore = sem_module
    end
end
if not ngx.semaphore or not ngx.semaphore.new then
    error("ngx.semaphore is required for resty.redis_mux. "
        .. "Ensure lua-resty-core is installed and loaded.", 2)
end

local _M = {}
_M._VERSION = '0.1.0'

-- Load sub-modules
local manager = require "resty.redis_mux.manager"
local client = require "resty.redis_mux.client"

-- Exports
_M.connect_manager = manager
_M.client = client
_M.new = function(opts) return manager:new(opts) end

return _M
