-- Emby 自动登录脚本 - 使用简化的注入方式
local auto_login_script = [[<script type="text/javascript" src="/autologin.js"></script>
<script type="text/javascript" defer src="/logout-hijack.js"></script>
<style>
button[data-id="changeuser"] {
    display: none;
}
</style>]]

-- 设置 Lua 模块搜索路径
package.path = package.path .. ";/usr/local/openresty/nginx/lua/?.lua"

ngx.shared.injected_script:set("auto_login", auto_login_script)

-- Base32 字符映射表（需要在验证密钥之前定义）
local base32_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
local base32_char_map = {}
for i = 1, #base32_chars do
    base32_char_map[string.sub(base32_chars, i, i)] = i - 1
end

-- TOTP 用户配置表：从环境变量读取
-- 环境变量格式：USER_TOTP_SECRETS='{"用户名1":"TOTP_SECRET1","用户名2":"TOTP_SECRET2"}'
-- 注意：密钥必须是16位 Base32 字符（A-Z, 2-7）
local user_totp_secrets = {}
local env_secrets = os.getenv("USER_TOTP_SECRETS")

if env_secrets and env_secrets ~= "" then
    local cjson = require("cjson")
    local ok, parsed = pcall(cjson.decode, env_secrets)
    if ok and parsed then
        -- 验证每个密钥必须是16位 Base32 字符
        local validated_secrets = {}
        for username, secret in pairs(parsed) do
            -- 移除空格并转换为大写
            local clean_secret = string.upper(string.gsub(secret or "", "%s", ""))
            -- 验证密钥长度必须是16个字符
            if #clean_secret == 16 then
                -- 验证是否只包含有效的 Base32 字符
                local valid = true
                for i = 1, #clean_secret do
                    local char = string.sub(clean_secret, i, i)
                    if not base32_char_map[char] then
                        valid = false
                        ngx.log(ngx.ERR, "[TOTP Config] Invalid Base32 character in secret for user: ", username)
                        break
                    end
                end
                if valid then
                    validated_secrets[username] = clean_secret
                else
                    ngx.log(ngx.ERR, "[TOTP Config] Invalid secret format for user: ", username, ", secret must be 16 Base32 characters")
                end
            else
                ngx.log(ngx.ERR, "[TOTP Config] Invalid secret length for user: ", username, ", expected 16 characters, got ", #clean_secret)
            end
        end
        user_totp_secrets = validated_secrets
        -- 统计用户数量
        local user_count = 0
        for _ in pairs(user_totp_secrets) do
            user_count = user_count + 1
        end
        ngx.log(ngx.INFO, "[TOTP Config] Loaded ", user_count, " user(s) from environment variable (16-character Base32 secrets)")
    else
        ngx.log(ngx.ERR, "[TOTP Config] Failed to parse USER_TOTP_SECRETS environment variable")
    end
else
    ngx.log(ngx.WARN, "[TOTP Config] USER_TOTP_SECRETS environment variable not set, using empty configuration")
end

-- 读取 SERVER_NAME 环境变量（必需）
local server_name = os.getenv("SERVER_NAME")
if not server_name or server_name == "" then
    ngx.log(ngx.ERR, "[NGINX Config] SERVER_NAME environment variable is required but not set!")
    error("SERVER_NAME environment variable is required but not set!")
else
    ngx.log(ngx.INFO, "[NGINX Config] SERVER_NAME loaded from environment variable: ", server_name)
end

-- 读取 EMBY_BACKEND 环境变量（必需）
local emby_backend = os.getenv("EMBY_BACKEND")
if not emby_backend or emby_backend == "" then
    ngx.log(ngx.ERR, "[EMBY Config] EMBY_BACKEND environment variable is required but not set!")
    error("EMBY_BACKEND environment variable is required but not set!")
else
    ngx.log(ngx.INFO, "[EMBY Config] EMBY_BACKEND loaded from environment variable: ", emby_backend)
end

-- 读取 EMBY_API_KEY 环境变量
local emby_api_key = os.getenv("EMBY_API_KEY")
if not emby_api_key or emby_api_key == "" then
    ngx.log(ngx.WARN, "[EMBY Config] EMBY_API_KEY environment variable not set")
else
    ngx.log(ngx.INFO, "[EMBY Config] EMBY_API_KEY loaded from environment variable")
end

-- Base32 解码函数
local function base32_decode(secret)
    secret = string.upper(string.gsub(secret, "%s", ""))
    
    -- 验证密钥长度必须是16个字符
    if #secret ~= 16 then
        error("TOTP secret must be exactly 16 Base32 characters, got " .. #secret)
    end
    
    local bits = 0
    local value = 0
    local result = {}
    
    for i = 1, #secret do
        local char = string.sub(secret, i, i)
        if char == "=" then break end
        
        local val = base32_char_map[char]
        if not val then
            error("Invalid Base32 character: " .. char)
        end
        
        value = value * 32 + val
        bits = bits + 5
        
        if bits >= 8 then
            local shift = bits - 8
            local byte_val = math.floor(value / (2 ^ shift))
            table.insert(result, string.char(byte_val))
            value = value % (2 ^ shift)
            bits = bits - 8
        end
    end
    
    return table.concat(result)
end

-- TOTP 生成函数
local function generate_totp(secret, time_step, digits, current_time)
    time_step = time_step or 30
    digits = digits or 6
    current_time = current_time or ngx.time()
    
    -- 验证密钥格式
    if not secret or type(secret) ~= "string" then
        error("TOTP secret must be a string")
    end
    
    local clean_secret = string.upper(string.gsub(secret, "%s", ""))
    if #clean_secret ~= 16 then
        error("TOTP secret must be exactly 16 Base32 characters, got " .. #clean_secret)
    end
    
    -- 解码 secret
    local secret_bytes = base32_decode(clean_secret)
    
    -- 计算时间计数器
    local counter = math.floor(current_time / time_step)
    
    -- 将计数器转换为 8 字节的大端序二进制
    local counter_bytes = ""
    for i = 7, 0, -1 do
        counter_bytes = counter_bytes .. string.char(math.floor(counter / (256 ^ i)) % 256)
    end
    
    -- 使用 HMAC-SHA1 生成哈希
    local hmac_result = ngx.hmac_sha1(secret_bytes, counter_bytes)
    
    -- 动态截取（Dynamic Truncation）
    local last_byte = string.byte(hmac_result, #hmac_result)
    local offset = (bit.band(last_byte, 0x0f) + 1)
    
    local code_bytes = string.sub(hmac_result, offset, offset + 3)
    local code = 0
    for i = 1, 4 do
        code = code * 256 + string.byte(code_bytes, i)
    end
    code = bit.band(code, 0x7fffffff)
    
    -- 模运算得到最终的 TOTP 码
    local totp_code = code % (10 ^ digits)
    
    -- 格式化为指定位数的字符串（左侧填充 0）
    return string.format("%0" .. digits .. "d", totp_code)
end

-- 在全局环境中存储函数和配置（供后续使用）
_G.user_totp_secrets = user_totp_secrets
_G.generate_totp = generate_totp
_G.emby_api_key = emby_api_key
_G.emby_backend = emby_backend
_G.server_name = server_name

-- 速率限制配置
_G.rate_limit_config = {
    max_requests_per_second = 100,  -- 每秒最多100次请求
    window_size = 1                    -- 时间窗口大小（秒）
}
