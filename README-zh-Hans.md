# 🔥 Mac 卡成狗？元凶交给 Claude 揪出来。

[English](README.md) · [한국어](README-ko.md) · **简体中文** · [繁體中文](README-zh-Hant.md) · [日本語](README-ja.md) · [Español](README-es.md) · [Deutsch](README-de.md) · [Français](README-fr.md) · [Português](README-pt-BR.md) · [Русский](README-ru.md)

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-F05138?logo=swift&logoColor=white)
![Menu bar app](https://img.shields.io/badge/menu--bar-no%20Dock%20icon-success)

**Mac 一卡 → Claude 当场点名是哪个进程在吃资源 → 一键干掉它。你不点，它就什么都不做，没有任何风险。**

每隔一小时，你 Mac 的负载就发给 Claude。它把*真正*在啃你 CPU/RAM 的家伙排出名次，写好准确的修复命令，直接送进你的菜单栏，最严重的排最前、按颜色分级、一键搞定。而在任何命令执行之前，还得有*第二轮* Claude 校验把它放行为 **SAFE**。

**Mac Optimizing Looper** 是一款 macOS 菜单栏应用（无 Dock 图标），在你本地的 LLM CLI 之上，持续跑一个**观察 → 询问模型 → 给建议 →（可选）执行**的循环。

[**⬇ 安装**](#安装) · [**看它怎么干活 ↓**](#工作原理)

<p align="center"><img src="docs/menu.png" alt="Mac Optimizing Looper 菜单——按严重程度着色排序的修复建议" width="540"></p>

> 活动监视器甩给你 200 行数据，答案一个没有。这里只给你**一条命令**，能解决问题，还告诉你为什么。

## 工作原理

一个循环，从上到下走一遍：

```
⏱  timer fires (default: every 1h, slider 10m … 36h)
→  collect: CPU/MEM + mac-optimizer snapshot (+ optional sustained sample)
→  claude -p   (analysis pass, --effort max)
→  claude -p   (format pass → ranked JSON suggestions)
```

菜单栏显示数量。下拉列表按**最严重优先**排序：🔴 严重 → 🟡 警告 → 🟢 优化。每一行都能展开成 **Copy** · **Show in Terminal** · **Review with Claude** · **Run Command Now**。

## 安全闸门：它凭什么不会把你的 Mac 搞崩

"Run Command Now" 是**唯一**会执行任何东西的入口，而且全程上锁：

```
click ▸ Run Command Now   ($ kill 8123)
→  claude -p   classifies → RISK: SAFE
→  background run   (sudo → GUI password prompt, because there's no TTY)
→  ✅ notification → click → full stdout/stderr window
→  suggestion marked ✓ done
```

任何没被判定为 `SAFE` 的命令（**`unknown` 也算在内**）都会弹出一个确认对话框，默认按钮就是 **Cancel**。建议本身只是惰性数据；模型永远没法让这个应用自行跑任何东西，这条铁律由 `GuardrailTests` 死死锁住。

## Mac Optimizing Looper vs 那几位老熟人

| | 活动监视器 | "清理"类应用 | **Mac Optimizing Looper** |
|---|---|---|---|
| 找出真正的元凶 | 自己读 200 行 | 靠猜 | 🟢 Claude 把最严重的排最前 |
| 告诉你*为什么*卡 | ✗ | ✗ | 🟢 大白话讲清原因 |
| 给出准确的修复 | ✗ | 笼统的"清理" | 🟢 真正能用的 `kill` / `unload` 命令 |
| 自作主张地动手 | — | 🔴 会，还按计划定时跑 | 🟢 绝不，只在你点击时 |
| 执行前过安全闸 | — | ✗ | 🟢 第二轮 Claude 校验放行 `SAFE` |
| 你的数据去哪 | 本地 | 看情况 | 只去你自己的 Claude CLI |

## 安装

需要 `claude` CLI 在你的 PATH 里。macOS 13+。

```bash
brew install --cask kargnas/tap/mac-optimizing-looper
```

> cask 与 DMG 会在首个签名版本发布后上线。流水线已搭好，就等签名密钥，参见 [docs/release-setup.md](docs/release-setup.md)。在此之前，请从源码构建：

```bash
git clone https://github.com/kargnas/mac-optimizing-looper
cd mac-optimizing-looper
bash script/build_and_run.sh run     # builds the .app, codesigns ad-hoc, launches
```

请运行**应用包（bundle）**，别跑裸二进制，`UNUserNotificationCenter` 需要一个真实的 bundle id（`as.kargn.MacOptimizingLooper`）。

## 调成你自己的样子

在设置里挑 **Provider / Model / Speed / Fast Mode**，可用的模型与推理等级会**实时**从每个 CLI 读取。默认后端是 `claude` CLI；同时也支持 `codex`（单次受 schema 约束的处理，不再单独走格式化）。界面已完整本地化为 **10 种语言**，而 **Language** 选择器同时决定界面*和*分析输出的语言。

<p align="center"><img src="docs/settings.png" alt="Mac Optimizing Looper 设置——提供方、模型、语言、间隔" width="520"></p>

## 常见问题

**它会自己跑命令吗？**
不会。建议只是惰性数据。唯一的执行入口就是 "Run Command Now" 按钮，靠你点击，由 `GuardrailTests` 强制保证。

**点 "Run" 安全吗？**
每条命令都要过第二轮 Claude 校验。任何没被明确判为 `SAFE` 的（包括 `unknown`）都会弹确认框，默认停在 **Cancel**。`sudo` 走 macOS 的 GUI 密码提示。

**我的数据会离开这台 Mac 吗？**
只有实时指标 + 进程列表，而且只经由*你自己的* `claude` CLI 发给 Anthropic（或经 `codex` 发给 OpenAI），跟你亲手用那个 CLI 一模一样。应用零遥测。

**要花多少钱？**
除了你本来就在用的 `claude` / `codex` CLI，不再花一分钱。应用免费，MIT 许可。

**没装 `claude` CLI 怎么办？**
那就没有建议，它会把错误显示出来，而不是瞎猜。

<details>
<summary><b>底层细节</b>：系统提示词、完整循环、决策流程、配置、限制</summary>

### 系统提示词（脱敏摘录）

```
You are a macOS performance analyst.
Given live metrics + a process table, identify the ACTUAL remediation
command (kill / killall / unload) for each real problem — never an
inspection command (no pgrep / ps / top).

MUST:     rank by severity; prefer graceful `kill <pid>` over `kill -9`.
MUST:     return a null command when no command-line action applies.
MUST NOT: claim anything was executed — the app never auto-runs.
```

### 每个循环可能触及什么

| 步骤 | 工具 | 副作用 |
|---|---|---|
| 采集 | `MetricsCollector`、`mac-optimizer.sh` | 只读 |
| 分析 | `claude -p`（effort = max） | 联网，只读 |
| 格式化 | `claude -p`（effort = low） | 排序后的 JSON |
| 风险校验 | `claude -p` | 联网，只读 |
| 执行 | `CommandExecutor` | **执行命令**（仅由用户发起） |
| 复查 | 已配置的终端 + 交互式 `claude` | 打开一个终端 |

### 决策流程

```
timer → collect → claude analyze → rank suggestions
                                       │
                 user picks an action ─┼─ Copy / Show in Terminal → no execution
                                       ├─ Review with Claude       → interactive claude session
                                       └─ Run Command Now
                                              → claude risk-check
                                                   ├─ SAFE → run → notify → ✓
                                                   └─ else → confirm (default Cancel)
```

### 配置

配置位于 `~/.config/mac-optimizing-looper/config.json`（可复制 `config.example.json`）：提供方、模型、思考等级、监控秒数、间隔、终端、语言。它只在启动时读取一次，手动改完要重启。

### 限制／它会拒绝什么

- **从不自作主张。** 只有 "Run Command Now" 会执行，且仅在你点击时。
- **未知风险 = 当作危险处理。** 故障保护设计；由你来确认。
- **`sudo` → GUI 密码提示。** 后台执行没有 TTY，所以 root 命令会经由 `osascript … with administrator privileges` 路由。
- **没有 `claude` CLI = 没有建议。** 它会把错误显示出来，而不是瞎猜。
- 通知需要应用包；裸二进制会退而打开结果窗口。

</details>

---

MIT 许可。献给那些宁愿弄清 Mac *为什么*卡，也不想重启了事、碰碰运气的人。
