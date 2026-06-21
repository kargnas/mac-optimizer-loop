# 🔥 Your Mac is slow. Claude finds the culprit.

**English** · [한국어](README-ko.md) · [简体中文](README-zh-Hans.md) · [繁體中文](README-zh-Hant.md) · [日本語](README-ja.md) · [Español](README-es.md) · [Deutsch](README-de.md) · [Français](README-fr.md) · [Português](README-pt-BR.md) · [Русский](README-ru.md)

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-F05138?logo=swift&logoColor=white)
![Menu bar app](https://img.shields.io/badge/menu--bar-no%20Dock%20icon-success)

**Your Mac chokes → Claude names the exact process eating it → one click kills it. Nothing happens until you click — so there's no risk to your Mac.**

Every hour, your Mac's load goes to Claude. It ranks what's *actually* hogging your CPU/RAM, writes the exact fix, and drops it in your menu bar — worst-first, color-coded, one click away. And before anything runs, a *second* Claude pass has to clear the command as **SAFE**.

**Mac Optimizing Looper** is a macOS menu-bar app (no Dock icon) that runs a continuous **observe → ask the model → advise → (optionally) act** loop on top of your local LLM CLI.

[**⬇ Install**](#install) · [**See it work ↓**](#how-it-works)

<p align="center"><img src="docs/menu.png" alt="Mac Optimizing Looper menu — ranked, severity-colored fixes" width="540"></p>

> Activity Monitor shows you 200 rows and zero answers. This shows you the **one command** that fixes it — and why.

## How it works

One cycle:

```
⏱  timer fires (default: every 1h, slider 10m … 36h)
→  collect: CPU/MEM + mac-optimizer snapshot (+ optional sustained sample)
→  claude -p   (analysis pass, --effort max)
→  claude -p   (format pass → ranked JSON suggestions)
```

The menu bar shows the count. The dropdown is ranked **worst-first**: 🔴 critical → 🟡 warning → 🟢 hygiene. Each row expands into **Copy** · **Show in Terminal** · **Review with Claude** · **Run Command Now**.

## The safety gate — why it won't nuke your Mac

"Run Command Now" is the **only** path that executes anything, and it's gated end to end:

```
click ▸ Run Command Now   ($ kill 8123)
→  claude -p   classifies → RISK: SAFE
→  background run   (sudo → GUI password prompt, because there's no TTY)
→  ✅ notification → click → full stdout/stderr window
→  suggestion marked ✓ done
```

Anything not classified `SAFE` (including `unknown`) pops a confirmation dialog defaulting to **Cancel**. The advice itself is inert data; the model can never make the app run a thing. Enforced by `GuardrailTests`.

## Mac Optimizing Looper vs the usual suspects

| | Activity Monitor | "Cleaner" apps | **Mac Optimizing Looper** |
|---|---|---|---|
| Finds the actual culprit | you read 200 rows | guesses | 🟢 Claude ranks worst-first |
| Tells you *why* it's slow | ✗ | ✗ | 🟢 plain-language reason |
| Gives the exact fix | ✗ | generic "clean" | 🟢 the real `kill` / `unload` command |
| Acts on its own | — | 🔴 yes, on a schedule | 🟢 never — only on your click |
| Safety-gated before running | — | ✗ | 🟢 second Claude pass clears it `SAFE` |
| Where your data goes | local | varies | only to your own Claude CLI |

## Install

Needs the `claude` CLI on your PATH. macOS 13+.

```bash
brew install --cask kargnas/tap/mac-optimizing-looper
```

> The cask + DMG go live after the first signed release. The pipeline is wired and waiting on signing secrets — see [docs/release-setup.md](docs/release-setup.md). Until then, build from source:

```bash
git clone https://github.com/kargnas/mac-optimizing-looper
cd mac-optimizing-looper
bash script/build_and_run.sh run     # builds the .app, codesigns ad-hoc, launches
```

Run the **bundle**, not the bare binary — `UNUserNotificationCenter` needs a real bundle id (`as.kargn.MacOptimizingLooper`).

## Make it yours

Pick **Provider / Model / Speed / Fast Mode** in Settings — models and reasoning levels are read live from each CLI. Default backend is the `claude` CLI; `codex` is also supported (one schema-constrained pass, no separate format step). The UI is in 10 languages; the **Language** picker controls both the UI and what language Claude analyzes in.

<p align="center"><img src="docs/settings.png" alt="Mac Optimizing Looper Settings — provider, model, language, interval" width="520"></p>

## FAQ

**Does it ever run anything by itself?**
No. Advice is inert data. The single execution path is the "Run Command Now" button, on your click — enforced by `GuardrailTests`.

**Is it safe to hit "Run"?**
Every command goes through a second Claude pass. Anything not clearly `SAFE` (including `unknown`) pops a confirm dialog defaulting to **Cancel**. `sudo` routes through the macOS GUI password prompt.

**Does my data leave my Mac?**
Only the live metrics + process table, sent to Anthropic via *your own* `claude` CLI (or OpenAI via `codex`). The app adds zero telemetry.

**What does it cost?**
Nothing beyond your existing `claude` / `codex` CLI usage. The app is free and MIT-licensed.

**No `claude` CLI installed?**
Then no advice — it surfaces the error instead of guessing.

<details>
<summary><b>Under the hood</b> — system prompt, full cycle, decision flow, config, limits</summary>

### System prompt (sanitized excerpt)

```
You are a macOS performance analyst.
Given live metrics + a process table, identify the ACTUAL remediation
command (kill / killall / unload) for each real problem — never an
inspection command (no pgrep / ps / top).

MUST:     rank by severity; prefer graceful `kill <pid>` over `kill -9`.
MUST:     return a null command when no command-line action applies.
MUST NOT: claim anything was executed — the app never auto-runs.
```

### What each cycle can touch

| Step | Tool | Side effect |
|---|---|---|
| Collect | `MetricsCollector`, `mac-optimizer.sh` | read-only |
| Analyze | `claude -p` (effort = max) | network, read-only |
| Format | `claude -p` (effort = low) | ranked JSON |
| Risk-check | `claude -p` | network, read-only |
| Run | `CommandExecutor` | **runs the command** (user-initiated only) |
| Review | configured terminal + interactive `claude` | opens a terminal |

### Decision flow

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

### Config

Config lives at `~/.config/mac-optimizing-looper/config.json` (copy `config.example.json`): provider, model, thinking level, monitor seconds, interval, terminal, language. It's read once at launch — restart after hand-editing.

### Limits / what it refuses

- **Never acts on its own.** Only "Run Command Now" executes, and only on your click.
- **Unknown risk = treated as dangerous.** Fail-safe; you confirm.
- **`sudo` → GUI password prompt.** A background run has no TTY, so root commands route through `osascript … with administrator privileges`.
- **No `claude` CLI = no advice.** It surfaces the error instead of guessing.
- Notifications need the app bundle; a bare binary falls back to opening the result window.

</details>

---

MIT licensed. Built for people who'd rather know *why* their Mac is slow than reboot and hope.
