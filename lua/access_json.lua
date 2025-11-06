-- access_json.lua - /Users/AuthenticateByName 端点的速率限制检查
require("auth_handler")

if not check_rate_limit() then
    ngx.exit(429)
end
