# 平板保活选项（vivo PA2553）

状态：只做选择，本轮不写保活代码。v1 安装步骤仍是 [android-termux.md](./android-termux.md)。路线背景在 [android-adaptation-plan.md](./android-adaptation-plan.md)。本文取代那份计划里「先靠 `termux-wake-lock`」和「M4 = 带 WebView 的 Kotlin 壳」这两句。

范围只限本 fork（[Teee3047/Antigravity-Manager](https://github.com/Teee3047/Antigravity-Manager)）。不向 `lbjlaq/Antigravity-Manager` 提 PR。与 DroidDeck 无关。

这不是官方 Android 版，也不是 Play 商店应用。许可证仍是 [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/)。个人非商业使用。以后如果打 APK，包内继续带 `LICENSE` 和 `ATTRIBUTION.txt`，applicationId 不得使用 `com.lbjlaq.antigravity-tools`。

监听语义保持 `ABV_BIND_LOCAL_ONLY=1`：只绑 `127.0.0.1`。`scripts/termux/run-headless.sh` 已经写死这个变量。本文没有理由改成局域网。

公开规格表把型号 PA2553 标成 vivo Pad5：Android 15，OriginOS 5，Dimensity 9300+。本仓库没有读过这台平板的「关于本机」。下面凡是写 OriginOS 5 / API 35 的地方，都以真机版本号为准。

## English verdict

Teee's report on this vivo: the headless proxy stays up while Termux sits in a small floating window, and it stops in workbench / multi-window and when the screen is off. That pattern is an OriginOS visibility freeze (or a static workbench preview), not a missing wake lock.

`termux-wake-lock` is real and worth turning on, and it is not a fix for this report. Current Termux already runs a foreground service (`TermuxService`) for the whole session. The command, from `termux-tools` rather than Termux:API, only adds a partial wake lock and a Wi-Fi lock on that service. A partial wake lock asks the CPU to stay runnable; Doze ignores that lock unless the app is also exempt from battery optimization. It does not make a paused freeform window count as foreground, and another app's notification cannot protect Termux's uid. On stock Android the lock plus an unrestricted-battery setting plus Termux's existing foreground service is often enough for a local server. On OriginOS the vendor has a separate background-power list, and community reports still describe overnight freeze after that list is set.

Do not build a babysitter APK. The next code, and only after the on-device matrix below fails, is a throwaway in-process loopback probe (`m4a-loopback-probe`): its own `specialUse` foreground service listens on `127.0.0.1` and does not run the Antigravity binary. If that probe dies the same way, a full host APK will die too, and the floating window stays the working setup. If the probe lives where Termux dies, the later host is `m4a-specialuse-host`, and it needs a Bionic server-only binary. Dropping proot inside Termux does not by itself change this kill surface. `dataSync` is the wrong foreground-service type on Android 15 (six-hour cap). Keep localhost-only binding.

## 1. 现场

Teee 在这台 vivo 上：

| 状态 | 反代 |
| --- | --- |
| Termux 以小浮窗留在屏幕上 | 能用 |
| 工作台 / 多窗 | 停 |
| 息屏 | 停 |

v1 文档已经写过：没有我们自己的前台服务，不保证息屏之后还在。本次把「停」拆开，因为后面每条路只对某一种「停」有效。

平板上还没记下的三件事，K0 要补上。在失败的那一刻：

1. 进程还在不在（`ps` 里还有没有 `antigravity-tools` / `proot`）。
2. 还在的话，连 `127.0.0.1:8045` 是超时，还是马上拒绝。
3. logcat 里是 `signal 9`、`Trimming phantom processes`、`excessive cpu`，还是厂商的 freeze / 冻结。

三种结果不是同一种故障：

| 现象 | 含义 | 唤醒锁有没有用 |
| --- | --- | --- |
| 进程还在，连接一直转到超时 | 进程被冻住，或者套接字不再被调度。小窗能恢复，符合 OriginOS 的应用冻结 / 工作台静态预览 | 基本没用。CPU 醒着也轮不到这段被冻住的代码 |
| 进程消失，日志是 signal 9 / phantom / excessive cpu | Android 12 起的子进程回收。Termux 主进程和它的通知可以还在 | 没用。锁拿在 Termux 主进程上，被杀掉的是子进程 |
| 进程消失，没有上述日志 | 厂商直接杀 uid，或用户划掉了任务 | 没用。要先看是不是「允许后台高耗电」没开 |

公开资料和这次现场对得上的是第一种，而且工作台是亮屏发生的，所以不是 Doze。这个判断在 K0 记完之前仍然是判断，不是实测。

## 2. 现在谁在听 8045

```text
vivo / OriginOS
  com.termux
    TermuxService          前台服务，会话在时就有通知
      shell 会话
        proot              ptrace
          Debian
            antigravity-tools --headless
              只听 127.0.0.1:8045
```

`run-headless.sh` 跑在 Debian 里面。它改不了 Android 的进程优先级，也调不到 `termux-wake-lock`（客人系统里没有 `am`）。浏览器只是管理页，关掉浏览器不会顺带保住这个进程，也不会是这次被杀的原因。

本仓库没有自己的 Service、通知或 APK。`src-tauri/` 里没有 Android 工程。

## 3. 对原先假设的核对

假设是：厂商杀后台是主因；单独的 Termux 唤醒锁在 vivo 上不够；可能必须有一个真正的 Android 前台服务（带通知）。

核对结果：

1. 主因是厂商的后台策略。现场（小窗活、工作台和息屏停）跟「应用不在受保护的可见状态就被冻」一致，跟「忘了拿唤醒锁」不一致。亮屏的工作台停掉，说明当时 CPU 没有睡。
2. 单独的 `termux-wake-lock` 不够。它应该打开，用来挡住真正的 CPU 休眠，但挡不住这次报告的两种停法。
3. 「再做一个前台服务」只说对了一半。Termux 会话本身已经是前台服务。再发一条 `termux-notification --ongoing` 不会多出一个生命周期。另一个 APK 的前台服务保护的是那个 APK 自己的 uid。能改变杀伤面的前台服务，是**自己听 8045 的那个进程**上的服务。在 OriginOS 上，这个服务仍然要进厂商的后台白名单；白名单也不是 24 小时承诺。

## 4. 选项 A — 只动 Termux 和系统设置

这一档不改本仓库的二进制。K0 用的就是这一档。它可能让息屏好转，工作台则更可能仍然失败。

### A1. `termux-wake-lock`

当前 F-Droid 版 Termux 里，这条命令属于 `termux-tools`，不需要安装 Termux:API。脚本做的事是：

```text
am startservice --user 0 \
  -a com.termux.service_wake_lock \
  com.termux/com.termux.app.TermuxService
```

`TermuxService` 收到后做三件事：拿 `PARTIAL_WAKE_LOCK`（标签 `termux:service-wakelock`），拿一把高性能 Wi-Fi 锁，并在系统还没忽略电池优化时弹出原生对话框。通知文案里会出现 wake lock 已拿住。通知上的同一颗按钮走的是同一个 action。

在 **Termux 里**执行，不要在 `proot-distro login` 之后执行。命令把输出重定向掉了，退出码不能当成功。成功的标志是通知里写着锁还在。

这把锁的能力：

- 在设备还没进入 Doze 时，要求 CPU 保持可调度。屏幕可以仍然是灭的。
- 它本身不是 Doze 豁免。Doze 开始之后，不在电池白名单里的应用，这把锁会被忽略，网络也会被推迟。豁免来自「电池不受限制」那张名单，加上 Termux 已经在跑的前台服务。三样一起，才是原生 Android 上本机服务的常规做法。
- Wi-Fi 锁对 `127.0.0.1` 没有意义。回环不走无线网。

这把锁不做的事：

- 不把工作台里失焦的窗口抬成前台。
- 不解除 cgroup freezer。进程已经被冻住时，锁拿在同一个 uid 里也跑不到。
- 不保护子进程不被 phantom process killer 收掉。Termux 维护者记过：锁在主进程上，被 SIGKILL 的是 shell 子进程，通知可以还显示「0 sessions (wake lock held)」。
- 原生电池对话框不等于 OriginOS 的「允许后台高耗电」。两个开关都要看。vivo 上那个原生对话框可能不出现，或者出现了也不控制厂商自己的冻结名单。

库存 Android（Pixel 一类）上，前台服务、这把锁、电池「不受限制」三样一起，本机服务通常扛得住息屏。这是 Termux 社区的常规做法，不是这台 Pad 的记录。锁单独一项，在 Doze 里站不住。

### A2. 通知和前台服务

会话还在时，Termux 已经 `startForeground()`。通知栏里的 Termux 就是这个前台服务。

`termux-notification --ongoing` 走 Termux:API，用 `NotificationManager` 发一条划不掉的通知。它不把 shell 提升成另一个前台服务。保活价值可以忽略。需要一个「人眼能看见还活着」的提示时才用。

### A3. 电池白名单：原生和 OriginOS 不是同一个开关

原生 Android 的 Doze 白名单：

- 设置 → 应用 → Termux → 电池 → 不受限制
- 对应 `dumpsys deviceidle whitelist` 里的 `com.termux`
- 拿唤醒锁时 Termux 可能自己弹出这个页面

OriginOS 另外还有自己的名单。菜单名称以这台平板的搜索框为准，本仓库没有 vivo 的截图。公开的 OriginOS 路径是：

- 设置里搜索「后台耗电管理」或「后台高耗电」→ Termux → **允许后台高耗电**
- i 管家 → 应用管理 → 权限管理 → 自启动 → Termux 打开
- 最近任务里把 Termux **锁定**，避免一次「清除全部」把它划掉

华为帮助页把 vivo / iQOO 的「允许后台活动」也指到「后台耗电管理 → 允许后台高耗电」。OriginOS 1 的使用记录里，这三项做完之后，整夜息屏仍可能假死，亮屏后再进一次应用才恢复。那是手机、旧系统的记录，不是 PA2553 的记录，所以 K0 要把「30 分钟」和「过夜」分成两行。

只做原生「不受限制」、不做「允许后台高耗电」，在 OriginOS 上通常不够。只做厂商开关、不拿 partial wake lock，则应用即使没被冻，息屏后 CPU 仍可能睡，回环在睡眠窗口里不应答。两个都做。

### A4. 小窗是目前这台机器上唯一对过现场的办法

小浮窗让 Termux 保持可见。OriginOS 的冻结看的是「还算不算前台」，可见窗口算。工作台 / 多窗里，没被点中的那一格可以被暂停。vivo 对另一台 OriginOS 设备的「原子工作台」说明里写过：过热、低电、游戏、视频通话时，原子窗会变成静态预览。PA2553 的工作台是不是同一种预览，要在真机上看；如果是，缩略图还在，进程已经不跑。这和「小窗活、工作台停」一致。

把小窗写成产品：用户已经在用，安装文档把它标成当前权宜，不自动化。自动弹出 1 像素 Activity、悬浮窗权限（`SYSTEM_ALERT_WINDOW`）或无障碍服务，是厂商专门打击的保活手法，也把一个本机代理做成了看起来像常驻监控的东西。不进下一刀。

### A5. 重启类工具不解决「冻住」

| 工具 | 实际作用 |
| --- | --- |
| `termux-services`（runit） | Termux 还活着时，把崩溃的子进程拉起来。uid 被冻住时，runit 一起冻住 |
| Termux:Boot | 只在开机广播里跑。不在息屏被冻时跑。装完必须手动打开一次 Boot 应用，系统才登记这个接收器 |
| `nohup` | 只防终端挂断。Android 不看这个 |

这些可以以后当作「崩溃或重启之后怎么自己起来」的补充，不排进这次保活。

### A6. 幽灵进程：只有日志对得上才做

Android 12 起，`ActivityManager` 监视应用 fork 出来、又不是系统组件的子进程（phantom process）。`proot`、guest 里的 shell、`antigravity-tools` 都是 `com.termux` 的这类子进程。

公开实现（agnostic-apollo 整理的 AOSP 行为，Termux 讨论里采用同一套）：

- 默认全局上限 32，是全机所有应用加在一起，不是每个应用 32。别的应用占满名额时，优先级更差的子进程先被杀。可见的前台应用排在后面，所以小窗有时能躲开，后台的 Termux（前台服务大约是 `oom_score_adj` 200）会先被剪。
- 另外每约 5 分钟查一次过度 CPU。子进程和主进程都会被查。这次现场更像立刻停，不太像 5 分钟配额；除非 K0 看到 `excessive cpu`，否则不要用这条解释工作台。
- 前台服务不把子进程移出这个名单。

Android 14 及更新的系统上，开发者选项里可能有 **Disable child process restrictions**（关闭子进程限制）。vivo 可能把它藏掉或改名。这个开关在开发者选项被关掉时会失效。对应的全局设置是：

```text
adb shell settings put global settings_enable_monitor_phantom_procs false
```

这是诊断开关，不是本仓库要装进启动脚本的步骤。只在 logcat 出现 `Trimming phantom processes` 或会话以 signal 9 结束、而且 K0 已经排除「进程还在只是冻住」之后，才在这台自己的平板上试。不要执行 `device_config set_sync_disabled_for_tests persistent`：那会停掉设备配置同步，副作用比这次故障大。

`adb shell dumpsys deviceidle whitelist +com.termux` 只重复原生 Doze 白名单，替代不了「允许后台高耗电」。

### A 档结论

先做 A 档的设置和 K0 记录。不把 A 档写成「已经能保活」。小窗继续当权宜。

## 5. 选项 B — 伴随 APK

### B0. 只负责把 Termux 保住的 APK：不做

Android 按 uid 冻结、按应用算 oom adj。APK 自己的前台服务、唤醒锁、常驻通知，都算在那个 APK 的 uid 上。Termux 是 `com.termux`，签名不同，不能 `sharedUserId`。

因此下面这些形态留不住现在的 8045：

- 空的前台服务，定时去连 `127.0.0.1:8045`
- 通过 Termux `RUN_COMMAND` 在 Termux 被冻住之后再投递一条命令
- 自己画一个悬浮窗，指望系统因此放过 Termux

`RUN_COMMAND` 还要求用户打开 Termux 的 `allow-external-apps`。它能在 Termux **已经允许跑**的时候代为执行脚本，不能把冻住的 uid 解冻。

### B1. 下一刀代码：`m4a-loopback-probe`

这是最小的、能在 vivo 上分出「前台服务到底算不算数」的实现。它不携带 Antigravity 二进制，也不代替现有的 headless。

只有 K0 失败才写它。K0 若已经让现有 `/health` 在息屏和工作台都活过 30 分钟，探针没有新信息，就停。

探针本身：

- 个人侧载的调试 APK。不上 Play。关于页写明非官方、CC BY-NC-SA 4.0、上游仓库和本 fork。启动器名称用「本机保活探针」，不把产品名扩到图标上。applicationId 用占位 `dev.teee3047.antigravity.keepalive.probe`，Teee 可以改，但不要用 `com.lbjlaq.antigravity-tools`。
- 一个 `specialUse` 前台服务，在**服务进程里**听 `127.0.0.1` 的一个探测端口（建议 `18045`，避开 8045）。请求来了就回一行纯文本。不要 `exec` 外部二进制。进程内监听才测得到「前台服务这个 uid」，而不是又制造一个 phantom 子进程。
- `targetSdk` 按这台平板的 API（公开规格是 35）。Android 14 起前台服务必须声明类型。
- 类型用 `specialUse`，并写 `PROPERTY_SPECIAL_USE_FGS_SUBTYPE`，例如本机回环保活探针。不要用 `dataSync` 或 `mediaProcessing`：应用 target 为 Android 15 时，这两类在后台合计只能跑 6 小时 / 24 小时，超时后 `onTimeout`，不 `stopSelf` 会把应用打崩。`shortService` 大约 3 分钟。`specialUse` 不在这条时限里。
- 同时拿 `PARTIAL_WAKE_LOCK`。
- 通知渠道要在 `startForeground()` 之前建好。Android 13 起先要到 `POST_NOTIFICATIONS`。用户拒绝通知的话，前台服务立不住，探针作废，这本身就是一条记录。
- 权限停在：`INTERNET`（让系统浏览器能连回环）、`FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_SPECIAL_USE`、`WAKE_LOCK`、`POST_NOTIFICATIONS`。不要 `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`：那个权限过不了 Play 审查，而我们本来就不上架；它也翻不动 OriginOS 的开关。界面上放两个入口：系统应用详情，以及一段文字说明去搜索「后台耗电管理 → 允许后台高耗电」。
- 套接字明确绑 `127.0.0.1`。不要 `0.0.0.0`。不提供局域网开关。不使用 VPN、无障碍、悬浮窗、开机广播。
- 明文只针对这次回环探测。不设置全局 `usesCleartextTraffic="true"`。
- 服务 `stopWithTask` 保持默认之外，要记录「从最近任务划掉」之后通知还在不在。OriginOS 经常在划掉时把前台服务一起杀掉。第一刀不承诺划掉后复活。

探针的通过标准（都在 PA2553 上）：

1. 通知还在，`ps` 里进程还在，USB `adb` 访问 `http://127.0.0.1:18045/` 在息屏 30 分钟后仍有响应。
2. 工作台里这个探针不是当前那格活窗口时，同样还有响应。
3. 小窗作为对照，应当有响应。
4. 监听地址是 `127.0.0.1`，不是 `0.0.0.0`。
5. 强行停止该应用之后探测失败。这是预期，不跟强行停止较劲。

判读：

| 探针结果 | 下一步 |
| --- | --- |
| 息屏和工作台都活 | Termux 这条链路的停，不是「OriginOS 连前台服务一起冻」。可以做 B2 |
| 和 Termux 一样停，进程还在只是不应答 | OriginOS 连 `specialUse` 前台服务也冻。再写承载反代的 APK 会同样停。保活停在小窗，不写 B2 |
| 进程被 signal 9，而服务进程里并没有子进程 | 记录 logcat 再决定。这种结果和「子进程被收」对不上，先别猜 |

### B2. 探针通过之后才做：`m4a-specialuse-host`

这是真正承载反代的 APK，现在不写。条件是 B1 通过，并且已经有 Bionic 的 server-only 二进制（适配计划里的路线 B）。现有的 glibc / GTK 二进制不能放进 APK。

形态：

- 同一个 `specialUse` 前台服务，无 WebView。管理页继续用平板浏览器打开 `http://127.0.0.1:8045/`。WebView 是以后的壳，不是保活所需要的。
- 二进制放在 `nativeLibraryDir`，文件名像 `libantigravity.so`，从那里 `exec`。Android 10 以后，应用私有目录的任意路径不能当普通可执行文件跑（W^X）。这是路线 C 里已经写过的约束。
- 进程环境固定 `ABV_BIND_LOCAL_ONLY=1`、`ABV_DISABLE_UPDATES=1`、`ABV_DATA_DIR` 指向 `Context.getFilesDir()`。不要去读 Termux 的 `/data/data/com.termux`，另一个 uid 读不到。
- 数据从 proot 的 `/root/.antigravity_tools` 迁出来是单独的一步，不塞进保活第一刀。
- `exec` 出来的服务进程仍然是 phantom 子进程。若父服务还在、子进程是 signal 9，再考虑把监听放进服务进程（in-process），那是更后面的一刀。不要在探针阶段就上 JNI。
- 关于页和资产里带本仓库 `LICENSE`、`ATTRIBUTION.txt`，写上上游 <https://github.com/lbjlaq/Antigravity-Manager> 和本 fork。禁止写成官方 Android 版。
- 不把 proot 或 Debian rootfs 打进 APK。proot 是 GPL-3.0，本仓库是 CC BY-NC-SA 4.0，两个许可证不能收成同一个合并作品。Termux + proot 继续作为 v1 的独立安装。

Tauri Android 和 Capacitor 仍然不做。反代要活在 Activity 停掉之后，这是 Service 的事；那两条壳都不提供这个进程模型，还要把桌面窗口、托盘和指向上游的更新器拖进来。

### B3. 安全和许可证（两条 APK 路线共用）

- 只绑 `127.0.0.1`。不增加「同一 Wi-Fi 可访问」的默认值，也不在探针里做这个开关。
- 不申请存储权限，不去扫桌面 IDE 的 `state.vscdb`。
- 不上架。CC BY-NC-SA 禁止以商业为主要目的分发；本地账号代理也不适合装成商店应用。
- 商标不在 CC 许可里。探针避开产品名。真正的 host APK 用什么启动器名字，仍由 Teee 定（适配计划开放问题 8）。

## 6. 选项 C — Termux 里改跑 Bionic，去掉 proot

适配计划的路线 B 仍然值得做：去掉 GTK / WebKit，减小内存，让以后的 host APK 有一个可执行文件。它**不**是这次保活的修复。

杀伤面在 Android uid，不在 glibc：

- Bionic 二进制若仍由 Termux 会话拉起，它还是 `com.termux` 的子进程，phantom 名单和 OriginOS 冻结照旧。
- proot 多几个进程、多用 ptrace。进程数离全局 32 很远，除非别的应用已经占满。ptrace 不是「小窗活、工作台停」这种按窗口状态发生的现象的解释。
- 内存变小，只降低低内存杀手（LMK）在整机吃紧时先杀它的概率。现场是一切到工作台或息屏就停，不像内存压力。

所以不要为了保活先做 Bionic 移植。Bionic 是 B2 的前置，排在探针之后。

## 7. 取舍

| 路线 | 安装成本 | 息屏 | 工作台 / 多窗 | 安全 | 许可证 | 何时停 |
| --- | --- | --- | --- | --- | --- | --- |
| A. 白名单 + 唤醒锁 + 小窗 | 无新包。菜单要在真机上对一次 | 有可能好转，过夜没有承诺 | 小窗可以；工作台按现场会停 | 仍是 `127.0.0.1` | 无新分发 | K0 之前就做 |
| A6. 关闭子进程限制 | 要开发者选项或 adb，系统更新后可能丢 | 只对 signal 9 / phantom 日志有效 | 冻住时无效 | 放宽的是全机子进程策略，不只是这个代理 | 不改本仓库许可证 | 日志对不上就不做 |
| B0. 看护 APK | 多一个包 | 保护不到 Termux | 保护不到 Termux | 多一个常驻应用，却换不来监听 | 若放进本仓库，仍是 CC BY-NC-SA | 不做 |
| B1. 回环探针 | 一个很小的侧载 APK，无账号数据 | 用来测量，不是产品 | 用来测量 | 只听 `127.0.0.1:18045`，无上游、无 token | 放进本仓库就沿用 CC BY-NC-SA，非官方 | K0 失败才写 |
| B2. host APK | 依赖 Bionic 构建；用户要再配一次厂商白名单；数据目录换到应用私有目录 | 仅当 B1 证明前台服务能活 | 同上 | `ABV_BIND_LOCAL_ONLY=1` 写进进程环境 | 同一许可证和署名；不捆绑 GPL 的 proot | B1 失败就不写 |
| C. 仅 Bionic、仍在 Termux | 一次 Rust 移植 | 杀伤面不变 | 杀伤面不变 | 绑定语义可以收成默认只本机 | 仍是本仓库许可证 | 不当作保活项目 |

## 8. 推荐的下一刀

**名字：`m4a-loopback-probe`。**

它是 vivo 上最小的一段实现：一个侧载 APK，在自己的 `specialUse` 前台服务进程里听 `127.0.0.1:18045`，不跑 Antigravity，不带 WebView，不捆绑 proot。用来回答「OriginOS 5 是否连前台服务一起冻」。答案是否定的时候，才投入 `m4a-specialuse-host` 和 Bionic 移植。答案是肯定的时候，保活就停在用户已经在用的小窗上。

开工门禁是 K0，不是 Android Studio。K0 不改代码：把 Termux 设为允许后台高耗电、打开自启动、最近任务锁定，在 Termux（不是 Debian）里执行 `termux-wake-lock`，然后按第 9 节把息屏和工作台记下来。K0 若让现有 `http://127.0.0.1:8045/health` 在这两种状态下都活过 30 分钟，就不写探针。

## 9. 仍要在 PA2553 上核对

本仓库没有在这台平板上执行过下面任何一条。

### K0 — 现有 headless，先做

准备：USB 调试开着，电脑上的 `adb` 在息屏后仍能 `adb shell`。无线调试在息屏后可能随 Wi-Fi 策略一起停，不要用它当唯一观察口。Termux 按 A3 设好。反代用现在的 `run-headless.sh` 启动。锁是否真的拿着，看通知里的 “wake lock held”，或：

```text
adb shell dumpsys power | grep termux:service-wakelock
```

每一行都记下四列：`pidof` / `ps` 里还有没有 `antigravity-tools`；`adb` 访问 `/health` 是成功、拒绝还是超时；通知还在不在；logcat 里有没有 phantom、signal 9、excessive cpu、freeze。

1. 关于本机：Android 版本、OriginOS 版本、`ro.build.version.sdk`。确认是不是公开规格上的 Android 15 / OriginOS 5。
2. 小窗，亮屏。这是现场里的对照，应当成功。
3. 工作台或多窗，Termux 不是当前那格还在刷新的窗口。亮屏。
4. 息屏 5 分钟，USB 还在。
5. 息屏 30 分钟。
6. 插电过夜。和 30 分钟分开记。旧的 OriginOS 记录里，短时间能过、过夜假死。
7. 只开「允许后台高耗电」、不拿 wake lock，重复第 4 行。用来区分「冻住」和「CPU 睡了」。
8. 最近任务里划掉 Termux。预期会停。记下是通知一起没，还是通知还在、子进程没了。
9. 失败那一刻的 cgroup / wchan（进程还在时）：`/proc/<pid>/cgroup` 和 `/proc/<pid>/wchan` 里有没有 freezer。有，就是冻结；没有，再看 logcat。

健康检查示例（端口以日志为准，默认 8045）：

```text
adb shell toybox nc -w 3 127.0.0.1 8045
```

在另一台机器上把一行 HTTP 请求送进去即可，例如 `GET /health HTTP/1.0`。超时就是「还在但不跑」的候选；连接被拒绝且 `ps` 里没有进程，就是已经死了。

### 探针写完之后才做

10. 第 5 节 B1 的五条通过标准。
11. 探针与 Termux 同时装在机器上时，全局 phantom 名额会不会把 Termux 的子进程挤掉。测探针时把 headless 停掉，避免两件事情叠在一起。
12. 开发者选项里到底有没有「Disable child process restrictions」。没有就记没有，不要为了找它去 root。

### 只有 B2 开工才需要

13. `exec` `libantigravity.so` 之后，父服务还在、子进程是不是 signal 9。
14. 应用私有目录里的新 `ABV_DATA_DIR` 与 proot 里旧数据如何拷贝。机器 ID 密钥（`machine_uid`）换目录之后是否还解得开。登录密码仍由环境变量注入，不把这一步当成登录的前置。
15. 最终 applicationId 和启动器名字。

## 10. 不在这次范围内

- 实现探针或 host APK，改 `run-headless.sh`，改 Rust
- 把 `ABV_BIND_LOCAL_ONLY` 放开
- 1 像素 Activity、悬浮窗、无障碍、VPN 常驻、Shizuku、Magisk、Xposed
- fork Termux（GPL 工程，另外维护）
- 把 proot / Debian 打进 APK
- 用 `dataSync` 前台服务硬撑 24 小时
- Termux:Boot / runit 当作息屏方案
- DroidDeck，以及任何推到 `lbjlaq/Antigravity-Manager` 的改动
- Play 商店、收费包、官方 Android 名义
- 为了保活先做 Bionic 移植或 Tauri Android / Capacitor

## 11. 依据

这些都是公开文档或社区记录，不是 PA2553 的测试结果。

- Termux 唤醒锁命令：<https://github.com/termux/termux-tools/blob/master/scripts/termux-wake-lock.in>（`am startservice` 到 `TermuxService`，不是 Termux:API）
- Termux 前台服务与 partial wake lock：<https://github.com/termux/termux-app/blob/master/app/src/main/java/com/termux/app/TermuxService.java>
- 锁在主进程、子进程仍被杀：Termux 维护者在 phantom process 讨论中的说明，以及 <https://github.com/termux/termux-app/issues/256>（0 个会话时锁仍可被拿住）
- 唤醒锁管不到厂商的 cgroup 冻结。这条记录来自华为机型，和 OriginOS 的冻结是同一类机制，不是 PA2553 的测试：<https://github.com/termux/termux-app/issues/1489>
- phantom 上限、5 分钟 CPU 检查、Android 14 开发者选项：<https://github.com/agnostic-apollo/Android-Docs/blob/master/en/docs/apps/processes/phantom-cached-and-empty-processes.md>
- Android 15 前台服务时限（`dataSync` / `mediaProcessing` 6 小时，`specialUse` 不在其中）：<https://developer.android.com/develop/background-work/services/fgs/timeout>
- 前台服务类型：<https://developer.android.com/develop/background-work/services/fgs/service-types>
- 前台服务让进程停在 `oom_score_adj` 200，缓存进程会被 freezer：<https://developer.android.com/topic/performance/memory/guide/process-splitting>
- vivo / iQOO「允许后台高耗电」：华为帮助页对 vivo 路径的说明（搜索「后台耗电管理」）
- OriginOS 三项设置之后过夜仍可能假死：第三方 OriginOS 1 使用记录，只能当预期管理，不能当 Pad5 的结果
- 原子工作台在部分场景把窗口收成静态预览：vivo 官方对原子工作台的说明（页面写的是另一台折叠屏设备）。PA2553 是否相同，见 K0 第 3 行
- PA2553 的公开规格：vivo Pad5，Android 15，OriginOS 5，Dimensity 9300+。以这台平板「关于本机」为准
