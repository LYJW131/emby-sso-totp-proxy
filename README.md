# Emby Unified Authentication Proxy

> **Disclaimer**: We sincerely apologize that the author's English proficiency is limited. Therefore, this English documentation has been translated using generative artificial intelligence.

This project is an Emby authentication proxy built on **OpenResty (Nginx + Lua)** and **oauth2-proxy**. It provides a unified login gateway for Emby, supporting both **OAuth2/OIDC (SSO)** and **TOTP (Two-Factor Authentication)** login methods, with automatic user registration for new users.

## Project Architecture

All user requests first pass through the OpenResty proxy:

- **Web Browser Clients**: Traffic is guided by the `autologin.js` script to oauth2-proxy for SSO authentication
- **Other Clients** (e.g., Apps): Traffic is redirected to a custom login page (`login.html`), where TOTP verification codes are used for login

```
                                +------------------+
                                |      Users       |
                                | (Browser / App)  |
                                +--------+---------+
                                         |
                                         v
+-------------------------------------------------------------------------+
|                                OpenResty (Nginx + Lua) Port 8096        |
|                                                                         |
|  +--------------------------+         +-------------------------------+ |
|  |     Lua Auth Handler     |         |      OAuth2/OIDC Flow         | |
|  | (TOTP, Rate Limiting)  <----+------>| (autologin.js / oauth2-proxy) | |
|  +--------------------------+         +-------------------------------+ |
|                 |                                      |                |
|                 | (Auto-create for Web clients)        | (TOTP clients) |
|                 v                                      v                |
|  +-------------------------------------------------------------------+  |
|  |                      Backend Emby Server (Port 8096)              |  |
|  +-------------------------------------------------------------------+  |
|                                                                         |
+-------------------------------------------------------------------------+
```

## Main Features

### 🔐 Dual Authentication Modes

- **OAuth2/OIDC**: Perfect integration with oauth2-proxy, providing Single Sign-On (SSO) support for web clients  
  (e.g., using Synology SSO, Authelia, Keycloak, etc.)

- **TOTP**: Provides time-based one-time password login for clients that don't support SSO (such as Emby mobile or TV apps)

### 👤 Automatic User Creation

New users logging in via SSO will have their Emby accounts automatically created using the Emby API if they don't already exist

### 🎯 Automatic Policy Application

Newly created Emby accounts automatically have a preset permission policy applied (default: hidden with no media library access)

### 🎨 Custom Login Page

Provides a dedicated `login.html` page for TOTP login

### 🔄 Auto-Login Script

Injects `autologin.js` into the Emby Web UI to enable OAuth2 authentication state checking and automatic login redirection

### 🚪 Logout Hijacking

Hijacks the Emby Web UI logout button to ensure users are logged out from both oauth2-proxy (SSO) simultaneously

### ⏱️ Rate Limiting

Provides Lua-based rate limiting for the authentication interface (`authenticatebyname`) to prevent brute force attacks

## Usage Guide

### 1️⃣ Prerequisites

- ✅ A server with **Docker** and **Docker Compose** installed
- ✅ A running **Emby server**
- ✅ An available **OAuth2/OIDC provider** (e.g., Synology SSO, Authelia, Keycloak, Google, etc.)
- ✅ Prepared **SSL certificates**

### 2️⃣ Emby Backend Configuration

Before starting the proxy, **you must configure the Emby server properly**:

1. **Disable Emby Password Authentication** ⚠️ **Important**
   - Disable Emby's built-in password authentication and let this proxy manage it uniformly

2. **Hide All Users** (Recommended)
   - Go to **Admin** → **Users & Permissions**
   - Set all users except the admin to **Not Shown** or **Hidden**
   - This prevents the user list from being displayed on the login screen

3. **Migrate Existing Users to SSO**
   - If you have existing users in Emby who want to use SSO, **you must ensure**:
     - Username in Emby = Username in your SSO provider (e.g., Keycloak, Authelia) **exactly matches**
     - This way the system can correctly identify and log in existing users during SSO login

4. **Permission Settings for New SSO Users**
   - New SSO users are automatically created with **minimal permissions** during registration
   - By default, new users **will not have access to any media libraries**
   - Admins can manually adjust permissions, or modify the default policy in the code to auto-assign permissions
   - Default policy configuration location: `lua/set_policy.lua` file

#### 🔐 API Key Setup

1. Go to **Admin** → **API Keys** → **New API Key**
2. Create a dedicated API key for the proxy
3. Copy this key to the `EMBY_API_KEY` field in the `.env` file

### 3️⃣ Configuration File Modifications

After completing the Emby backend configuration, modify the `.env` file according to your environment. This contains environment variables for all services.

```env
# 【Server Domain】
# Must be configured! Your Emby server domain (used for SSL certificate matching)
# If this environment variable is not set, nginx will fail to start with an error
SERVER_NAME=emby.your-domain.com

# 【SSL Certificate Path】
# Must be configured! The full path to the SSL certificate file on the host
# If this environment variable is not set, docker-compose will fail to start
SSL_CERT_PATH=/path/to/your/fullchain.pem
SSL_KEY_PATH=/path/to/your/privkey.pem

# 【Emby Backend Server Address】
# Must be configured! The complete address of the backend Emby server (including protocol and port)
# If this environment variable is not set, nginx will fail to start with an error
EMBY_BACKEND=http://192.168.1.100:8096

# 【Emby API Key】
# Must be configured! Used for automatic user creation and policy setup
# Go to Emby admin dashboard -> API Keys -> New API Key
EMBY_API_KEY=YOUR_EMBY_API_KEY_HERE

# 【TOTP Configuration】
# Add users who need to use TOTP and their 16-character Base32 TOTP keys (case-sensitive)
# Format: '{"username1":"key1", "username2":"key2"}'
USER_TOTP_SECRETS='{"admin":"JBSWY3DPEHPK3PXP"}'

# 【OAuth2-Proxy Basic Configuration】
# For details, please refer to the official OAuth2-Proxy project documentation
```

### 4️⃣ Start the Service

After completing all configuration modifications, run the following command in the project root directory:

```bash
docker-compose up -d
```

### 5️⃣ Login Flow

#### (1) 🌐 Web Browser (SSO Login)

1. Open your browser and visit `https://emby.your-domain.com:8096`
2. SSO login is used by default, automatically redirecting to the IdP
3. The `autologin.js` script will automatically log you into Emby
4. If the Emby account doesn't exist: the proxy will automatically create an Emby account using your SSO username (with default policy applied), then log you in
5. If the Emby account already exists: you will be logged in directly

> 💡 **Tip**: If you need to use TOTP login on the web, manually visit `https://emby.your-domain.com:8096/login.html`

#### (2) 📱 Mobile/TV App (TOTP Login)

1. In your authenticator app (such as Google Authenticator, Authy), add a new entry and select "Manual Entry"
2. Enter the **16-character Base32 key** you configured for that user in the `.env` file
3. In the app's login page, fill in the **Server Address** field with `https://emby.your-domain.com:8096`
4. In the **Username** field, enter the username you configured in the `.env` file
5. In the **Password** field, enter the **6-digit TOTP verification code** displayed in your authenticator app
6. Click Login

## ⚠️ Important Disclaimer

### Code Source

**The code in this project is entirely generated by generative artificial intelligence.** Although it has undergone preliminary security checks, **there is no guarantee of absolute security**.

Before using this project in a production environment, **we strongly recommend that you conduct a complete security review and testing yourself**, including but not limited to:
- Code security audit
- Dependency security check
- Network security testing
- Authentication and authorization process verification

Any security issues, data breaches, or other losses resulting from the use of this project shall be the responsibility of the user.

## 🙏 Acknowledgments

This project uses the [oauth2-proxy](https://github.com/oauth2-proxy/oauth2-proxy) project for OAuth2/OIDC authentication. Please refer to the [oauth2-proxy GitHub repository](https://github.com/oauth2-proxy/oauth2-proxy) for more information and documentation.

## 📄 License

This project is licensed under the **MIT License**. See the [`LICENSE`](./LICENSE) file for details.

The MIT License allows you to freely use, modify, and distribute this project, including for commercial purposes, with the only requirement being to retain the original license and copyright notice in any copies or derivative works.

