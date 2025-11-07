// 注销退出按钮和更改用户按钮劫持脚本
// 功能：劫持注销退出按钮和更改用户按钮，点击后重定向到指定页面

(function () {
    'use strict';

    // 重定向位置配置（只配置一次）
    const LOGIN_PAGE_URL = '/oauth2/sign_out?rd=%2Flogin.html';
    const SWITCH_USER_URL = '/oauth2/sign_in?rd=%2Fweb%2Findex.html';

    // 多语言翻译文本 - 用于匹配所有语言版本的按钮
    const TRANSLATIONS = {
        changeUser: [
            "Change User",
            "Canvia d'usuari",
            "Změnit uživatele",
            "Benutzer wechseln",
            "Αλλαγή  Χρήστη",
            "Cambiar Usuario",
            "Vaheta kasutajat",
            "Vaihda käyttäjää",
            "Changer d'utilisateur",
            "החלף משתמש",
            "Felhasználó módosítása",
            "Beralih Pengguna",
            "Cambia utente",
            "사용자 변경",
            "Bytt bruker",
            "Gebruiker wijzigen",
            "Zmień użytkownika",
            "Mudar Usuário",
            "Alterar Utilizador",
            "Смена пользователя",
            "Zmeniť používateľa",
            "Preklopi med uporabniki",
            "Ndërro Përdoruesin",
            "Byt användare",
            "Kullanıcıyı değiştir",
            "Змінити користувача",
            "Thay đổi người dùng",
            "更改用户",
            "更換使用者",
            "變更使用者"
        ],
        signOut: [
            "Sign Out",
            "تسجيل الخروج",
            "Tanca Sessió",
            "Odhlásit se",
            "Abmelden",
            "Αποσύνδεση",
            "Desconectarse",
            "Cerrar Sesión",
            "Logi välja",
            "Kirjaudu ulos",
            "Déconnexion",
            "התנתק",
            "Kijelentkezés",
            "Keluar",
            "Disconnessione",
            "로그아웃",
            "Atsijungti",
            "Logg Ut",
            "Afmelden",
            "Wyloguj",
            "Sair",
            "Odhlásiť sa",
            "Odjava",
            "Dil",
            "Logga ut",
            "Oturumu Kapat",
            "Вийти",
            "Đăng xuất",
            "注销退出",
            "登出"
        ]
    };

    // 注入CSS样式，强制显示"更改用户"按钮（支持多语言）
    function injectSwitchUserButtonStyles() {
        // 检查是否已经注入过
        if (document.getElementById('switch-user-button-styles')) {
            return;
        }

        // 生成多语言 CSS 选择器
        const changeUserSelectors = TRANSLATIONS.changeUser.map(text =>
            `button[aria-label*="${text.replace(/"/g, '\\"')}"]`
        ).join(',\n            ');

        const style = document.createElement('style');
        style.id = 'switch-user-button-styles';
        style.textContent = `
            /* 强制显示"更改用户"按钮（多语言支持） */
            ${changeUserSelectors} {
                display: flex !important;
                visibility: visible !important;
                opacity: 1 !important;
                height: auto !important;
                width: auto !important;
                min-height: 43px !important;
                min-width: 179px !important;
            }
        `;

        // 将样式添加到 head 或 body
        const target = document.head || document.body;
        if (target) {
            target.appendChild(style);
            console.log('更改用户按钮 CSS 样式已注入（多语言支持）');
        }
    }

    // 使用 JavaScript 方式强制显示包含特定文本的按钮（支持多语言）
    function forceShowSwitchUserButtons() {
        if (!document.body) return;

        const buttons = Array.from(document.querySelectorAll('button'));
        buttons.forEach(btn => {
            const text = btn.textContent || '';
            const ariaLabel = btn.getAttribute('aria-label') || '';

            // 检查按钮文本或 aria-label 是否包含任何一种语言的"更改用户"文本
            const isChangeUserButton = TRANSLATIONS.changeUser.some(translation =>
                text.includes(translation) || ariaLabel.includes(translation)
            );

            if (isChangeUserButton) {
                // 强制显示按钮
                btn.style.display = 'flex';
                btn.style.visibility = 'visible';
                btn.style.opacity = '1';
                btn.style.height = 'auto';
                btn.style.width = 'auto';
                btn.style.minHeight = '43px';
                btn.style.minWidth = '179px';

                // 确保父元素也是可见的
                let parent = btn.parentElement;
                while (parent && parent !== document.body) {
                    if (parent.style.display === 'none') {
                        parent.style.display = '';
                    }
                    if (parent.style.visibility === 'hidden') {
                        parent.style.visibility = 'visible';
                    }
                    if (parent.style.opacity === '0') {
                        parent.style.opacity = '1';
                    }
                    parent = parent.parentElement;
                }
            }
        });
    }

    // 劫持注销按钮的函数（支持多语言）
    function hijackLogoutButton() {
        // 如果 DOM 还没准备好，直接返回
        if (!document.body) {
            return false;
        }

        // 查找所有按钮，找到包含任何一种语言的"注销退出"文本的按钮
        const buttons = Array.from(document.querySelectorAll('button'));
        const logoutBtn = buttons.find(btn => {
            const text = btn.textContent || '';
            return TRANSLATIONS.signOut.some(translation => text.includes(translation));
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
                console.log('注销按钮被劫持，执行清理操作后重定向到', LOGIN_PAGE_URL);

                // 清理服务器凭证和会话数据
                (c => (c.Servers = (c.Servers || []).map(s => ({ ...s, UserId: null, Users: [] })), localStorage.setItem('servercredentials3', JSON.stringify(c)), sessionStorage.removeItem('pinvalidated')))(JSON.parse(localStorage.getItem('servercredentials3') || '{}'));
                console.log('已清理服务器凭证信息');

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

    // 劫持切换用户按钮的函数（支持多语言）
    function hijackSwitchUserButton() {
        // 如果 DOM 还没准备好，直接返回
        if (!document.body) {
            return false;
        }

        // 先强制显示所有更改用户按钮
        forceShowSwitchUserButtons();

        // 查找所有按钮，找到包含任何一种语言的"更改用户"文本的按钮
        const buttons = Array.from(document.querySelectorAll('button'));
        const switchUserBtn = buttons.find(btn => {
            const text = btn.textContent || '';
            const ariaLabel = btn.getAttribute('aria-label') || '';
            return TRANSLATIONS.changeUser.some(translation =>
                text.includes(translation) || ariaLabel.includes(translation)
            );
        });

        // 如果找到更改用户按钮且尚未被劫持
        if (switchUserBtn && !switchUserBtn.dataset.hijacked) {
            // 标记为已劫持，避免重复处理
            switchUserBtn.dataset.hijacked = 'true';

            // 通过克隆节点移除所有现有的事件监听器
            const newButton = switchUserBtn.cloneNode(true);
            switchUserBtn.parentNode.replaceChild(newButton, switchUserBtn);
            newButton.dataset.hijacked = 'true';

            // 添加新的事件监听器，在捕获阶段执行以确保优先于原有事件
            newButton.addEventListener('click', function (e) {
                e.preventDefault();
                e.stopPropagation();
                e.stopImmediatePropagation();
                console.log('更改用户按钮被劫持，执行清理操作后重定向到', SWITCH_USER_URL);

                // 清理服务器凭证和会话数据
                (c => (c.Servers = (c.Servers || []).map(s => ({ ...s, UserId: null, Users: [] })), localStorage.setItem('servercredentials3', JSON.stringify(c)), sessionStorage.removeItem('pinvalidated')))(JSON.parse(localStorage.getItem('servercredentials3') || '{}'));
                console.log('已清理服务器凭证信息');

                // 重定向到 OAuth2 登录页面
                window.location.href = SWITCH_USER_URL;
                return false;
            }, true); // true 表示在捕获阶段执行

            return true;
        }
        return false;
    }

    // 初始化函数
    function init() {
        // 首先注入CSS样式
        injectSwitchUserButtonStyles();

        // 立即尝试劫持一次（针对菜单已打开的情况）
        hijackLogoutButton();
        hijackSwitchUserButton();

        // 使用 MutationObserver 监听 DOM 变化
        // 当菜单重新打开时会动态创建按钮，需要重新劫持
        if (document.body && !window.logoutHijackObserver) {
            window.logoutHijackObserver = new MutationObserver(function (mutations) {
                // 每次DOM变化时，重新确保CSS已注入
                injectSwitchUserButtonStyles();
                hijackLogoutButton();
                hijackSwitchUserButton();
            });

            // 监听整个 body 的子树变化
            window.logoutHijackObserver.observe(document.body, {
                childList: true,
                subtree: true
            });
        }

        // 定期检查作为备用方案（每500毫秒）
        // 确保即使 MutationObserver 遗漏也能捕获到按钮
        if (!window.logoutHijackInterval) {
            window.logoutHijackInterval = setInterval(function () {
                forceShowSwitchUserButtons();
                hijackLogoutButton();
                hijackSwitchUserButton();
            }, 500);
        }

        console.log('注销退出按钮和更改用户按钮劫持脚本已初始化（包含CSS强制显示，支持多语言）');
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

