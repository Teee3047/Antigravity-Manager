# Android 平板适配计划（vivo PA2553 / Dimensity 9300+）

状态：v1 安装路径已经落到仓库里。操作步骤见 [android-termux.md](./android-termux.md)。目标机仍是 Teee 的 vivo PA2553（联发科 Dimensity 9300+，arm64）。本仓库没有在这台机器上跑过，文末开放问题和安装文档里的「需要真机确认」仍然有效。

本文件是当时的路线说明。它不包含 Bionic 原生包，也不包含保活 APK。不要把本 fork 推到 `lbjlaq/Antigravity-Manager`。

## 0. v1 唯一主路线

**v1 就做一件事：在 Termux 的 `proot-distro` Debian 里跑现有的 Linux aarch64 `--headless` 二进制，用平板自带浏览器打开已经存在的 Web 管理界面。**

不选 Tauri Android，不选 Capacitor，不选 Kotlin 重写 UI。那些路线都要先拆掉桌面壳或重做界面。这条路线不用。

原因（都对应现有代码，不是新设计）：

1. 进程入口在拉起 Tauri 之前就分叉了。`src-tauri/src/lib.rs` 的 `run()` 看到参数 `--headless` 后，只启动 Axum 反代和调度器，然后 `return`，不会进入 `tauri::Builder`。
2. 同一条路径已经是 Docker 的正式形态。`docker/Dockerfile` 的 `ENTRYPOINT` 就是 `["/app/antigravity-tools", "--headless"]`，并用 `ABV_DIST_PATH=/app/dist` 把 `npm run build` 的静态页交给 Axum 托管。`docker/README.md` 写明浏览器访问 `http://localhost:8045`。
3. 前端在没有 Tauri 时已经走 HTTP。`src/utils/env.ts` 用 `window.__TAURI_INTERNALS__` / `__TAURI__` 判断环境。`src/utils/request.ts` 在非 Tauri 时把命令映射到 `/api/...`，登录态放在 `sessionStorage` 的 `abv_admin_api_key`（`src/components/common/AdminAuthGuard.tsx`）。
4. 上游发布矩阵里已经有 Linux arm64 桌面机构建：`.github/workflows/release.yml` 的 `ubuntu-24.04-arm`。产物是 glibc 动态链接，不是 Android Bionic。Issue [lbjlaq/Antigravity-Manager#3818](https://github.com/lbjlaq/Antigravity-Manager/issues/3818) 仍为 OPEN，正文写明 Linux ARM64 不能直接在 Termux 里跑，且没有 headless 专用包。proot Debian 正好补上这个 glibc 缺口，让 v1 不必先做 Bionic 移植。
5. 平板上真正要长期活着的是本机反代（默认端口 8045，`src-tauri/src/proxy/config.rs` 的 `ProxyConfig::default`），不是一个前台窗口。浏览器只是管理面。进程保活先用 Termux 唤醒锁，不把产品绑进 Activity 生命周期。

v1 成功时，使用者在平板 Chrome（或系统浏览器）打开 `http://127.0.0.1:8045`，用 Web 密码登录，粘贴一条 refresh token，让本机客户端把 OpenAI / Anthropic / Gemini 请求打到 `http://127.0.0.1:8045/v1`。桌面壳功能不在 v1。

后续才做的两件事，明确不是 v1：

- **M2–M3**：`server-only` 构建，去掉 GTK / WebKit / Tauri 链接，使二进制能在 Termux Bionic 上直接跑。这是 #3818 真正要的「原生 Termux」。
- **M4（可选）**：很薄的 Kotlin 前台服务 APK，WebView 只加载 `127.0.0.1`。只有 vivo 杀后台让 proot / Termux 保活失败时才做。

## 1. 架构：桌面壳、可移植后端、已经能用的 Web UI

版本以仓库当前清单为准：根目录 `package.json` 与 `src-tauri/Cargo.toml`、`src-tauri/tauri.conf.json` 都是 `5.0.0`。前端是 Vite + React 19 + React Router 7。后端是一个 Rust crate：库名 `antigravity_tools_lib`（`crate-type = ["rlib"]`），二进制入口 `src-tauri/src/main.rs` 只有一行 `antigravity_tools_lib::run()`。

```text
平板浏览器 / 桌面 WebView
        |  Tauri invoke（仅桌面）或 HTTP /api（Web / Docker / 未来平板）
        v
src-tauri/src/lib.rs::run()
        |-- CLI：modules/cli_handler.rs（switch / list / import / export）
        |-- --headless：Axum + scheduler，无窗口
        `-- 否则 tauri::Builder（窗口、托盘、更新器、单实例）
                |
                v
        commands/*  （#[tauri::command]，桌面 IPC）
        proxy/server.rs （同一套管理 API + 协议反代，端口默认 8045）
                |
                v
        modules/* 账号、配置、OAuth、SQLite
        proxy/*   协议转换、账号调度、上游请求
                |
                v
        上游 Google / Anthropic（rquest，Chrome 指纹）
```

### 1.1 本地反代实际做什么

监听与路由在 `src-tauri/src/proxy/server.rs`。

- 协议面（给 Claude Code、聊天客户端、SDK 用），挂在根上，不走管理登录：
  - OpenAI：`/v1/chat/completions`、`/v1/models`、`/responses` 等，处理器 `src-tauri/src/proxy/handlers/openai.rs`
  - Anthropic：`/v1/messages`，`handlers/claude.rs`
  - Gemini：`/v1beta/models/...`，`handlers/gemini.rs`
  - 探活：`/health`、`/healthz`
- 管理面：`.nest("/api", admin_routes)`，再套 `admin_auth_middleware`。账号、配额、配置、日志、安全、User Token、OAuth URL 都在这里。`src/utils/request.ts` 的 `COMMAND_MAPPING` 就是这组 HTTP 的前端契约。
- 静态页：环境变量 `ABV_DIST_PATH` 指向的目录存在时，用 `tower_http::services::ServeDir` 托管，未知路径回退 `index.html`。这就是 Docker / 平板浏览器能打开完整 React 界面的原因。
- 请求体上限默认 100MB，可用 `ABV_MAX_BODY_SIZE` 覆盖（`server.rs` 里读取该变量）。
- 上游出站不走 `reqwest` 的普通客户端。`src-tauri/src/proxy/upstream/client.rs` 的 `base_client_builder()` 使用 `rquest`，并 `emulation(rquest_util::Emulation::Chrome123)`。`Cargo.toml` 依赖 `rquest = "5.1.0"`（features 含 `json`、`stream`、`socks`、`cookies`）和 `rquest-util`。换掉这个客户端会改变 TLS / HTTP 指纹。任何 Android 构建都必须把 `rquest` 编进去，不能为了好交叉编译改成裸 `reqwest`。
- 账号调度、配额、重试在 `src-tauri/src/proxy/`（`token_manager.rs`、`rate_limit.rs`、`session_manager.rs`、`mappers/`）。这层不画窗口，但是它通过 `SystemManager` 碰到桌面集成，见下。

Headless 启动时还会做这些环境变量覆盖（`lib.rs` 里 `is_headless` 分支）：

| 变量 | 作用 |
| --- | --- |
| `ABV_BIND_LOCAL_ONLY=1/true/yes/on` | 关掉 `allow_lan_access`，只绑 `127.0.0.1` |
| 未设置上面的变量 | headless **强制** `allow_lan_access = true`，绑 `0.0.0.0`（`ProxyConfig::get_bind_address`） |
| `ABV_API_KEY` 或 `API_KEY` | 写入 `proxy.api_key` |
| `ABV_WEB_PASSWORD` 或 `WEB_PASSWORD` | 写入 `proxy.admin_password` |
| `ABV_AUTH_MODE` 或 `AUTH_MODE` | `off` / `strict` / `all_except_health` / `auto` |
| 鉴权模式原为 `Off` 或 `Auto` | headless 改成 `AllExceptHealth`，保证 Web 登录会校验 |

默认配置本身是「仅本机、端口 8045、随机 `sk-...` API Key」（`ProxyConfig::default`）。headless 会把「仅本机」翻成局域网，除非显式 `ABV_BIND_LOCAL_ONLY`。平板 v1 必须设这个变量，避免 vivo 连上 Wi-Fi 后反代对局域网开放。

### 1.2 数据放在哪

`src-tauri/src/modules/account.rs` 的 `get_data_dir()` 顺序：

1. 环境变量 `ABV_DATA_DIR`
2. 进程内覆盖
3. 家目录下的指针文件 `.antigravity_tools_location`（可用 `ABV_DATA_DIR_POINTER_FILE` 改位置）
4. 默认 `~/.antigravity_tools`（`dirs::home_dir()`）

家目录拿不到时，非测试代码会返回错误（`failed_to_get_home_dir`）。Termux / proot 里 `HOME` 是有的。将来如果做成 APK，必须自己设 `ABV_DATA_DIR` 到应用私有目录，不能假设 `dirs` 在 `target_os = "android"` 上找得到家目录。这一点没有在本仓库验证过。

该目录里已有的文件（路径都是相对数据目录）：

| 文件 | 来源 |
| --- | --- |
| `gui_config.json` | `src-tauri/src/modules/config.rs` |
| `accounts.json`、`accounts/` | `modules/account.rs` |
| `token_stats.db` | `modules/token_stats.rs` |
| `proxy_logs.db`、`thinking_store.db` | `modules/proxy_db.rs` |
| `security.db` | `modules/security_db.rs` |
| `user_tokens.db` | `modules/user_token_db.rs` |
| `logs/` | `modules/logger.rs` |
| `http_api_settings.json` | `modules/http_api.rs`（独立 19527 端口的旧模块；`lib.rs` 注明管理 API 已并进 8045，该模块「当前未在主流程中启用」） |

`gui_config.json` 里的代理密码用本机 ID 做 AES-GCM 密钥：`src-tauri/src/utils/crypto.rs` 调用 `machine_uid::get()`，失败则用字符串 `"default"`。机器 ID 一旦变化，解密失败只会打日志并留下密文。平板上 proot 的 `/etc/machine-id` 是否稳定没有测过。v1 用 `ABV_API_KEY` / `ABV_WEB_PASSWORD` 每次注入，不依赖这份密文能跨重启解开。

### 1.3 桌面壳专有 vs 可移植

**可移植（v1 要留下的）：**

- `src-tauri/src/proxy/**` 协议管线、Axum 服务、中间件
- `src-tauri/src/modules/` 里账号、配额、配置、SQLite、OAuth token 交换（`modules/oauth.rs`）、headless 集成（`modules/integration.rs` 的 `HeadlessIntegration`）
- `src/` React 页面在浏览器中的那一部分：仪表盘、账号、API 反代、监控、统计、设置里不依赖窗口的项
- CLI 的读账号 / 导入导出（`modules/cli_handler.rs`）。`switch` 到本机 IDE 在平板上没有宿主，见非目标

**桌面壳专有（v1 不搬，server-only 构建时用 cfg 摘掉）：**

| 能力 | 证据 |
| --- | --- |
| 两个窗口：主窗 1024×700 Overlay 标题栏；`mini` 透明无边框悬浮窗 | `src-tauri/tauri.conf.json` 的 `app.windows` |
| 托盘、`ANTIGRAVITY_DISABLE_TRAY`、Linux Wayland 下探测 AppIndicator | `lib.rs` 的 `should_enable_tray` |
| 单实例 + deep link | `tauri-plugin-single-instance`（`Cargo.toml` features 含 `deep-link`） |
| 开机自启 | `tauri-plugin-autostart`，macOS 用 LaunchAgent，参数 `--minimized` |
| 窗口位置记忆 | `tauri-plugin-window-state` |
| Tauri 签名更新 | `tauri.conf.json` 的 `plugins.updater`，端点与公钥都指向 `lbjlaq/Antigravity-Manager` |
| macOS 私有 API、文件描述符上限、Windows EcoQoS、Win32 快捷方式 | `tauri.conf.json` 的 `macOSPrivateApi`；`lib.rs` 的 `increase_nofile_limit` / `windows_api`；`utils/win_shortcut.rs` |
| Linux GTK / WebKit 显示守卫 | `Cargo.toml` 的 `target.'cfg(target_os = "linux")'.dependencies` 里的 `gtk`；`linux_display_guard.rs`、`linux_graphics.rs`。Docker 运行镜像仍安装 `libgtk-3-0`、`libwebkit2gtk-4.1-0`，因为 **headless 用的是同一个二进制** |
| 菜单能力 | `src-tauri/capabilities/default.json` 引用 `../gen/schemas/desktop-schema.json`，窗口只有 `main` 和 `mini`。仓库里没有 `src-tauri/gen/android`，没有 Gradle 工程 |
| 把账号写进本机 Antigravity / IDE 的 `state.vscdb`、系统钥匙串、`security` / `secret-tool` | `modules/db.rs`（macOS `~/Library/Application Support`、Windows `%APPDATA%`、Linux `~/.config/Antigravity`）、`modules/integration.rs` 的 `write_to_system_keyring`、`modules/device.rs` 的 `storage.json` |
| 启动 / 关闭 Claude Desktop、给 agy / Claude 打补丁、Homebrew 升级 | `src/components/settings/AgentSettings.tsx` 直接 `import { invoke } from "@tauri-apps/api/core"`，命令如 `launch_claude_desktop`、`patch_agy_binary`。这些调用不经过 `request.ts`，浏览器里会失败 |
| cloudflared 下载 | `modules/cloudflared.rs` 的 `get_download_url()` 只匹配 macos / linux / windows。Android 的 `std::env::consts::OS` 不是 `"linux"`，会落到 `Unsupported platform`。proot Debian 里 OS 仍是 `linux`，可能去下 `cloudflared-linux-arm64`。v1 不做隧道 |
| 前端拖拽标题栏 | `src/components/layout/Layout.tsx` 顶部 36px 在 `onMouseDown` 里无条件调用 `getCurrentWindow().startDragging()`。浏览器里点到这块会抛错。平板 v1 要加 `isTauri()` 判断，这是小修补，不是新 UI |

`#[cfg_attr(mobile, tauri::mobile_entry_point)]`（`lib.rs` 的 `run`）是 Tauri 模板留下的移动入口属性。旁边没有 Android 工程，不能把它当成「已经支持手机」。

`modules/integration.rs` 已经有三档系统集成：`Desktop`、`Headless`、`Cli`。`HeadlessIntegration::on_account_switch` 只改内存里的当前账号；目标是 `agy` 时直接返回错误：`no host keyring access`。平板走 headless 时，切换账号意味着「反代接下来用哪个号」，不是「把 vivo 上并不存在的桌面 IDE 换登录」。

### 1.4 Web 命令契约里，v1 能用和不能用的

浏览器只认 `src/utils/request.ts` 的 `COMMAND_MAPPING`。表里没有的命令会抛 `Command [..] not supported in Web mode`。

v1 垂直切片依赖、且表里已经有的命令：

- 账号：`list_accounts`、`add_account`、`delete_account`、`fetch_account_quota`、`refresh_all_quotas`
- 反代：`get_proxy_status`、`start_proxy_service`、`stop_proxy_service`、`load_config`、`save_config`、`generate_api_key`
- 登录后的页面数据：仪表盘用的列表与配额

已确认不在该表中、浏览器会失败、v1 不补齐的例子：

- `batch_import_accounts`（批量导入；单条 `add_account` 在表里）
- `get_active_clients_status`
- `get_token_stats_minute`、`get_token_stats_model_trend_minute`、`get_token_stats_account_trend_minute`（小时 / 日 / 周在表里）
- `get_hub_fingerprint`、`get_proxy_logs_paginated`
- `check_homebrew_installation`、`brew_upgrade_cask`、`patch_agy_binary`
- `check_claude_cowork_patch`、`apply_claude_cowork_patch`、`launch_claude_desktop`、`close_claude_desktop`
- `show_main_window`、`show_mini_view`、`set_window_theme`（后两个有的调用点已用 `isTauri()` 包住）

OAuth：桌面走 `modules/oauth_server.rs`，在 `127.0.0.1` 和 `[::1]` 上起临时端口，redirect 为 `http://localhost:<临时端口>/oauth-callback`，并用 `tauri-plugin-opener` 打开系统浏览器。Web / headless 另有一条：`server.rs` 的 `get_oauth_redirect_uri` 默认 `http://localhost:<反代端口>/auth/callback`，只有设置了 `ABV_PUBLIC_URL` 才用外网 HTTPS。`src/components/accounts/AddAccountDialog.tsx` 在非 Tauri 时默认页是「粘贴 token」，不是 OAuth。v1 账号入口用粘贴 refresh token。回环 OAuth 能否在 vivo 的 Chrome 里打到 proot 里的端口，是开放问题，不作为 v1 成功条件。

更新检查即使在 Web 模式也会打到上游仓库：`src-tauri/src/modules/update_checker.rs` 把 `GITHUB_API_URL` 写死为 `https://api.github.com/repos/lbjlaq/Antigravity-Manager/releases/latest`，`STABLE_UPDATER_JSON_URL` 同样指向该仓库的 `updater.json`。Tauri 插件更新器的公钥也是上游的（`tauri.conf.json`）。本 fork 没有那把私钥，不能给现有更新器签包。平板上如果点「更新」，拿到的是桌面 dmg / exe / AppImage 的说明，不是 APK。v1 在 headless 默认关闭自动检查，或在 UI 上标明「此处是上游桌面版本，不是本平板包」。不要把上游安装包写进本 fork 的更新通道。

### 1.5 前端对平板屏幕意味着什么

`index.html` 已有 `width=device-width`。导航在 `src/components/navbar/NavMenu.tsx` 按宽度切换：≥1120px 文字胶囊，更窄则图标或下拉。横屏平板足够用。窗口设计尺寸是 1024×700，那只是 Tauri 窗口，浏览器会铺满。

生产构建 `vite.config.ts` 的 `base` 是 `"./"`。开发时 `index.html` 引用 `/src/main.tsx` 和 `/icon.png`。打包后资源会变成相对路径。Axum 对深链接会回退 `index.html`，但浏览器在 `/accounts` 这种 URL 上刷新时，相对资源会去请求 `/accounts/assets/...`。Docker 文档只要求打开站点根路径。v1 书签用 `http://127.0.0.1:8045/`。若刷新子路由白屏，再把 headless 专用构建的 `base` 改成 `"/"`。这是待验证项，本计划没有跑过 `npm run build` 去看产物 HTML。

## 2. 许可证与再分发

仓库根目录 `LICENSE` 是 **Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International** 全文。没有单独的 `NOTICE` 文件。`src-tauri/Cargo.toml` 的 `license = "CC-BY-NC-SA-4.0"`。`README.md` 文末写 “Strictly for non-commercial use.”，并有 “Copyright © 2024-2026 Antigravity Team.”

和本 fork 有关的条款（以 `LICENSE` 正文为准，这里不是法律意见）：

- **可以**为非商业目的复制、修改、再分享，包括换介质（Section 2(a)(1)、2(a)(4)）。个人平板上自用、把构建方法写进本 fork，属于这个范围。
- **不可以**以商业优势或金钱对价为主要目的来分享（Section 1(k)、2(a)(1)）。不卖 APK，不做付费「Pro」包，不把这个移植塞进收费服务。
- **相同方式共享**（Section 3(b)）：改编作品继续用 CC BY-NC-SA 4.0（或 CC 列出的兼容许可证）。本 fork 保持现有 `LICENSE`，不改成 MIT / Apache。
- **署名**（Section 3(a)）：再分发时保留上游作者标识、许可证指向、免责声明、以及在合理范围内指向原仓库的链接；标明改过。平板包的关于页或随包文本至少要写清：
  - 上游：Antigravity Team，<https://github.com/lbjlaq/Antigravity-Manager>
  - 本改编：Teee3047/Antigravity-Manager 的 Android / Termux 移植（未官方发布）
  - 许可证：CC BY-NC-SA 4.0，附 `LICENSE` 或指向 <https://creativecommons.org/licenses/by-nc-sa/4.0/>
- **禁止暗示官方认可**（Section 2(a)(6)）。不能写成「Antigravity 官方 Android 版」。`tauri.conf.json` 的 identifier 是 `com.lbjlaq.antigravity-tools`。将来若做 APK，applicationId 不要冒充上游包名。具体 id 尚未选定，见开放问题。
- **专利和商标不在许可证里**（Section 2(b)(2)）。「Antigravity Tools」名称能不能用在图标和启动器上，CC 文本没有授权。v1 的 Termux 脚本继续用现有产品名，并在同一屏写上「非官方 fork」。是否改名留给 Teee，不在本计划里定死。
- 第三方依赖（React、Tauri、crates、npm）各自有许可证，多数是 MIT。仓库没有汇总的 `NOTICE`。再分发二进制时带上本仓库 `LICENSE`，并说明依赖保留各自许可证。不在本计划里编一份未核对的第三方清单。
- 本计划的 PR 只进 `Teee3047/Antigravity-Manager` 的 `main`。不向 `lbjlaq` 开 PR，不用上游的 minisign 私钥（本 fork 也没有）去签更新包。

`modules/oauth.rs` 里编译进了上游使用的 OAuth client。再分发 fork 会连同这段已公开的源码一起带走，这不是本计划新增的密钥。不要在文档、脚本或截图里再抄一遍 client secret。改 redirect、改应用身份有可能被 Google 拒绝，这是产品风险，不是许可证条款。

## 3. 路线比较（按平板可行性排序）

目标只有一个：Dimensity 9300+ 平板上，本机反代能活着，管理界面能点。排序看的是「离现有代码有多近」和「后台进程能不能活」，不是桌面功能覆盖率。

### 路线 A — v1 主路线：proot Debian + 现有 `--headless` + 浏览器

做法：Termux 安装 `proot-distro`，进 Debian，装与 `docker/Dockerfile` 运行阶段相同的动态库（`libssl3`、`libsqlite3-0`、`libgtk-3-0`、`libwebkit2gtk-4.1-0`、`libayatana-appindicator3-1`、`librsvg2-2`、`ca-certificates`），放入 **本 fork 自己构建** 的 linux aarch64 二进制和 `dist/`，设 `ABV_DIST_PATH`、`ABV_DATA_DIR`、`ABV_BIND_LOCAL_ONLY=1`、`ABV_API_KEY`、`ABV_WEB_PASSWORD`，执行 `antigravity-tools --headless`。浏览器打开 `http://127.0.0.1:8045/`。

| 优点 | 代价 |
| --- | --- |
| 不改协议代码。Docker 已经证明这条启动路径 | 二进制仍链接 GTK / WebKit。即使用 `--headless` 也要装那一套库，磁盘和内存都比「纯 API」大。#3818 抱怨的就是这个开销 |
| 数据目录、Web 登录、四套协议端点都在 | proot 不是 Android Service。vivo 省电策略可能把 Termux 杀掉。需要 `termux-wake-lock`，并在系统里把 Termux 设为无限制。能否扛住息屏，必须在 PA2553 上试 |
| 构建可复用 `.github/workflows/release.yml` 的 `ubuntu-24.04-arm` 依赖清单，在 arm64 Linux 上 `npm run build` 再 `cargo build --release --bin antigravity-tools` | 不要直接 `workflow_dispatch` 现有 `release.yml` 来「只编一个测试包」：该 workflow 在 tag / 手动触发时会走发布门禁并上传 Release。测试包用单独的一次性构建，或以后加一个不发布的 workflow |
| 浏览器 UI 就是现在的 React | AppImage 依赖 FUSE。proot 里 FUSE 经常不可用。用 `.deb` 解压出来的二进制，或 `cargo build` 的 ELF，不用 AppImage 挂载 |

### 路线 B — v1 之后的主工程：Termux Bionic 上的 server-only 二进制 + 同一套浏览器 UI

这是 #3818 的原文请求：不要 proot，不要桌面库，保留 OpenAI / Anthropic 兼容端点。

做法：给 `src-tauri/Cargo.toml` 加可选 feature（名字建议 `server-only`，实现时再定），在该 feature 下：

- `tauri`、`tauri-plugin-*`、linux `gtk` 改为 optional，headless 入口不再编译 `tauri::Builder` 那一支
- `build.rs` 里的 `tauri_build::build()` 不能在 server-only 时跑
- 保留 `axum`、`tokio`、`rusqlite`（已 `bundled`）、`rquest`、`aes-gcm`、账号与代理模块
- 目标三元组：`aarch64-linux-android`（Termux 官方 Rust 用的就是这个，libc 是 Bionic）
- 前端仍是 `ABV_DIST_PATH` 指向的 `dist/`。可以在电脑上 `npm run build` 把 `dist/` 拷进 Termux，平板上不必装 Node

这比路线 A 干净，但它是一次真实的 Rust 构建改造。`rquest` 带 BoringSSL，`docker/Dockerfile` 为它安装了 Go、clang、cmake。Termux 上这套能否编过，仓库没有记录。所以不要把「第一天就能在平板上点开」押在这条路上。路线 A 先证明功能，路线 B 再减重。

### 路线 C — 薄 Kotlin 前台服务 + WebView（只在保活失败时）

不重写 UI。Kotlin 只做三件事：以前台服务把 **Bionic** 二进制拉起来（Android 10 之后不能随便从任意目录 `exec`，常见做法是放在 native lib 目录、文件名像 `libantigravity.so` 再执行）、发一条常驻通知、WebView 打开 `http://127.0.0.1:8045/`。

前提是路线 B 的二进制已经存在。glibc 的 proot 二进制不能塞进 APK。

Tauri 2 的 Android 壳和 Capacitor 都不如这个薄壳：

- 仓库没有 mobile 工程。`tauri.conf.json` 打开了 `macOSPrivateApi`、托盘、两个桌面窗口、指向上游的 updater。`capabilities/default.json` 是 desktop schema。
- 反代必须在界面退到后台后继续听 8045。Tauri / Capacitor 的 Activity 会被系统冻结。前台服务要写在 Android 组件里，不是 WebView 插件能顺便得到的。
- Capacitor 不编译这个 Cargo 工程，最后还是要另挂一个进程，多一层壳，少一层能力。

因此：不把「Tauri mobile」或「Capacitor」列为 v1，也不列为 v2 的默认壳。只有路线 B 完成且 Termux 保活在 vivo 上不够用，才做这个 Kotlin 壳。

### 路线 D — Kotlin UI + UniFFI / JNI 共享 Rust 核心

不推荐，包括 v1 之后。

管理 API 已经是稳定边界：`proxy/server.rs` 的 `/api` 加上 `request.ts` 的映射。`src-tauri/src/commands/mod.rs` 的命令是 `#[tauri::command]`，签名里是 `tauri::State`、`Emitter`、`Manager`、`tauri_plugin_opener::OpenerExt`。要上 UniFFI 就得再抽一层与 Tauri 无关的 facade，同时丢掉已经能在浏览器里跑的 `src/`。工作量和「重写客户端」同级，对「平板上能用反代」没有额外收益。

`modules/http_api.rs` 头部写着预留、默认端口 19527、当前未接入主流程。不要把它当成现成的移动 API。主流程是 8045。

### 路线 E — 不在平板上跑，只跑 Docker

`docker/` 已经能在 NAS / 服务器上提供同一套 Web UI。这满足不了「人在平板跟前、反代在平板本机」的目标，而且普通 Android 没有 Docker 引擎。不作为本机方案。可以继续当桌面 / 服务器的参照实现。

## 4. 每条推荐路线要动什么

下面只写路线 A（v1）和路线 B（紧接着的工程）。路线 C 的差异单独附在 B 后面。路线 D、E 不动代码。

### 4.1 路线 A（proot + 现有二进制）

原则上 **可以零改 Rust 就先跑起来**。下面这些是跑通之后、仍算 v1 收尾的小改，都落在已有开关上，不动协议。

| 面 | 现状 | v1 要做的 |
| --- | --- | --- |
| 构建 | 同一二进制带 Tauri。Linux arm64 依赖见 `release.yml`（`libwebkit2gtk-4.1-dev`、GTK、ayatana、`libsoup`、`javascriptcoregtk`）和 `docker/Dockerfile` | 在 arm64 Linux 上按 Docker 顺序：先 `npm run build` 得到 `dist/`，再在 `src-tauri` 里 release 编译二进制。`build.rs` 会调用 `tauri_build::build()`，所以 `dist/` 要先存在（与 Dockerfile 一致）。产物放进 proot，不走上游 updater |
| 安装说明 | 无 | 下一阶段补 `docs/` 或 `scripts/` 里的 Termux 步骤。本文件第 5 节是草稿，还没在 PA2553 上跑过 |
| 会话与鉴权 | Web 密码在 `sessionStorage`（`AdminAuthGuard.tsx`）。关标签就丢，要重输。API Key 与 Web 密码分离已由 headless 环境变量支持 | 保持。不把管理密码放进平板剪贴板历史以外的新存储。文档里要求 `ABV_WEB_PASSWORD` 与 `ABV_API_KEY` 分开 |
| 网络 | headless 默认局域网 | 启动命令固定 `ABV_BIND_LOCAL_ONLY=1`。需要给同一 Wi-Fi 上的电脑用时，再手动打开，并在设置里看 `auth_mode`。v1 文档默认只绑本机 |
| 后台 | headless 只等 `tokio::signal::ctrl_c()`（`lib.rs`）。Linux GUI 分支才有 SIGTERM 处理 | proot 里用 `nohup` 或 Termux 的 runit（`termux-services`）。息屏用 Termux:API 的 `termux-wake-lock`。SIGTERM 是否干净退出是开放问题；v1 接受「杀进程再拉起」，数据以 SQLite / JSON 落盘为准 |
| OAuth | Web 默认粘贴 token。回环 callback 见 `get_oauth_redirect_uri` | v1 只用 `add_account` 粘贴 refresh token。不新开 Google Cloud 客户端 |
| 路径 | `ABV_DATA_DIR` 已支持 | 设在 proot 家目录，例如 `/root/.antigravity_tools`，不要指到 Android 共享存储。Termux 与 proot 的文件系统是两套，浏览器下载的 JSON 要用 `termux-setup-storage` 再拷进 proot，或直接在网页里粘贴 |
| 自动更新 | 检查的是上游桌面 Release | v1 启动后在 Web 设置里关掉自动检查（`save_update_settings` 已在 `COMMAND_MAPPING`）。代码层默认关闭留到路线 B，避免 A 的「先跑起来」被设置项挡住。关于页不要出现「下载最新版」却链到 dmg/exe |
| 前端小坑 | `Layout.tsx` 拖拽条 | 用 `isTauri()` 包住 `startDragging`。否则浏览器里点顶栏会报错 |

明确不在路线 A 改的：`rquest` 指纹、协议 mapper、托盘、IDE 注入、cloudflared。

### 4.2 路线 B（Bionic server-only）

在 A 已经在平板上证明「浏览器 + 8045 + 一条账号能打通上游」之后再做。

| 面 | 改动 |
| --- | --- |
| 构建 | `Cargo.toml` 把 Tauri 全家和 linux `gtk` 变成可选。`src-tauri/src/lib.rs` 里窗口、托盘、插件、`ensure_cli_symlinks`、Linux display guard 全部 `cfg` 掉。`main.rs` 仍调用 `run()`，但 `run()` 在 server-only 下只保留 headless 分支（甚至不再需要 `--headless` 参数，见开放问题）。交叉或在 Termux 本机编译 `aarch64-linux-android`。CI 若要加 job，用 Android NDK，**不要**复用装了 WebKit 的 `ubuntu-24.04-arm` 当作 Bionic 产物 |
| `build.rs` | server-only 时不调用 `tauri_build::build()`，否则没有桌面前端嵌入也会失败 |
| 动态库 | 目标是只依赖 libc、可能的 `libdl`。SQLite 继续用 `rusqlite` 的 `bundled`。BoringSSL 随 `rquest` 静态链进来。这是 B 的最大技术风险 |
| 鉴权存储 | 继续环境变量 + `gui_config.json`。先在 Termux 上打印 `machine_uid::get()` 的结果（不要打印密钥），确认重启后不变。若变化，server-only 改为使用文件内随机密钥并写进数据目录，而不是机器 ID。这是行为变化，要单独提交，并给旧的 `ag_enc_` / `ag_enc_v2_` 留解密失败时的明确错误，而不是静默把密文当密码 |
| 网络 | 默认 `ABV_BIND_LOCAL_ONLY` 的语义收成「Android / Termux 默认只绑 127.0.0.1」，不要继承 Docker「headless 即局域网」 |
| 后台 | `termux-wake-lock` + 可选 `termux-boot` 拉起脚本。文档写明 vivo 电池白名单。不承诺息屏 24 小时 |
| OAuth | 仍优先粘贴 token。若要做回环：用系统浏览器打开 `http://localhost:8045/auth/callback` 这条已有路由，并在 PA2553 的 Chrome 上验证。失败则维持粘贴，不引入自定义 scheme（那会变成路线 C 的事情） |
| 路径 | Termux 的 `HOME` 一般是 `/data/data/com.termux/files/home`，`dirs::home_dir()` 在设了 `HOME` 时可用。脚本显式导出 `ABV_DATA_DIR=$HOME/.antigravity_tools` |
| 自动更新 | `update_checker.rs` 的三个上游 URL、`tauri.conf.json` 的 updater endpoint **不要**在 Bionic 包里启用。本 fork 若以后发 Termux 包，用自己的 Release 资产名（例如带 `android-arm64` 或 `termux` 的 tarball），并在关于页链到 `Teee3047/Antigravity-Manager`。未实现前，更新按钮禁用 |
| 前端 | 修拖拽条；子路由刷新若复现，headless 构建 `base: "/"`。触控热区不够大就只改导航和主按钮，不重做页面 |
| 安装 | 一个 `scripts/termux-install.sh`：检查 `uname -m` 为 `aarch64`，下载本 fork Release 的 server-only 包和 `dist/`，写一个 `sv` 或前台启动脚本。脚本里不要 `curl \| bash` 指到 `lbjlaq` 的 `install.sh`（那个脚本装的是 deb / rpm / AppImage） |

### 4.3 路线 C 相对 B 还要多做的（非 v1）

- `minSdk` 至少覆盖 PA2553 的系统版本（版本号未知，实施前在机器上读一次）
- 前台服务 + 通知渠道；WebView 只允许 `http://127.0.0.1:8045`，禁止任意导航
- 明文流量：仅放行 loopback，不设全局 `usesCleartextTraffic`
- 二进制从 `nativeLibraryDir` 执行；数据目录用 `Context.getFilesDir()`，传给 `ABV_DATA_DIR`
- 不要申请存储权限来扫桌面 IDE 的 `state.vscdb`（平板上没有）
- applicationId 与上游 `com.lbjlaq.antigravity-tools` 区分开
- 关于页放 CC 署名。不上 Play 商店（非商业许可证，且应用形态是本地账号代理，审核风险另说）

## 5. 阶段与第一块垂直切片

### M0 — 本变更

只增加这份计划并开草稿 PR。不改 Rust / 前端行为。

### M1 — 垂直切片（路线 A）

目标：PA2553 上不用改协议代码，先看到 Web UI，并完成一次本机反代调用。

建议操作顺序（**尚未在该平板执行**，实施 M1 时逐条核对；失败就停，不要改去走 Tauri Android）：

1. 在一台 Linux arm64（或与 `release.yml` 相同的 `ubuntu-24.04-arm` 环境）构建，依赖包与该 workflow 的 “Install dependencies (Linux)” 步骤一致，另外按 `docker/Dockerfile` 准备 Go（`rquest` / BoringSSL 需要）。顺序：
   - `npm ci --legacy-peer-deps && npm run build`
   - `cd src-tauri && cargo build --release --bin antigravity-tools`
2. 平板安装 Termux，执行 `pkg update && pkg install proot-distro`，`proot-distro install debian`，`proot-distro login debian`。
3. Debian 内安装运行库，对齐 `docker/Dockerfile` 最终阶段的 `apt-get install` 列表（`curl`、`ca-certificates`、`libssl3`、`libsqlite3-0`、`libgtk-3-0`、`libwebkit2gtk-4.1-0`、`libayatana-appindicator3-1`、`librsvg2-2`）。包名在 Debian 新版本里可能带 ABI 后缀，以 `apt-cache search` 为准。
4. 把二进制和 `dist/` 拷进 proot（`adb`、或 Termux 存储目录再 `cp`）。不要使用 AppImage 的 FUSE 运行方式。
5. 启动：

```bash
export ABV_DIST_PATH=/opt/antigravity/dist
export ABV_DATA_DIR=/root/.antigravity_tools
export ABV_BIND_LOCAL_ONLY=1
export ABV_API_KEY='替换成自己的 key'
export ABV_WEB_PASSWORD='替换成另一串密码'
export RUST_LOG=info
./antigravity-tools --headless
```

6. Termux **外面**（Android 侧）安装 Termux:API 后执行 `termux-wake-lock`。在 vivo 电池设置里把 Termux 设为无限制。这一步的菜单位置以系统为准，本仓库没有 vivo 的截图。
7. 平板浏览器打开 `http://127.0.0.1:8045/`。用 `ABV_WEB_PASSWORD` 登录（未设置时 headless 会退回 API Key，见 `docker/README.md`）。在账号页粘贴一条已有 refresh token，而不是走 OAuth。
8. 在 Termux 或 proot 里对 `http://127.0.0.1:8045/v1/models` 发一次带 `Authorization: Bearer <ABV_API_KEY>` 的请求。再从使用者真正要用的客户端发一次最短对话。上游失败时看 `ABV_DATA_DIR/logs/`，不要先改 mapper。

**M1 成功标准（全部满足才算切片完成）：**

- 进程在 proot 里监听 `127.0.0.1:8045`，`/health` 返回成功
- 浏览器能打开仪表盘并保持登录（刷新根路径不白屏）
- 粘贴的账号出现在列表里，配额刷新要么成功，要么给出上游错误而不是 Rust panic
- 一次 `/v1/models` 或一次最短 chat/completions 走完本机反代（允许上游 4xx，只要请求确实从平板发出并写进 `proxy_logs.db` 或日志）
- `ss` 或日志显示绑定的是 `127.0.0.1` 而不是 `0.0.0.0`
- 数据目录在 proot 内重启后还在（账号还在）
- 关于或文档中能看到上游仓库名和 CC BY-NC-SA，且没有把这个包称为官方 Android 版

**M1 失败时的退路：** 记录缺哪个动态库、`ldd` 输出、以及是 proot 系统调用失败还是 GTK 初始化失败。下一步才是 M2 的 server-only，而不是换 Tauri Android。若二进制能启动但浏览器打不开 `127.0.0.1`，先在 proot 里 `curl 127.0.0.1:8045/health`，区分「服务没起来」和「Chrome 与 Termux 回环是否互通」。后者是开放问题里要在 vivo 上确认的事。

### M2 — 让 Web UI 在这块屏上能每天用

仍是路线 A 的二进制也可以做，但最好和 M3 的 feature 一起，避免分叉两套补丁。

- `Layout.tsx` 拖拽条只在 Tauri 里调用
- 验证子路由刷新；需要的话 headless 构建使用 `base: "/"`
- 关闭或隔离指向上游桌面 Release 的更新提示
- 把「批量导入 / 分钟级统计 / IDE 补丁」在 Web 上的失败收成明确提示，而不是未捕获异常。不要求把这些命令全部补进 `COMMAND_MAPPING`
- 顶栏和主按钮在触控下能点中（`NavMenu.tsx` 已有窄屏布局，查的是热区，不是新视觉）

### M3 — 路线 B：去掉桌面链接，Termux 原生包

成功标准：`pkg` 环境里不安装 GTK / WebKit，`ldd` 或 `readelf` 看不到 `libgtk` / `libwebkit`；`./antigravity-tools --headless`（或 server-only 的默认启动）重复 M1 的功能标准；安装步骤写成脚本并在 PA2553 上跑通一次。

### M4 — 仅当 M1/M3 保活不够

Kotlin 前台服务，见 4.3。成功标准：屏幕关闭、WebView 划掉之后，通知还在，`/health` 仍通，至少 30 分钟（时长在 vivo 上实测后再写死）。这不是 v1。

## 6. v1 明确不做

- 与桌面版功能对齐：托盘、Mini 悬浮窗、开机自启插件、单实例、窗口几何、macOS/Windows 快捷方式
- 在平板上切换 Antigravity IDE / `agy` 钥匙串 / `state.vscdb` / 设备指纹绑定到桌面客户端（`modules/db.rs`、`modules/device.rs`、`HeadlessIntegration` 对 `agy` 的明确错误）
- 启动或修补 Claude Desktop、Homebrew cask、cloudflared 公网隧道
- 把 `COMMAND_MAPPING` 缺的统计与批量导入全部补完
- Tauri Android、Capacitor、UniFFI、Kotlin 重写 UI
- Play 商店、自动更新成本 fork 的 APK、使用上游 `updater.json` 和上游公钥
- 修改协议转换、模型路由、Chrome123 仿真（除非 M1 证明上游在平板网络下拒绝该指纹，那是单独的问题）
- iOS、ChromeOS、Android 手机小屏适配
- 商用授权、改许可证
- 向 `lbjlaq/Antigravity-Manager` 提交本计划或后续移植
- 根治 vivo 省电。v1 只文档化白名单和唤醒锁，不承诺后台常驻

## 7. 风险

| 风险 | 为什么严重 | 怎么收 |
| --- | --- | --- |
| proot + WebKit 太重或被 vivo 杀掉 | v1 的进程模型就是这个 | M1 用唤醒锁和电池白名单实测。失败再做 M3/M4，不在 M1 里换架构 |
| `rquest` / BoringSSL 在 Bionic 上编不过 | 上游指纹依赖它，不能换成普通 reqwest | M3 单独排期。M1 用 glibc 构建绕开这个问题 |
| Chrome 访问不到 Termux 的 `127.0.0.1` | 管理 UI 和本机客户端都靠回环 | M1 第 8 步先在 proot 内 curl，再在 Chrome 里开。若只有 Chrome 失败，再查 vivo 是否隔离回环；那会直接抬高路线 C 的优先级 |
| `machine-uid` 在 proot 里为空或每次变化 | `crypto.rs` 会解不开已保存的密码 | v1 用环境变量注入。M3 再决定是否换密钥来源 |
| 用户点更新装到上游桌面安装包 | `update_checker.rs` 与 `tauri.conf.json` 写死了 `lbjlaq` | M1 手动关自动检查。M2 起禁用该入口 |
| OAuth 回环或 client 被拒 | redirect 是 `http://localhost:...`（`oauth_server.rs` 与 `get_oauth_redirect_uri`） | v1 不依赖 OAuth，用已有 refresh token |
| 子路由刷新白屏 | `vite.config.ts` 的 `base: "./"` | 书签只用根 URL；M2 再改 base |
| 许可证误用 | CC BY-NC-SA，且禁止暗示官方 | 关于页署名；不分发收费包；APK id 与上游区分 |
| headless 默认监听所有网卡 | `lib.rs` 在未设置 `ABV_BIND_LOCAL_ONLY` 时打开 `allow_lan_access` | 启动命令写死该变量 |

## 8. 开放问题

1. PA2553 的 Android 版本、WebView 主版本、是否已安装 Termux、存储空间还剩多少。决定 M1 能不能在机上编译（不建议）以及 M4 的 `minSdk`。
2. 在这台 vivo 上，Chrome 是否能访问 Termux / proot 监听的 `127.0.0.1:8045`。Android 一般共享回环，但是否被厂商改过，仓库无法证明。
3. proot Debian 里 `machine_uid::get()` 的值跨重启是否稳定。
4. `termux-wake-lock` 加电池白名单之后，息屏多久进程还在。没有这个数据就不能判断要不要做 M4。
5. arm64 `.deb` 解压后的 `ldd` 在 proot 里缺哪些库。`docker/Dockerfile` 的列表是 glibc 容器，不一定等于 Debian proot 的包名。
6. `tauri_build::build()` 在「只 `cargo build --bin`、但 `dist/` 已生成」时是否还要求其它 Tauri 资源。Dockerfile 是这么构建的，所以预期可以；若失败，以构建日志为准，不要改去 `tauri build` 出 AppImage。
7. server-only 的 CLI 形态：还要不要保留 `--headless` 这个词，以及 `cli_handler.rs` 的 `switch` 在没有桌面宿主时是隐藏还是保留并返回现有的 headless 错误。
8. 将来 APK 的 applicationId，以及启动器上是否继续使用「Antigravity Tools」这个名字。商标不在 CC 许可范围内，需要 Teee 定。
9. 本 fork 的 Release 是否要发 linux aarch64 测试包。现有 `release.yml` 会发布版本，不适合拿来打一次性试验包。
10. Google 是否接受从平板浏览器回到 `http://localhost:8045/auth/callback`。v1 不阻塞在这个问题上。
