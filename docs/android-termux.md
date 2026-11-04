# 平板安装：Termux + proot Debian / Tablet install

这是 **非官方** 的 headless 用法，不是 Antigravity 官方 Android 版，也不是 APK。许可证是 [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/)：个人非商业使用可以，不要拿去卖，分发时保留 `LICENSE` 和 `ATTRIBUTION.txt`。上游仓库是 [lbjlaq/Antigravity-Manager](https://github.com/lbjlaq/Antigravity-Manager)，本 fork 是 [Teee3047/Antigravity-Manager](https://github.com/Teee3047/Antigravity-Manager)。

This is an **unofficial** headless setup, not an official Android app and not an APK. The license is CC BY-NC-SA 4.0: personal non-commercial use is allowed. Keep `LICENSE` and `ATTRIBUTION.txt` if you pass the bundle on. Upstream is lbjlaq/Antigravity-Manager. This fork is Teee3047/Antigravity-Manager.

浏览器打开的是本机已有的 Web 管理界面。进程是 Linux glibc 二进制，跑在 Termux 的 Debian 里，用现成的 `--headless`。不要把这个二进制直接丢进 Termux（那是 Bionic，对不上）。不要安装上游的 Windows / macOS / Linux 桌面安装包来「更新」它。

The browser opens the existing local Web UI. The process is a glibc Linux binary inside Termux's Debian, started with the existing `--headless` flag. Do not run that binary directly in Termux (Bionic will not load it). Do not install upstream desktop packages as an update.

目标机是 arm64 平板（vivo PA2553 / Dimensity 9300+ 属于这一类）。下面的步骤还没有在这台 vivo 上执行过。文末列出了必须在真机上确认的点。

The target is an arm64 tablet. These steps have not been executed on the vivo PA2553. The last section lists what still needs that device.

## 0. 安装 Termux / Install Termux

**中文**

1. 从 [F-Droid 的 Termux](https://f-droid.org/packages/com.termux/) 安装。不要用 Play 商店里的旧包。
2. 打开 Termux，执行：

```bash
pkg update
pkg install -y proot-distro tar
```

**English**

1. Install [Termux from F-Droid](https://f-droid.org/packages/com.termux/). Do not use the outdated Play Store build.
2. In Termux:

```bash
pkg update
pkg install -y proot-distro tar
```

## 1. 拿到 linux/aarch64 安装包 / Get the linux/aarch64 bundle

安装包里有 `antigravity-tools`、`dist/`（网页）、`run-headless.sh`、`termux-setup.sh`、`LICENSE`、`ATTRIBUTION.txt`。架构文件 `BUNDLE_ARCH` 必须是 `aarch64`。

The archive contains `antigravity-tools`, `dist/` (the web UI), `run-headless.sh`, `termux-setup.sh`, `LICENSE`, and `ATTRIBUTION.txt`. `BUNDLE_ARCH` must say `aarch64`.

### 1A. 从本 fork 的 Actions 下载 / Download the Actions artifact

本仓库的 workflow `.github/workflows/headless-bundle.yml` 会在 `ubuntu-24.04-arm` 上打 `dist-bundles/antigravity-headless-linux-aarch64.tar.gz`，并作为名为 `antigravity-headless-linux-aarch64` 的 artifact 上传。它 **不会** 创建 GitHub Release，也 **不会** 写入上游的 `updater.json`。

Artifact 大约保留 14 天。到本 fork 的 Actions 页，打开 **Headless bundle** 那次运行，下载这个文件。不要去 `lbjlaq/Antigravity-Manager` 的 Releases 里下桌面 AppImage / deb 当作平板包。

The workflow `.github/workflows/headless-bundle.yml` builds `antigravity-headless-linux-aarch64.tar.gz` on `ubuntu-24.04-arm` and uploads it as an artifact. It does not publish a Release and does not write upstream `updater.json`.

Artifacts are kept for about 14 days. On this fork's Actions tab, open the **Headless bundle** run and download that file. Do not use desktop AppImage or deb files from lbjlaq/Antigravity-Manager releases as the tablet bundle.

如果这次 PR 的 arm 任务没跑起来（runner 不可用或失败），用 1B。失败时以 Actions 日志为准，不要改去编 Tauri Android。

If that arm job did not run or failed, use 1B. Follow the Actions log. Do not switch to a Tauri Android build.

### 1B. 在一台 Linux aarch64 上自己编 / Build on Linux aarch64

依赖与 `.github/workflows/release.yml` 的 Linux 步骤以及 `docker/Dockerfile` 里给 `rquest` 用的 Go / cmake / clang 相同。在仓库根目录：

```bash
bash scripts/build-headless-bundle.sh
```

成功时打印 `dist-bundles/antigravity-headless-linux-aarch64.tar.gz`。脚本在非 Linux 上会直接退出。在 x86_64 上编出来的包不能放进这台平板。

在平板的 proot 里从源码编也行，但要装完整的 GTK/WebKit 编译依赖和 Rust、Node，时间和磁盘都大，而且没有在 PA2553 上试过。优先用 1A 或另一台 aarch64 Linux。

Match the Linux packages from `.github/workflows/release.yml` and the Go/cmake/clang packages `docker/Dockerfile` installs for `rquest`. From the repo root:

```bash
bash scripts/build-headless-bundle.sh
```

A successful build prints `dist-bundles/antigravity-headless-linux-aarch64.tar.gz`. The script refuses to run on non-Linux. An x86_64 archive will not run on this tablet.

Compiling inside the tablet's proot is possible and untested. It needs the full GTK/WebKit toolchain plus Rust and Node. Prefer 1A or another aarch64 Linux machine.

## 2. 把压缩包放进 Termux / Copy the archive into Termux

**中文**

1. 用 U 盘、网盘或 `adb` 把 `antigravity-headless-linux-aarch64.tar.gz` 放到平板的 Download 目录。
2. 在 Termux 里：

```bash
termux-setup-storage
cd ~
tar -xzf storage/downloads/antigravity-headless-linux-aarch64.tar.gz
cd antigravity-headless
cat BUNDLE_ARCH
```

`cat BUNDLE_ARCH` 应该打印 `aarch64`。然后看一眼 `ATTRIBUTION.txt`。

**English**

1. Put `antigravity-headless-linux-aarch64.tar.gz` in the tablet's Download folder.
2. In Termux:

```bash
termux-setup-storage
cd ~
tar -xzf storage/downloads/antigravity-headless-linux-aarch64.tar.gz
cd antigravity-headless
cat BUNDLE_ARCH
```

`BUNDLE_ARCH` must print `aarch64`. Read `ATTRIBUTION.txt`.

如果压缩包不在 Download，把 `tar -xzf` 的路径换成实际位置。解压后当前目录里要有 `antigravity-tools`、`dist/index.html`、`termux-setup.sh`、`run-headless.sh`。

If the archive is not in Download, change the `tar` path. After unpacking you need `antigravity-tools`, `dist/index.html`, `termux-setup.sh`, and `run-headless.sh` in the current directory.

## 3. 安装 Debian 和动态库 / Install Debian and libraries

在 **Termux** 里，就在解压后的目录中执行：

```bash
bash termux-setup.sh
```

脚本会：

- 安装 `proot-distro`。是否已有 Debian 看 `proot-distro list` 和 `proot-distro login debian`，不看旧目录在不在
- 把当前目录用 `tar` 送进 `proot-distro login debian`，落到 `/opt/antigravity-headless`
- 在 Debian 里安装运行库：`ca-certificates`、`libssl3`（或 `libssl3t64`）、`libsqlite3-0`、`libgtk-3-0`（或 `libgtk-3-0t64`）、`libwebkit2gtk-4.1-0`、`libayatana-appindicator3-1`、`librsvg2-2`、`curl`

这些库和 `docker/Dockerfile` 最终阶段是同一类。headless 用的是带 GTK/WebKit 链接的同一个二进制，所以即使用 `--headless` 也要装它们。

脚本最后跑 `ldd`。如果还有 `not found`，它会把缺的库打出来并失败。这时不要继续打开浏览器。把缺的包名用 `apt-get install` 装上，再执行：

```bash
proot-distro login debian -- /bin/bash /opt/antigravity-headless/termux-setup.sh --inside
```

From **Termux**, in the unpacked directory:

```bash
bash termux-setup.sh
```

The script installs proot-distro, treats Debian as present when `proot-distro list` or `proot-distro login debian` says so, and streams this directory into the guest with `tar`. It does not decide that from the old `installed-rootfs` directory. The headless binary is the same GTK/WebKit-linked binary as the desktop build, so those libraries are required even with `--headless`.

It then runs `ldd`. If any line says `not found`, it exits and prints them. Install those packages and re-run the `--inside` command above. Do not open the browser yet.

proot-distro 当前拉到的 Debian 版本可能让包名带 `t64` 后缀。脚本会按候选名逐个试。如果候选全部失败，以 `apt-cache search webkit2gtk` 的结果为准，这是真机上才会知道的事。

The Debian release inside proot may use `t64` package names. The script tries the candidates it knows. If every candidate fails, use `apt-cache search webkit2gtk` on the device.

### Debian 已经装好，但旧目录不存在 / Debian is listed, old rootfs path is missing

当前 Termux 里的 proot-distro 把系统放在：

```text
$PREFIX/var/lib/proot-distro/containers/debian/rootfs
```

下面这个旧路径可以不存在，`ls` 报 `No such file or directory` 是正常的：

```text
$PREFIX/var/lib/proot-distro/installed-rootfs/debian
```

这时 `proot-distro list` 仍然显示 `debian`，`proot-distro login debian -- pwd` 仍然打印 `/root`。不要再执行 `proot-distro install debian`。再装一次会失败，错误是 `container 'debian' already exists`。也不要 `proot-distro remove debian`，那会把已经装好的系统删掉。

用这份更新过的 `termux-setup.sh` 时，直接在解压目录里重新执行 `bash termux-setup.sh` 即可。脚本看到 list 或 login 成功就跳过 install，再用 tar 把文件送进 guest。

如果平板上还是旧脚本，先不要重装 Debian。在解压后的目录里手工做下面这几步（和脚本同一条路）：

```bash
proot-distro login debian -- pwd
proot-distro login debian -- rm -rf /opt/antigravity-headless
proot-distro login debian -- mkdir -p /opt/antigravity-headless
tar -C "$PWD" -cf - . | proot-distro login debian -- tar -C /opt/antigravity-headless -xf -
proot-distro login debian -- /bin/bash /opt/antigravity-headless/termux-setup.sh --inside
```

`pwd` 应打印 `/root`。`/opt` 在复制前是空的，这没关系。复制之后再跑 `--inside`。

Current proot-distro stores the guest at `$PREFIX/var/lib/proot-distro/containers/debian/rootfs`. The legacy directory `$PREFIX/var/lib/proot-distro/installed-rootfs/debian` may be missing. `proot-distro list` can still show `debian`, and `proot-distro login debian -- pwd` still prints `/root`. Do not run `proot-distro install debian` again: the error is `container 'debian' already exists`. Do not run `proot-distro remove debian`; that deletes the guest.

With this updated `termux-setup.sh`, run `bash termux-setup.sh` again from the unpacked directory. It skips install when list or login succeeds, then streams the bundle in with tar.

If the tablet still has the old script, stay in the unpacked directory and run the commands above. `pwd` should print `/root`. An empty `/opt` before the copy is expected. Run `--inside` after the copy.

## 4. 启动 / Start

在 Termux 里：

```bash
proot-distro login debian -- /opt/antigravity-headless/run-headless.sh
```

保持这个会话不要关。第一次启动会在 Debian 里生成：

```text
/root/.antigravity_tools/tablet.env
```

终端会打印一次 Web 密码和 API Key。之后再次启动不再打印。忘记了就执行：

```bash
proot-distro login debian -- cat /root/.antigravity_tools/tablet.env
```

`run-headless.sh` 固定设置：

| 变量 | 值 | 作用 |
| --- | --- | --- |
| `ABV_DIST_PATH` | 安装包里的 `dist/` | 托管网页 |
| `ABV_DATA_DIR` | `/root/.antigravity_tools` | 账号和 `gui_config.json` |
| `ABV_BIND_LOCAL_ONLY` | `1` | 只监听 `127.0.0.1`，不对 Wi-Fi 开放 |
| `ABV_DISABLE_UPDATES` | `1` | 不请求上游桌面更新 |

日志里应出现 `Web UI (this machine): http://127.0.0.1:8045/` 和 `Listening on 127.0.0.1 only`。端口以日志为准；默认配置是 8045（`src-tauri/src/proxy/config.rs`）。

In Termux:

```bash
proot-distro login debian -- /opt/antigravity-headless/run-headless.sh
```

Leave that session open. The first start creates `/root/.antigravity_tools/tablet.env` and prints the Web password and API key once. Read the file later with the `cat` command above.

The launcher binds `127.0.0.1` only and disables desktop auto-update. The log should include `Web UI (this machine): http://127.0.0.1:8045/` and `Listening on 127.0.0.1 only`.

停掉服务用 Ctrl-C。这不是 Android 前台服务，息屏之后 vivo 可能把 Termux 杀掉。v1 不解决这件事。可选、且未在这台平板上验证的做法：安装 [Termux:API](https://f-droid.org/packages/com.termux.api/)，在 **Termux 里而不是 Debian 里** 执行 `termux-wake-lock`，并在系统电池设置里把 Termux 设为不受限制。菜单名称以 vivo 系统为准。

Stop with Ctrl-C. This is not an Android foreground service. The vendor may kill Termux when the screen is off. v1 does not fix that. An optional, unverified step is `termux-wake-lock` from Termux:API plus a battery whitelist. The vivo menu names are not documented here.

## 5. 打开网页 / Open the UI

在平板自己的 Chrome（或系统浏览器）地址栏输入下面这一行，不要写成 `localhost`。进程只绑 `127.0.0.1`；有的系统上 `localhost` 会先走到 `::1`，页面就打不开。

```text
http://127.0.0.1:8045/
```

书签用这个根地址。登录框里填 `tablet.env` 的 **`ABV_WEB_PASSWORD`**。两个都设置了的时候，管理页不接受 API Key（`src-tauri/src/proxy/middleware/auth.rs`：管理接口在有 `admin_password` 时只认这一个）。

账号页在浏览器里默认是「粘贴 token」，不是桌面 OAuth。粘贴一条已有的 refresh token。v1 不把 OAuth 回环当作成功条件。

In the tablet's own browser open `http://127.0.0.1:8045/`. Type that IPv4 address; `localhost` can resolve to `::1` while the process listens only on `127.0.0.1`. Bookmark the root URL. Log in with `ABV_WEB_PASSWORD`. When both values are set, the admin UI rejects the API key.

In the browser the account dialog defaults to pasting a refresh token, not the desktop OAuth flow. v1 does not require the OAuth loopback to work.

给本机上的其他客户端用的地址是：

```text
http://127.0.0.1:8045/v1
```

请求头 `Authorization: Bearer <ABV_API_KEY>`。同一 Wi-Fi 上的电脑访问不到，这是 `ABV_BIND_LOCAL_ONLY=1` 的结果。

Other apps on this tablet use `http://127.0.0.1:8045/v1` with `Authorization: Bearer <ABV_API_KEY>`. Other devices on the Wi-Fi cannot connect.

可以先在 Debian 里确认服务本身是通的（另开一个 Termux 会话）：

```bash
proot-distro login debian -- curl -fsS http://127.0.0.1:8045/health
```

返回里应有 `"status":"ok"`。这一步通过、但平板浏览器打不开，才是「浏览器和 Termux 的回环是否互通」的问题，见文末。

In a second Termux session, `curl` the health URL inside Debian. `"status":"ok"` means the process is up. If curl works and Chrome does not, the open question is whether this phone's browser can reach Termux's loopback.

## 6. 换一个新包 / Replace the bundle later

不要点网页里的「检查更新」。浏览器模式不会走上游桌面更新器。设置页会说明这一点。

要升级：在 aarch64 上重新 `bash scripts/build-headless-bundle.sh`，把新的压缩包拷进平板，再执行一次 `bash termux-setup.sh`。它会覆盖 `/opt/antigravity-headless`，不会删除 `/root/.antigravity_tools` 里的账号。覆盖前先停掉正在跑的 `run-headless.sh`。

Do not use the in-app update check. The browser UI does not install upstream desktop builds. The About page says so.

To upgrade, build a new archive, copy it over, stop the old process, and run `bash termux-setup.sh` again. That replaces `/opt/antigravity-headless` and leaves `/root/.antigravity_tools` in place.

## 需要真机确认 / Still needs the tablet

vivo 上已经见过一种失败：`proot-distro list` 有 `debian`，`login` 能进 `/root`，但 `$PREFIX/var/lib/proot-distro/installed-rootfs/debian` 不存在，旧脚本因此去 `install`，得到 `container 'debian' already exists`。上面的检测和 tar 复制就是对着这个失败改的。本机用假的 `proot-distro` 跑过 `bash scripts/termux/termux-setup.sh --self-test`。平板上还没重跑过更新后的脚本。下面这些仍然要在 vivo 上确认：

1. 用更新后的脚本（或上面的手工 tar）把包送进已经存在的 Debian 之后，`libwebkit2gtk-4.1-0` 这些包名是否都能装上。装不上时以脚本打印的 `ldd` 为准。tar 若没把 `dist/index.html` 送进去，脚本会改到 `containers/debian/rootfs` 上复制；这条备用路径也还没在平板上走过。
2. Debian 里 `curl http://127.0.0.1:8045/health` 成功之后，平板 Chrome 是否也能打开同一个地址。
3. 登录、粘贴 refresh token、刷新配额、以及一次 `/v1/models` 或一次最短对话是否走完本机进程。上游返回 4xx 可以接受，前提是请求确实从平板发出，并且写进了数据目录里的日志或 `proxy_logs.db`。
4. 息屏之后进程还能活多久。v1 不保证后台常驻。
5. `tablet.env` 里的密码在重启 proot 之后是否还能解开 `gui_config.json` 里用机器 ID 加密的字段。启动脚本每次都会重新导出 `ABV_API_KEY` 和 `ABV_WEB_PASSWORD`，所以登录不依赖那份密文。

The vivo already hit one failure: `proot-distro list` shows `debian`, `login` reaches `/root`, and `$PREFIX/var/lib/proot-distro/installed-rootfs/debian` is missing, so the old script ran `install` and got `container 'debian' already exists`. The detection and tar copy above are the fix for that. `bash scripts/termux/termux-setup.sh --self-test` passed here against a fake `proot-distro`. The updated script has not been re-run on the tablet. These still need the vivo:

1. Whether the WebKit/GTK package names install after the updated script, or the manual tar commands, copies the bundle into the Debian that is already there. Trust the `ldd` output if they do not. If tar does not land `dist/index.html`, the script copies onto `containers/debian/rootfs` instead. That fallback has not been exercised on the tablet either.
2. Whether Chrome on the tablet can open `127.0.0.1:8045` after `curl` inside Debian succeeds.
3. Login, a pasted refresh token, a quota refresh, and one `/v1/models` or one short chat through the local process. An upstream 4xx is acceptable when the request left the tablet and was logged.
4. How long the process survives with the screen off. v1 does not promise a background service.
5. Whether passwords encrypted with the machine id in `gui_config.json` still decrypt after a proot restart. The launcher re-applies `ABV_API_KEY` and `ABV_WEB_PASSWORD` on every start, so login does not depend on that ciphertext.
