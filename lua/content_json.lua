-- content_json.lua - /Users/AuthenticateByName 端点的JSON TOTP验证处理
require("auth_handler")

-- 处理 JSON 格式的 TOTP 验证流程
function handle_json_totp_auth()
    -- 读取请求体
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    
    if not body or body == "" then
        ngx.status = 400
        ngx.header["Content-Type"] = "application/json"
        ngx.say('{"error": "Missing request body"}')
        return false
    end
    
    ngx.log(ngx.INFO, "[JSON TOTP Auth] Original body: ", body)
    
    -- 解析 JSON 请求体
    local cjson = require("cjson")
    local ok, request_data = pcall(cjson.decode, body)
    
    if not ok or not request_data then
        ngx.status = 400
        ngx.header["Content-Type"] = "application/json"
        ngx.say('{"error": "Invalid JSON request body"}')
        return false
    end
    
    -- 提取 Username 和 Pw
    local username = request_data.Username
    local pw = request_data.Pw
    
    -- 验证必需字段
    if not username or username == "" then
        ngx.status = 400
        ngx.header["Content-Type"] = "application/json"
        ngx.say('{"error": "Username is required"}')
        return false
    end
    
    if not pw or pw == "" then
        ngx.status = 400
        ngx.header["Content-Type"] = "application/json"
        ngx.say('{"error": "Pw is required"}')
        return false
    end
    
    -- 验证 Pw 必须是6位数字
    if not string.match(pw, "^%d%d%d%d%d%d$") then
        ngx.status = 400
        ngx.header["Content-Type"] = "application/json"
        ngx.say('{"error": "Pw must be exactly 6 digits"}')
        return false
    end
    
    ngx.log(ngx.INFO, "[JSON TOTP Auth] Username: ", username, ", Pw: ", pw)
    
    -- 获取用户对应的 TOTP secret
    local user_secret = _G.user_totp_secrets[username]
    if not user_secret then
        ngx.status = 403
        ngx.header["Content-Type"] = "application/json"
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
        ngx.header["Content-Type"] = "application/json"
        ngx.say('{"error": "Invalid TOTP code"}')
        return false
    end
    
    ngx.log(ngx.INFO, "[JSON TOTP Auth] Submitted Pw: ", pw, ", Matched TOTP: ", matched_totp, 
            ", Window offset: ", time_window_offset)
    
    -- 检查 TOTP 是否已被使用（防重放攻击）
    -- 使用匹配的TOTP代码进行防重放检查
    if not check_totp_replay(username, matched_totp) then
        ngx.status = 403
        ngx.header["Content-Type"] = "application/json"
        ngx.say('{"error": "TOTP code already used. Please use a new code."}')
        return false
    end
    
    -- TOTP 验证通过，清空 Pw 字段，保留其他字段
    request_data.Pw = nil
    
    -- 转换回 JSON 格式的新请求体
    local new_body = cjson.encode(request_data)
    
    ngx.log(ngx.INFO, "[JSON TOTP Auth] TOTP verified, rewriting body to: ", new_body)
    
    -- 设置请求头为 JSON
    ngx.req.set_header("Content-Type", "application/json")
    ngx.req.clear_header("Content-Length")
    
    -- 设置新的请求体
    ngx.req.set_body_data(new_body)
    
    -- 转发到内部代理（不传递body参数，让ngx.location.capture自动使用修改后的请求体和所有原始请求头）
    local res = ngx.location.capture(
        "/emby_proxy_auth",
        { method = ngx.HTTP_POST }
    )
    
    if not res then
        ngx.status = 500
        ngx.header["Content-Type"] = "application/json"
        ngx.say('{"error": "Internal error: subrequest failed"}')
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

-- 执行处理
handle_json_totp_auth()
