# 🔥 Mac 卡到不行？兇手交給 Claude 揪出來。

[English](README.md) · [한국어](README-ko.md) · [简体中文](README-zh-Hans.md) · **繁體中文** · [日本語](README-ja.md) · [Español](README-es.md) · [Deutsch](README-de.md) · [Français](README-fr.md) · [Português](README-pt-BR.md) · [Русский](README-ru.md)

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-F05138?logo=swift&logoColor=white)
![Menu bar app](https://img.shields.io/badge/menu--bar-no%20Dock%20icon-success)

**Mac 一卡 → Claude 直接點名是哪個程序在吃資源 → 一鍵收掉它。你不點，它就什麼都不做，沒有任何風險。**

每小時，你 Mac 的負載都會送一份給 Claude。它排出*真正*在啃 CPU/RAM 的兇手，寫好確切的修復指令，丟進你的選單列，最嚴重的排最前、依顏色分級、一鍵就能解決。而且在動手之前，還得讓*第二輪* Claude 把這道指令蓋上 **SAFE** 章。

**Mac Optimizing Looper** 是一款 macOS 選單列 App（沒有 Dock 圖示），它在你本機的 LLM CLI 之上，持續跑著 **觀察 → 詢問模型 → 建議 →（視情況）動作** 的迴圈。

[**⬇ 安裝**](#安裝) · [**看它怎麼運作 ↓**](#運作原理)

<p align="center"><img src="docs/menu.png" alt="Mac Optimizing Looper 選單——已排序、依嚴重程度標色的修復建議" width="540"></p>

> 活動監視器丟給你 200 列、零個答案。這裡只給你**那一道指令**，還告訴你為什麼。

## 運作原理

一個週期，由上而下：

```
⏱  timer fires (default: every 1h, slider 10m … 36h)
→  collect: CPU/MEM + mac-optimizer snapshot (+ optional sustained sample)
→  claude -p   (analysis pass, --effort max)
→  claude -p   (format pass → ranked JSON suggestions)
```

選單列顯示數量。下拉選單以**最嚴重者優先**排序：🔴 critical → 🟡 warning → 🟢 hygiene。每一列都可展開成 **Copy** · **Show in Terminal** · **Review with Claude** · **Run Command Now**。

## 安全閘：它為什麼不會把你的 Mac 搞爆

「Run Command Now」是**唯一**會執行任何東西的路徑，而且從頭到尾都受控管：

```
click ▸ Run Command Now   ($ kill 8123)
→  claude -p   classifies → RISK: SAFE
→  background run   (sudo → GUI password prompt, because there's no TTY)
→  ✅ notification → click → full stdout/stderr window
→  suggestion marked ✓ done
```

任何沒被歸類為 `SAFE` 的指令（**包括 `unknown`**）都會跳出一個確認對話框，預設按鈕是 **Cancel**。建議本身只是惰性資料；模型永遠無法讓這個 App 去跑任何東西。這份契約由 `GuardrailTests` 死守。

## Mac Optimizing Looper 對上那些老把戲

| | 活動監視器 | 「清理」App | **Mac Optimizing Looper** |
|---|---|---|---|
| 找出真正的兇手 | 你自己讀 200 列 | 用猜的 | 🟢 Claude 把最嚴重的排最前 |
| 告訴你*為什麼*變慢 | ✗ | ✗ | 🟢 白話講清楚原因 |
| 給你確切的修復指令 | ✗ | 一句空泛的「清理」 | 🟢 真正的 `kill` / `unload` 指令 |
| 自作主張動手 | — | 🔴 會，照排程跑 | 🟢 絕不，只在你點擊時 |
| 執行前過安全閘 | — | ✗ | 🟢 第二輪 Claude 蓋上 `SAFE` 章 |
| 你的資料往哪去 | 本機 | 看情況 | 只送到你自己的 Claude CLI |

## 安裝

需要 PATH 上有 `claude` CLI。macOS 13 以上。

```bash
brew install --cask kargnas/tap/mac-optimizing-looper
```

> cask 與 DMG 會在第一個簽署過的發行版上線後開放。發行流程已接好，正等著簽署密鑰，詳見 [docs/release-setup.md](docs/release-setup.md)。在那之前，請從原始碼建置：

```bash
git clone https://github.com/kargnas/mac-optimizing-looper
cd mac-optimizing-looper
bash script/build_and_run.sh run     # builds the .app, codesigns ad-hoc, launches
```

請執行 **bundle**，而非裸二進位檔，`UNUserNotificationCenter` 需要一個真正的 bundle id（`as.kargn.MacOptimizingLooper`）。

## 調成你的樣子

在「設定」裡挑 **Provider / Model / Speed / Fast Mode**，模型與推理層級都會**即時**從各個 CLI 讀取。預設後端是 `claude` CLI；`codex` 也有支援（單一次受 schema 約束的傳遞，沒有獨立的格式化步驟）。UI 完整在地化為 **10 種語言**，而 **Language** 選擇器會同時驅動 UI *以及*分析輸出的語言。

<p align="center"><img src="docs/settings.png" alt="Mac Optimizing Looper 設定——供應商、模型、語言、間隔" width="520"></p>

## 常見問題

**它會不會自己跑東西？**
不會。建議只是惰性資料。唯一的執行路徑是「Run Command Now」按鈕，按你的點擊才動，由 `GuardrailTests` 強制保證。

**按下「Run」安全嗎？**
每道指令都會過第二輪 Claude。任何不是明確 `SAFE` 的（包括 `unknown`）都會跳出確認對話框，預設停在 **Cancel**。`sudo` 會走 macOS 的 GUI 密碼提示。

**我的資料會離開我的 Mac 嗎？**
只有即時指標 + 程序清單，而且只透過*你自己的* `claude` CLI 送到 Anthropic（或透過 `codex` 送到 OpenAI），跟你親自用那個 CLI 完全一樣。這個 App 零遙測。

**要花多少錢？**
除了你原本就在用的 `claude` / `codex` CLI 之外，什麼都不用。App 本身免費，採 MIT 授權。

**沒裝 `claude` CLI 怎麼辦？**
那就沒有建議，它會把錯誤直接攤給你看，而不是憑空亂猜。

<details>
<summary><b>引擎蓋底下</b>：系統提示、完整週期、決策流程、設定、限制</summary>

### 系統提示（已淨化的節錄）

```
You are a macOS performance analyst.
Given live metrics + a process table, identify the ACTUAL remediation
command (kill / killall / unload) for each real problem — never an
inspection command (no pgrep / ps / top).

MUST:     rank by severity; prefer graceful `kill <pid>` over `kill -9`.
MUST:     return a null command when no command-line action applies.
MUST NOT: claim anything was executed — the app never auto-runs.
```

### 每個週期可能觸及什麼

| 步驟 | 工具 | 副作用 |
|---|---|---|
| Collect | `MetricsCollector`、`mac-optimizer.sh` | 唯讀 |
| Analyze | `claude -p`（effort = max） | 網路、唯讀 |
| Format | `claude -p`（effort = low） | 已排序的 JSON |
| Risk-check | `claude -p` | 網路、唯讀 |
| Run | `CommandExecutor` | **執行該指令**（僅限使用者發起） |
| Review | 設定好的終端機 + 互動式 `claude` | 開啟一個終端機 |

### 決策流程

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

### 設定

設定檔位於 `~/.config/mac-optimizing-looper/config.json`（複製 `config.example.json`）：供應商、模型、思考層級、監測秒數、間隔、終端機、語言。它只在啟動時讀取一次，手動改完後請重啟。

### 限制／它拒絕做的事

- **絕不自作主張。** 只有「Run Command Now」會執行，且只在你點擊時。
- **未知風險＝當成危險處理。** 故障安全（fail-safe）；由你來確認。
- **`sudo` → GUI 密碼提示。** 背景執行沒有 TTY，所以 root 指令會經由 `osascript … with administrator privileges` 轉送。
- **沒有 `claude` CLI ＝沒有建議。** 它會把錯誤攤給你看，而不是憑空亂猜。
- 通知需要 App bundle；裸二進位檔會退而開啟結果視窗。

</details>

---

採 MIT 授權。為那些寧可搞懂 Mac *為什麼*變慢、也不想重開機碰運氣的人而打造。
