/**
 * Emby 自动登录脚本
 * 支持多种备份机制确保在登录页面时自动登录
 */

(function () {
    'use strict';

    // 检查是否已认证 - 查看 localStorage 中的有效认证令牌
    function isAuthenticated() {
        try {
            var serverCreds = localStorage.getItem("servercredentials3");
            if (serverCreds) {
                var parsed = JSON.parse(serverCreds);
                if (parsed && parsed.Servers && parsed.Servers.length > 0) {
                    var users = parsed.Servers[0].Users;
                    if (users && users.length > 0 && users[0].AccessToken) {
                        return true;
                    }
                }
            }
        } catch (e) {
            console.error("[AutoLogin] Error checking authentication:", e);
        }
        return false;
    }

    // 检查是否在登录页面
    function isOnLoginPage() {
        var hash = window.location.hash || '';
        var isManualLogin = hash.indexOf('manuallogin') !== -1;
        var isStartup = hash.indexOf('startup') !== -1;
        return isManualLogin || isStartup;
    }

    // 检查是否是初始状态（没有路由hash或只有 /web）
    function isInitialState() {
        var hash = window.location.hash || '';
        return !hash || hash === '' || hash === '#!/' || hash === '#!/web';
    }

    // 执行自动登录
    function doLogin() {
        // 防止重复登录
        if (login_completed || redirecting_to_oauth) {
            console.log("[AutoLogin] Login already in progress or completed, skipping");
            return false;
        }

        if (!window.ApiClient || typeof window.ApiClient.authenticateUserByName !== "function") {
            return false;
        }

        console.log("[AutoLogin] Attempting login...");

        // 标记登录已开始，防止其他检查再次触发
        login_completed = true;

        window.ApiClient.authenticateUserByName(
            "Save your pathetic attempts.",
            "You'll sooner find a unicorn riding a skateboard than figure out my password."
        ).then(function (result) {
            console.log("[AutoLogin] ✓ Login successful");
            window.ApiClient.ensureWebSocket();

            // 停止所有检查间隔
            clearAllIntervals();

            // 添加短暂延迟确保认证令牌已保存到 localStorage
            setTimeout(function () {
                console.log("[AutoLogin] Redirecting to home page");
                // 使用 hash 方式导航到首页，这是 Emby 正确的导航方式
                window.location.hash = "#!/home";

                // 触发 PopStateEvent 事件
                window.dispatchEvent(new PopStateEvent('popstate', { state: { path: '/web#!/home' } }));

                // 等待1ms后再次触发
                setTimeout(function () {
                    window.dispatchEvent(new PopStateEvent('popstate', { state: { path: '/web#!/home' } }));
                }, 1);
            }, 50);
        }).catch(function (error) {
            // 重置登录完成标志，允许重试
            login_completed = false;

            console.error("[AutoLogin] ✗ Login failed:", error);

            // 如果已经在重定向中，不处理后续错误
            if (redirecting_to_oauth) {
                console.log("[AutoLogin] Already redirecting to OAuth, ignoring further errors");
                return;
            }

            // 详细的 401 检测日志
            console.log("[AutoLogin] Error details - status:", error.status, "statusCode:", error.statusCode, "ok:", error.ok);

            // 检查是否是 401 未授权错误（多种方式检查）
            var is_401 = (error && error.status === 401) ||
                (error && error.statusCode === 401) ||
                (error && error.ok === false && error.status === 401);

            if (is_401) {
                console.log("[AutoLogin] ✓ Detected 401 Unauthorized, redirecting to OAuth2 sign in");
                redirecting_to_oauth = true;
                clearAllIntervals();
                // 使用 replace 而不是 href，以避免保存历史记录
                window.location.replace("/oauth2/sign_in?rd=%2F");
                return;
            }
        });

        return true;
    }

    // 存储所有活跃的间隔 ID
    var activeIntervals = [];

    // 标志：是否已经因为 401 而重定向
    var redirecting_to_oauth = false;

    // 标志：是否已成功完成登录
    var login_completed = false;

    function registerInterval(intervalId) {
        activeIntervals.push(intervalId);
    }

    function clearAllIntervals() {
        activeIntervals.forEach(function (id) {
            clearInterval(id);
        });
        activeIntervals = [];
    }

    // 如果已认证，直接返回，不执行自动登录
    if (isAuthenticated()) {
        console.log("[AutoLogin] ✓ User already authenticated, skipping auto-login");
        return;
    }

    console.log("[AutoLogin] Starting auto-login process...");

    // ============================================================
    // 步骤 0: 检查 OAuth2 认证状态
    // ============================================================
    function checkOAuth2Status() {
        console.log("[AutoLogin] Checking OAuth2 userinfo status...");

        fetch("/oauth2/userinfo")
            .then(function (response) {
                console.log("[AutoLogin] OAuth2 userinfo response status:", response.status);

                if (response.status === 200) {
                    // 用户已通过 OAuth2 认证，立即执行登录
                    console.log("[AutoLogin] ✓ User is OAuth2 authenticated, triggering auto-login");
                    doLogin();
                } else if (response.status === 401) {
                    // 用户未认证，需要进行 OAuth2 登录
                    console.log("[AutoLogin] User not OAuth2 authenticated (401), redirecting to OAuth2 sign in");
                    redirecting_to_oauth = true;
                    clearAllIntervals();
                    window.location.replace("/oauth2/sign_in?rd=%2Fweb%2Findex.html");
                }
            })
            .catch(function (error) {
                console.error("[AutoLogin] Error checking OAuth2 status:", error);
                // 继续进行其他备份登录机制
            });
    }

    // 立即检查 OAuth2 状态
    checkOAuth2Status();

    // ============================================================
    // 方案 1: 立即尝试（如果 ApiClient 已准备好）
    // ============================================================
    if (doLogin()) {
        console.log("[AutoLogin] ✓ Login executed immediately (ApiClient ready)");
    }

    // ============================================================
    // 方案 2: 快速轮询检查 ApiClient 准备情况
    // ============================================================
    var checkCount = 0;
    var maxQuickChecks = 200;

    function quickCheck() {
        checkCount++;

        if (isAuthenticated()) {
            console.log("[AutoLogin] ✓ User authenticated (quick check at #" + checkCount + ")");
            return;
        }

        if ((isOnLoginPage() || isInitialState()) && doLogin()) {
            console.log("[AutoLogin] ✓ Login succeeded at quick check #" + checkCount);
            return;
        }

        if (checkCount >= maxQuickChecks) {
            console.warn("[AutoLogin] Max quick checks reached (" + maxQuickChecks + ")");
            return;
        }

        setTimeout(quickCheck, 50);
    }

    quickCheck();

    // ============================================================
    // 备份方案 3: DOM 内容加载完成
    // ============================================================
    function onDOMReady() {
        console.log("[AutoLogin] DOMContentLoaded event fired");
        if (!isAuthenticated() && (isOnLoginPage() || isInitialState())) {
            doLogin();
        }
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", onDOMReady);
    } else {
        // DOM 已经加载
        onDOMReady();
    }

    // ============================================================
    // 备份方案 4: 页面加载完成
    // ============================================================
    window.addEventListener("load", function () {
        console.log("[AutoLogin] Page load event fired");
        if (!isAuthenticated() && (isOnLoginPage() || isInitialState())) {
            doLogin();
        }
    });

    // ============================================================
    // 备份方案 5: 监听 hash 变化
    // ============================================================
    window.addEventListener("hashchange", function () {
        console.log("[AutoLogin] Hash changed to: " + window.location.hash);
        if (!isAuthenticated() && (isOnLoginPage() || isInitialState())) {
            console.log("[AutoLogin] Detected login page via hashchange, attempting login");
            doLogin();
        }
    });

    // ============================================================
    // 备份方案 6: 定期检查（每 2 秒）
    // ============================================================
    var backupCheckInterval = setInterval(function () {
        if (isAuthenticated()) {
            console.log("[AutoLogin] ✓ User authenticated, stopping backup checks");
            clearAllIntervals();
            return;
        }

        if (isOnLoginPage() || isInitialState()) {
            console.log("[AutoLogin] Running periodic backup check");
            doLogin();
        }
    }, 2000);

    registerInterval(backupCheckInterval);

    // ============================================================
    // 备份方案 7: 监听 ApiClient 就绪事件（如果存在）
    // ============================================================
    var apiClientCheckInterval = setInterval(function () {
        if (window.ApiClient && typeof window.ApiClient.authenticateUserByName === "function") {
            console.log("[AutoLogin] ApiClient detected");
            clearInterval(apiClientCheckInterval);

            if (!isAuthenticated() && (isOnLoginPage() || isInitialState())) {
                console.log("[AutoLogin] Attempting login via ApiClient detection");
                doLogin();
            }
        }
    }, 100);

    registerInterval(apiClientCheckInterval);

    // ============================================================
    // 备份方案 8: 监听页面就绪事件
    // ============================================================
    if (window.Emby && window.Emby.Page) {
        console.log("[AutoLogin] Emby.Page detected");
        if (typeof window.Emby.Page.addEventListener === "function") {
            window.Emby.Page.addEventListener("loadbegin", function () {
                console.log("[AutoLogin] Emby page loadbegin event");
                if (!isAuthenticated() && (isOnLoginPage() || isInitialState())) {
                    doLogin();
                }
            });
        }
    }

    console.log("[AutoLogin] ✓ Auto-login script initialized with multiple backup mechanisms");
})();