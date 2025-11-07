-- =====================
-- 辅助函数
-- =====================

-- 为创建用户 API 设置请求头
function setup_create_user_headers()
    ngx.log(ngx.INFO, "[Emby Create User] ========== Setting up create user request headers ==========")
    
    -- 设置正确的 Content-Type 为 application/x-www-form-urlencoded（Emby API 要求）
    ngx.req.set_header("Content-Type", "application/x-www-form-urlencoded")
    ngx.log(ngx.INFO, "[Emby Create User] ✓ Content-Type header set to application/x-www-form-urlencoded")
    
    -- 从环境变量中读取 API key（统一使用 EMBY_API_KEY）
    local api_key = _G.emby_api_key
    if api_key and api_key ~= "" then
        -- 记录 API key 前缀（安全起见，不显示完整key）
        local api_key_prefix = string.sub(api_key, 1, 8) .. "..."
        ngx.log(ngx.INFO, "[Emby Create User] API key loaded from environment variable (prefix: ", api_key_prefix, ")")
        ngx.log(ngx.INFO, "[Emby Create User] Setting X-Emby-Token header with API key")
        ngx.req.set_header("X-Emby-Token", api_key)
        ngx.log(ngx.INFO, "[Emby Create User] ✓ X-Emby-Token header set successfully")
    else
        ngx.log(ngx.ERR, "[Emby Create User] EMBY_API_KEY environment variable not set - request will fail")
    end
    
    ngx.log(ngx.INFO, "[Emby Create User] Request headers setup completed")
end

-- 为设置用户策略 API 设置请求头和 URI
function setup_user_policy_headers()
    ngx.log(ngx.INFO, "[Emby Set User Policy] ========== Setting up user policy request headers and URI ==========")
    
    local user_id = ngx.var.arg_user_id
    
    -- 验证和记录 user_id
    if not user_id or user_id == "" then
        ngx.log(ngx.ERR, "[Emby Set User Policy] No user_id in query parameters - request will fail")
    else
        ngx.log(ngx.INFO, "[Emby Set User Policy] User ID received: ", user_id)
    end
    
    -- 从环境变量中读取 API key（统一使用 EMBY_API_KEY）
    local api_key = _G.emby_api_key
    if api_key and api_key ~= "" then
        -- 记录 API key 前缀（安全起见，不显示完整key）
        local api_key_prefix = string.sub(api_key, 1, 8) .. "..."
        ngx.log(ngx.INFO, "[Emby Set User Policy] API key loaded from environment variable (prefix: ", api_key_prefix, ")")
        ngx.log(ngx.INFO, "[Emby Set User Policy] Setting X-Emby-Token header for user: ", user_id)
        ngx.req.set_header("X-Emby-Token", api_key)
        ngx.log(ngx.INFO, "[Emby Set User Policy] ✓ X-Emby-Token header set successfully")
    else
        ngx.log(ngx.ERR, "[Emby Set User Policy] EMBY_API_KEY environment variable not set - request will fail")
    end
    
    -- 动态设置请求 URI
    if user_id and user_id ~= "" then
        local target_uri = "/Users/" .. user_id .. "/Policy"
        ngx.log(ngx.INFO, "[Emby Set User Policy] Setting request URI to: ", target_uri)
        ngx.req.set_uri(target_uri)
        ngx.log(ngx.INFO, "[Emby Set User Policy] ✓ Request URI set successfully")
    else
        ngx.log(ngx.ERR, "[Emby Set User Policy] Cannot set URI - user_id is missing or empty")
    end
    
    ngx.log(ngx.INFO, "[Emby Set User Policy] Request headers and URI setup completed")
end

-- 获取并设置注入脚本
function setup_injected_script()
    ngx.var.injected_script = ngx.shared.injected_script:get("auto_login") or ""
end
