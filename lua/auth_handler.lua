-- =====================
-- 认证处理函数
-- =====================

-- 速率限制检查函数
function check_rate_limit()
    local rate_limit_dict = ngx.shared.rate_limit
    local config = _G.rate_limit_config
    local current_time = ngx.time()
    
    -- 速率限制：滑动窗口计数
    local window_key = "totp_rate_window_" .. math.floor(current_time)
    local count, err = rate_limit_dict:incr(window_key, 1)
    
    if err == "not found" then
        -- 键不存在，创建新键并设置为1
        local ok, set_err = rate_limit_dict:set(window_key, 1, config.window_size + 1)
        if not ok then
            ngx.log(ngx.ERR, "[Rate Limit] Failed to create counter: ", set_err)
        else
            count = 1
        end
    elseif err then
        ngx.log(ngx.ERR, "[Rate Limit] Failed to increment counter: ", err)
        -- 出错时允许请求通过（降级策略）
        count = nil
    end
    
    -- 记录计数日志用于调试
    if count then
        ngx.log(ngx.INFO, "[Rate Limit] Current count: ", count, ", Limit: ", config.max_requests_per_second)
    end
    
    -- 检查是否超过限制
    if count and count > config.max_requests_per_second then
        ngx.log(ngx.WARN, "[Rate Limit] Rate limit exceeded (", count, " > ", config.max_requests_per_second, ").")
        
        ngx.status = 429
        ngx.header["Content-Type"] = "application/json"
        ngx.say('{"error": "Too many requests. Rate limit exceeded."}')
        ngx.exit(429)
        return false
    end
    
    -- 清理旧的时间窗口（用于内存管理）
    local prev_window_key = "totp_rate_window_" .. math.floor(current_time - config.window_size)
    rate_limit_dict:delete(prev_window_key)
    
    return true
end

-- 检查 TOTP 是否已被使用（防重放攻击）
function check_totp_replay(username, totp_code)
    local used_totp_dict = ngx.shared.used_totp
    local totp_key = "totp_" .. username .. "_" .. totp_code
    
    -- 检查 TOTP 是否已被使用
    local used = used_totp_dict:get(totp_key)
    if used then
        ngx.log(ngx.WARN, "[TOTP Replay] TOTP code already used for user: ", username)
        return false
    end
    
    -- 标记 TOTP 为已使用，有效期90秒（三个时间窗口，确保前一个周期的代码也能被跟踪）
    local ttl = 90
    local ok, err = used_totp_dict:set(totp_key, 1, ttl)
    if not ok then
        ngx.log(ngx.ERR, "[TOTP Replay] Failed to mark TOTP as used: ", err)
        -- 如果无法标记，为了安全起见，拒绝请求
        return false
    end
    
    ngx.log(ngx.INFO, "[TOTP Replay] TOTP marked as used for user: ", username, ", valid for ", ttl, " seconds")
    return true
end

-- 验证 TOTP 代码（支持当前和前一个时间窗口）
-- 返回: (is_valid, matched_totp, time_window_offset)
-- is_valid: 是否验证通过
-- matched_totp: 匹配的TOTP代码
-- time_window_offset: 时间窗口偏移（0=当前窗口，-1=前一个窗口）
function verify_totp_with_previous_window(username, submitted_code, user_secret, time_step, digits, current_time)
    time_step = time_step or 30
    digits = digits or 6
    current_time = current_time or ngx.time()
    
    -- 计算当前时间窗口的 TOTP
    local current_totp = _G.generate_totp(user_secret, time_step, digits, current_time)
    
    -- 检查是否匹配当前时间窗口的 TOTP
    if submitted_code == current_totp then
        ngx.log(ngx.INFO, "[TOTP Verify] Code matches current window for user: ", username)
        return true, current_totp, 0
    end
    
    -- 计算前一个时间窗口的 TOTP
    local previous_time = current_time - time_step
    local previous_totp = _G.generate_totp(user_secret, time_step, digits, previous_time)
    
    -- 检查是否匹配前一个时间窗口的 TOTP
    if submitted_code == previous_totp then
        ngx.log(ngx.INFO, "[TOTP Verify] Code matches previous window for user: ", username)
        return true, previous_totp, -1
    end
    
    -- 都不匹配
    ngx.log(ngx.WARN, "[TOTP Verify] Code does not match current or previous window for user: ", username, 
            ", submitted: ", submitted_code, ", current: ", current_totp, ", previous: ", previous_totp)
    return false, nil, nil
end

-- 检查是否跳过 TOTP 验证（Emby Web 客户端）
function should_skip_totp()
    local args = ngx.var.args or ""
    
    if args ~= "" then
        -- 解析查询参数
        for pair in string.gmatch(args, "[^&]+") do
            local key, value = string.match(pair, "^([^=]+)=(.+)$")
            if key and value then
                key = ngx.unescape_uri(key)
                value = ngx.unescape_uri(value)
                
                -- 检查 X-Emby-Client=Emby Web (URL 解码后 + 会变成空格)
                if key == "X-Emby-Client" and value == "Emby Web" then
                    return true
                end
            end
        end
    end
    
    return false
end

-- 处理 Emby Web 客户端认证
function handle_emby_web_auth()
    ngx.log(ngx.INFO, "[Emby Web] Detected Emby Web client, fetching user info from /oauth2/userinfo")
    
    -- 调用内部请求获取用户信息
    local userinfo_res = ngx.location.capture("/oauth2/userinfo", {
        method = ngx.HTTP_GET
    })
    
    if not userinfo_res or userinfo_res.status ~= 200 then
        local status_msg = userinfo_res and tostring(userinfo_res.status) or "nil"
        ngx.log(ngx.ERR, "[Emby Web] Failed to fetch user info, status: ", status_msg)
        
        -- 如果是 401 未授权，返回 401 状态码通知客户端需要进行 OAuth2 登录
        if userinfo_res and userinfo_res.status == 401 then
            ngx.log(ngx.INFO, "[Emby Web] Received 401 from /oauth2/userinfo, returning 401 to client")
            ngx.status = 401
            return false
        end
        
        ngx.status = 403
        ngx.say('{"error": "Failed to get user information"}')
        return false
    end
    
    ngx.log(ngx.INFO, "[Emby Web] User info response: ", userinfo_res.body)
    
    -- 解析 JSON 响应，提取 user 字段
    local cjson = require("cjson")
    local ok, userinfo = pcall(cjson.decode, userinfo_res.body)
    
    if not ok or not userinfo then
        ngx.log(ngx.ERR, "[Emby Web] Failed to parse user info JSON")
        ngx.status = 500
        ngx.say('{"error": "Failed to parse user information"}')
        return false
    end
    
    local username = userinfo.user
    if not username or username == "" then
        ngx.log(ngx.ERR, "[Emby Web] User field not found in user info response")
        ngx.status = 403
        ngx.say('{"error": "User information not available"}')
        return false
    end
    
    ngx.log(ngx.INFO, "[Emby Web] Extracted username: ", username)
    
    -- 使用提取的用户名构建请求体
    local fixed_body = "Username=" .. ngx.escape_uri(username)
    ngx.log(ngx.INFO, "[Emby Web] Using extracted username, body: ", fixed_body)
    
    -- 设置请求头
    ngx.req.set_header("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8")
    ngx.req.clear_header("Content-Length")
    
    -- 读取并丢弃原始请求体（如果需要）
    ngx.req.read_body()
    
    -- 设置新的请求体
    ngx.req.set_body_data(fixed_body)
    
    -- 转发到内部代理
    local res = ngx.location.capture(
        "/emby_proxy_auth",
        { method = ngx.HTTP_POST, body = fixed_body }
    )
    
    if not res then
        ngx.status = 500
        ngx.say("Internal error: subrequest failed")
        return false
    end
    
    -- 如果 emby 返回 401，尝试创建用户后重试
    if res.status == 401 then
        local create_result = create_emby_user(username, fixed_body)
        if not create_result then
            return false
        end
        res = create_result
    end
    
    -- 输出响应头与内容
    ngx.status = res.status
    for k, v in pairs(res.header) do
        if k:lower() ~= "transfer-encoding" then
            ngx.header[k] = v
        end
    end
    ngx.say(res.body)
    return true
end

-- 创建 Emby 用户
function create_emby_user(username, original_body)
    ngx.log(ngx.INFO, "[Emby Web] Received 401 from emby, attempting to create user: ", username)
    
    -- 检查 EMBY_API_KEY 是否存在
    if not _G.emby_api_key or _G.emby_api_key == "" then
        ngx.log(ngx.ERR, "[Emby Web] EMBY_API_KEY not configured, cannot create user")
        ngx.status = 403
        ngx.say('{"error": "Server configuration error: API key not available"}')
        return false
    end
    
    -- 记录 API key 前缀（安全起见，不显示完整key）
    local api_key_prefix = string.sub(_G.emby_api_key, 1, 8) .. "..."
    ngx.log(ngx.INFO, "[Emby Web] EMBY_API_KEY is configured (prefix: ", api_key_prefix, ")")
    
    local cjson = require("cjson")
    
    -- =====================
    -- 第一步：创建用户（原子性操作开始）
    -- =====================
    ngx.log(ngx.INFO, "[Emby Web] ========== Starting user creation process ==========")
    ngx.log(ngx.INFO, "[Emby Web] Target username: ", username)
    
    -- Emby API 需要 application/x-www-form-urlencoded 格式
    local user_creation_body = "name=" .. ngx.escape_uri(username)
    ngx.log(ngx.INFO, "[Emby Web] Creating user with request body: ", user_creation_body)
    ngx.log(ngx.INFO, "[Emby Web] Request URL: /emby_create_user")
    ngx.log(ngx.INFO, "[Emby Web] Request method: POST")
    ngx.log(ngx.INFO, "[Emby Web] API key prefix in query: ", api_key_prefix)
    
    local create_user_res = ngx.location.capture(
        "/emby_create_user",
        {
            method = ngx.HTTP_POST,
            body = user_creation_body,
            args = "api_key=" .. ngx.escape_uri(_G.emby_api_key)
        }
    )
    
    if not create_user_res then
        ngx.log(ngx.ERR, "[Emby Web] User creation subrequest failed - subrequest returned nil")
        ngx.status = 500
        ngx.say('{"error": "Failed to create user (subrequest error)"}')
        return false
    end
    
    ngx.log(ngx.INFO, "[Emby Web] User creation response received - Status: ", create_user_res.status)
    ngx.log(ngx.INFO, "[Emby Web] User creation response body: ", create_user_res.body)
    
    if create_user_res.status ~= 200 then
        ngx.log(ngx.ERR, "[Emby Web] User creation failed with status: ", create_user_res.status, ", response body: ", create_user_res.body)
        ngx.status = 500
        ngx.say('{"error": "Failed to create user in emby"}')
        return false
    end
    
    ngx.log(ngx.INFO, "[Emby Web] ✓ User created successfully (Status: 200)")
    
    -- 从创建用户的响应中提取 Id
    ngx.log(ngx.INFO, "[Emby Web] ========== Extracting user ID from response ==========")
    ngx.log(ngx.INFO, "[Emby Web] Starting JSON parsing of user creation response")
    
    local ok_parse, user_data = pcall(cjson.decode, create_user_res.body)
    if not ok_parse or not user_data or type(user_data) ~= "table" then
        ngx.log(ngx.ERR, "[Emby Web] Failed to decode user creation response JSON - parse error: ", ok_parse, ", response body: ", create_user_res.body)
        ngx.status = 500
        ngx.say('{"error": "Failed to decode user creation response JSON"}')
        return false
    end
    
    ngx.log(ngx.INFO, "[Emby Web] JSON parsing successful, user data type: ", type(user_data))
    ngx.log(ngx.INFO, "[Emby Web] Full user data: ", cjson.encode(user_data))

    -- 检查 Id 字段
    if not user_data.Id or type(user_data.Id) ~= "string" or #user_data.Id == 0 then
        ngx.log(ngx.ERR, "[Emby Web] Missing or empty Id in user creation response - Id type: ", type(user_data.Id), ", Id value: ", tostring(user_data.Id), ", full response: ", create_user_res.body)
        ngx.status = 500
        ngx.say('{"error": "Failed to extract user Id from creation response"}')
        return false
    end
    
    local user_id = user_data.Id
    ngx.log(ngx.INFO, "[Emby Web] ✓ Successfully extracted user Id: ", user_id, " for username: ", username)
    
    -- =====================
    -- 第二步：设置用户策略（原子性操作继续）
    -- =====================
    ngx.log(ngx.INFO, "[Emby Web] ========== Starting user policy setup ==========")
    ngx.log(ngx.INFO, "[Emby Web] Target user ID: ", user_id)
    
    local policy_config = {
        EnableAllFolders = false,
        EnableUserPreferenceAccess = false,
        EnableMediaConversion = false,
        AllowCameraUpload = false,
        EnableSharedDeviceControl = false,
        IsHidden = true,
        IsHiddenRemotely = true,
        IsHiddenFromUnusedDevices = true
    }
    local policy_body = cjson.encode(policy_config)
    
    ngx.log(ngx.INFO, "[Emby Web] Policy configuration: ", policy_body)
    ngx.log(ngx.INFO, "[Emby Web] Request URL: /emby_set_user_policy")
    ngx.log(ngx.INFO, "[Emby Web] Request method: POST")
    ngx.log(ngx.INFO, "[Emby Web] Query parameters: user_id=", user_id, "&api_key=", api_key_prefix)
    
    local policy_res = ngx.location.capture(
        "/emby_set_user_policy",
        {
            method = ngx.HTTP_POST,
            body = policy_body,
            args = "user_id=" .. ngx.escape_uri(user_id) .. "&api_key=" .. ngx.escape_uri(_G.emby_api_key)
        }
    )
    
    if not policy_res then
        ngx.log(ngx.ERR, "[Emby Web] User policy setting subrequest failed - subrequest returned nil - ABORTING (user creation succeeded but policy setting failed)")
        ngx.status = 500
        ngx.say('{"error": "Failed to set user policy - user creation aborted due to policy configuration failure"}')
        return false
    end
    
    ngx.log(ngx.INFO, "[Emby Web] Policy setting response received - Status: ", policy_res.status)
    if policy_res.body and policy_res.body ~= "" then
        ngx.log(ngx.INFO, "[Emby Web] Policy setting response body: ", policy_res.body)
    else
        ngx.log(ngx.INFO, "[Emby Web] Policy setting response body: (empty)")
    end
    
    if policy_res.status ~= 204 then
        ngx.log(ngx.ERR, "[Emby Web] User policy setting failed with status: ", policy_res.status, ", response body: ", policy_res.body, " - ABORTING")
        ngx.status = 500
        ngx.say('{"error": "Failed to set user policy - operation incomplete"}')
        return false
    end
    
    ngx.log(ngx.INFO, "[Emby Web] ✓ User policy set successfully (Status: 204)")
    ngx.log(ngx.INFO, "[Emby Web] ========== User creation and policy setup completed ==========")
    ngx.log(ngx.INFO, "[Emby Web] ✓ User created and policy set successfully - proceeding with authentication")
    
    -- =====================
    -- 两个操作都成功，继续转发认证请求
    -- =====================
    local res = ngx.location.capture(
        "/emby_proxy_auth",
        { method = ngx.HTTP_POST, body = original_body }
    )
    
    if not res then
        ngx.status = 500
        ngx.say("Internal error: subrequest failed on retry")
        return false
    end
    
    return res
end

-- 处理 TOTP 验证流程
function handle_totp_auth()
    -- 读取请求体
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    
    if not body then
        ngx.status = 400
        ngx.say('{"error": "Missing request body"}')
        return false
    end
    
    ngx.log(ngx.INFO, "[TOTP Auth] Original body: ", body)
    
    -- 解析请求体：格式必须为 "Username={不限制}&Pw={必须是6位数字}"
    local username = nil
    local pw = nil
    
    -- 解析 URL 编码的表单数据
    for pair in string.gmatch(body, "[^&]+") do
        local key, value = string.match(pair, "^([^=]+)=(.+)$")
        if key and value then
            -- URL 解码
            key = ngx.unescape_uri(key)
            value = ngx.unescape_uri(value)
            
            if key == "Username" then
                username = value
            elseif key == "Pw" then
                pw = value
            end
        end
    end
    
    -- 验证格式
    if not username or username == "" then
        ngx.status = 400
        ngx.say('{"error": "Username is required"}')
        return false
    end
    
    if not pw or pw == "" then
        ngx.status = 400
        ngx.say('{"error": "Pw is required"}')
        return false
    end
    
    -- 验证 Pw 必须是6位数字
    if not string.match(pw, "^%d%d%d%d%d%d$") then
        ngx.status = 400
        ngx.say('{"error": "Pw must be exactly 6 digits"}')
        return false
    end
    
    ngx.log(ngx.INFO, "[TOTP Auth] Username: ", username, ", Pw: ", pw)
    
    -- 获取用户对应的 TOTP secret
    local user_secret = _G.user_totp_secrets[username]
    if not user_secret then
        ngx.status = 403
        ngx.say('{"error": "User not configured for TOTP"}')
        return false
    end
    
    -- 计算当前时间窗口（30秒）的 TOTP
    local current_time = ngx.time()
    local time_step = 30
    
    -- 验证提交的 Pw 是否匹配当前或前一个时间窗口的 TOTP
    local is_valid, matched_totp, time_window_offset = verify_totp_with_previous_window(
        username, pw, user_secret, time_step, 6, current_time
    )
    
    if not is_valid then
        ngx.status = 403
        ngx.say('{"error": "Invalid TOTP code"}')
        return false
    end
    
    ngx.log(ngx.INFO, "[TOTP Auth] Submitted Pw: ", pw, ", Matched TOTP: ", matched_totp, 
            ", Window offset: ", time_window_offset)
    
    -- 检查 TOTP 是否已被使用（防重放攻击）
    -- 使用匹配的TOTP代码进行防重放检查
    if not check_totp_replay(username, matched_totp) then
        ngx.status = 403
        ngx.say('{"error": "TOTP code already used. Please use a new code."}')
        return false
    end
    
    -- TOTP 验证通过，重写请求体为只有 Username
    local new_body = "Username=" .. ngx.escape_uri(username)
    
    ngx.log(ngx.INFO, "[TOTP Auth] TOTP verified, rewriting body to: ", new_body)
    
    -- 设置请求头
    ngx.req.set_header("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8")
    ngx.req.clear_header("Content-Length")
    
    -- 设置新的请求体
    ngx.req.set_body_data(new_body)
    
    -- 转发到内部代理
    local res = ngx.location.capture(
        "/emby_proxy_auth",
        { method = ngx.HTTP_POST, body = new_body }
    )
    
    if not res then
        ngx.status = 500
        ngx.say("Internal error: subrequest failed")
        return false
    end
    
    -- 输出响应头与内容
    ngx.status = res.status
    for k, v in pairs(res.header) do
        if k:lower() ~= "transfer-encoding" then
            ngx.header[k] = v
        end
    end
    ngx.say(res.body)
    return true
end
