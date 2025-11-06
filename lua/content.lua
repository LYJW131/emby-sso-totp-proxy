-- content.lua - 认证请求处理
require("auth_handler")

-- 首先检查请求体中是否包含 TOTP 码（优先处理 TOTP 认证）
-- 读取请求体检查是否有 6 位数字的 Pw 字段
ngx.req.read_body()
local body = ngx.req.get_body_data()

local has_totp_code = false
if body and body ~= "" then
    -- 解析请求体，查找 Pw 字段是否为 6 位数字
    for pair in string.gmatch(body, "[^&]+") do
        local key, value = string.match(pair, "^([^=]+)=(.+)$")
        if key and value then
            key = ngx.unescape_uri(key)
            value = ngx.unescape_uri(value)
            
            -- 如果找到 Pw 字段且是 6 位数字，说明是 TOTP 认证请求
            if key == "Pw" and string.match(value, "^%d%d%d%d%d%d$") then
                has_totp_code = true
                ngx.log(ngx.INFO, "[Auth Router] Detected TOTP code in request body, using TOTP auth flow")
                break
            end
        end
    end
end

-- 优先级：如果有 TOTP 码，始终使用 TOTP 流程；否则检查是否为 Emby Web 客户端
if has_totp_code then
    -- 有 TOTP 码，走 TOTP 验证流程
    handle_totp_auth()
elseif should_skip_totp() then
    -- 没有 TOTP 码，且是 Emby Web 客户端，走 OAuth2 流程
    handle_emby_web_auth()
else
    -- 默认走 TOTP 流程（如果没有提供 Pw，会在 handle_totp_auth 中返回错误）
    handle_totp_auth()
end
