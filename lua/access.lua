-- access.lua - 速率限制检查
require("auth_handler")

if not check_rate_limit() then
    ngx.exit(429)
end
