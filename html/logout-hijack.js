// 注销按钮劫持脚本
// 功能：劫持注销退出按钮，点击后重定向到 /login.html

(function () {
    'use strict';

    // 重定向位置配置（只配置一次）
    const LOGIN_PAGE_URL = '/oauth2/sign_out?rd=%2Flogin.html';

    // 劫持注销按钮的函数
    function hijackLogoutButton() {
        // 如果 DOM 还没准备好，直接返回
        if (!document.body) {
            return false;
        }

        // 查找所有按钮，找到包含"注销退出"或"注销"文本的按钮
        const buttons = Array.from(document.querySelectorAll('button'));
        const logoutBtn = buttons.find(btn => {
            const text = btn.textContent || '';
            return text.includes('注销退出') || text.includes('注销');
        });

        // 如果找到注销按钮且尚未被劫持
        if (logoutBtn && !logoutBtn.dataset.hijacked) {
            // 标记为已劫持，避免重复处理
            logoutBtn.dataset.hijacked = 'true';

            // 通过克隆节点移除所有现有的事件监听器
            const newButton = logoutBtn.cloneNode(true);
            logoutBtn.parentNode.replaceChild(newButton, logoutBtn);
            newButton.dataset.hijacked = 'true';

            // 添加新的事件监听器，在捕获阶段执行以确保优先于原有事件
            newButton.addEventListener('click', function (e) {
                e.preventDefault();
                e.stopPropagation();
                e.stopImmediatePropagation();
                console.log('注销按钮被劫持，调用 logout API 后重定向到', LOGIN_PAGE_URL);
                // 先调用 logout API
                if (window.ApiClient && window.ApiClient.logout) {
                    window.ApiClient.logout();
                }
                // 重定向到登录页面
                window.location.href = LOGIN_PAGE_URL;
                return false;
            }, true); // true 表示在捕获阶段执行

            return true;
        }
        return false;
    }

    // 初始化函数
    function init() {
        // 立即尝试劫持一次（针对菜单已打开的情况）
        hijackLogoutButton();

        // 使用 MutationObserver 监听 DOM 变化
        // 当菜单重新打开时会动态创建注销按钮，需要重新劫持
        if (document.body && !window.logoutHijackObserver) {
            window.logoutHijackObserver = new MutationObserver(function (mutations) {
                hijackLogoutButton();
            });

            // 监听整个 body 的子树变化
            window.logoutHijackObserver.observe(document.body, {
                childList: true,
                subtree: true
            });
        }

        // 定期检查作为备用方案（每500毫秒）
        // 确保即使 MutationObserver 遗漏也能捕获到注销按钮
        if (!window.logoutHijackInterval) {
            window.logoutHijackInterval = setInterval(hijackLogoutButton, 500);
        }

        console.log('注销按钮劫持脚本已初始化');
    }

    // 如果 DOM 已经准备好，立即初始化
    if (document.readyState === 'loading') {
        // DOM 还在加载，等待 DOMContentLoaded
        document.addEventListener('DOMContentLoaded', init);
    } else {
        // DOM 已经准备好，立即初始化
        // 如果 body 还不存在，等待一下
        if (document.body) {
            init();
        } else {
            // 使用 setInterval 等待 body 出现
            var bodyCheckInterval = setInterval(function () {
                if (document.body) {
                    clearInterval(bodyCheckInterval);
                    init();
                }
            }, 50);

            // 设置超时，避免无限等待
            setTimeout(function () {
                clearInterval(bodyCheckInterval);
                if (!window.logoutHijackObserver && !window.logoutHijackInterval) {
                    console.warn('注销按钮劫持脚本：等待 body 超时，强制初始化');
                    init();
                }
            }, 5000);
        }
    }

    // 也监听页面加载完成事件作为备用
    window.addEventListener('load', function () {
        if (!window.logoutHijackObserver || !window.logoutHijackInterval) {
            console.log('注销按钮劫持脚本：通过 load 事件初始化');
            init();
        }
    });
})();

