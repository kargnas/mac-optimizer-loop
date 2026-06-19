# AGENTS.md

Guidance for AI agents working on **Mac Load Advisor** — a macOS menu-bar app that
periodically analyzes system load with Claude and surfaces prioritized advice.

## Build / Run

- Package manager: SwiftPM. `swift build`, `swift test` (run both before finishing).
- **Always launch via the app bundle**, not the bare binary:
  ```bash
  bash script/build_and_run.sh run
  ```
  This builds `dist/MacLoadAdvisor.app`, codesigns it ad-hoc, and `open -n`s it. The
  bundle id is `as.kargn.MacLoadAdvisor`; it is `LSUIElement` (no Dock icon).
- **Why the bundle matters:** `UNUserNotificationCenter` needs a real bundle proxy. A
  bare `.build/.../MacLoadAdvisor` binary has no bundle id, so notifications silently
  fail there. Code guards on `Bundle.main.bundleIdentifier != nil` and falls back to
  opening the result window directly — but for real testing, run the bundle.
- Config lives at `~/.config/mac-load-advisor/config.json` and is read once at launch
  (`AppConfig.loadDefault()`). After editing config by hand, **restart the app**.
- `thinkingLevel` (config) = Claude `--effort` for the **analysis pass** only
  (low/medium/high/xhigh/max, default `max`; invalid values clamp to `max`). The JSON
  formatter and the command risk-check stay at `low` by design (mechanical / fast gate).
- `monitorSeconds` (config, default 30, clamped 0–600) = how long the mac-optimizer
  **sustained monitor** samples before evaluating. `MacOptimizerScript.runIfAvailable`
  runs the one-shot snapshot AND, when `monitorSeconds > 0`, a second `--monitor N`
  pass (separate script mode) appended to the report. `0` disables the monitor pass.

## Release pipeline

`script/build-app.zsh` packages a distributable `dist/MacLoadAdvisor.app` (release
build + version-stamped `Info.plist`). Local default is ad-hoc sign; CI sets
`CODE_SIGN_IDENTITY="Developer ID Application"` + `HARDENED_RUNTIME=1` for a
notarizable bundle. Keep it separate from `build_and_run.sh` (that is the fast
debug dev loop). `.github/workflows/auto-release.yml` bumps the patch version on
pushes to `main` and dispatches `build-release.yml` (build → sign → notarize → DMG
→ GitHub Release → `update-tap` writes the `kargnas/homebrew-tap` cask). The
pipeline is **inert until signing secrets exist** — see `docs/release-setup.md`.
Sparkle in-app auto-update is intentionally not wired yet (needs app-target changes).

## Terminal Launching — single entry point

All terminal-opening features (Show Command in Terminal, Claude review) go through
**`TerminalLauncher`** (`Sources/MacLoadAdvisor/TerminalLauncher.swift`). Do not open
terminals directly from `AppDelegate` or anywhere else — extend `TerminalLauncher`.

- Terminal resolution: `TerminalAppCatalog.application(bundleIdentifier:)`.
- The configured terminal (`config.terminalAppBundleIdentifier`) is **honored exactly**.
  When a specific terminal is configured but cannot be matched, we resolve it directly
  via `NSWorkspace`, and if it is genuinely not installed we return `nil` so the caller
  shows an error. **Never silently substitute a different terminal** (e.g. Apple
  Terminal) — that hid real misconfiguration and opened the wrong app.
- Per-terminal launch quirks live in `TerminalApplication.LaunchMode`
  (`appleTerminal` / `iTerm` via AppleScript, `openWithArguments` for Ghostty,
  `openCommandFile` for the rest). Unknown-but-installed terminals use `openCommandFile`.
- Scripts are written to a `.command` file and the **path only** is injected into
  AppleScript — never the multi-line/UTF-8 body (Terminal turns embedded newlines into
  Return presses, corrupting `if/elif/fi` and CJK text).

## Claude CLI invocation — headless vs interactive

`claude` starts an **interactive session by default**; `-p`/`--print` is non-interactive.
There is **no `claude run` subcommand**.

- **Headless `-p`** for anything the app parses programmatically:
  - Advice generation — `ClaudeCLIClient` (`-p --output-format text`, JSON parsed downstream).
  - Command risk check — `CommandRiskAssessor` (`-p`, parses `RISK: SAFE|DANGEROUS`).
- **Interactive `claude "<prompt>"`** for user-facing terminals:
  - "Review with Claude" — `TerminalScriptBuilder.claudeReviewScript` opens an
    interactive session seeded with the prompt via `"$(cat <promptfile>)"` so the user
    can read the assessment and keep chatting. Do not regress this back to `-p`. The
    review prompt (`claudeReviewPrompt`) is a proactive performance assistant: it
    assesses the command, then offers to inspect and clean up the system with the
    user's confirmation — not a narrow command-only reviewer.

## Command execution & safety model

`ActionPolicy.current == .userInitiatedWithSafeguards`. Advice is inert data; the model
can never make the app run anything. The single execution path is the explicit
**"Run Command Now"** menu action, gated by:

1. `CommandRiskAssessor` (`claude -p`) classifies the command; `unknown` is treated as
   dangerous (fail safe).
2. Anything not clearly `safe` → confirmation dialog (default button = Cancel).
3. `CommandExecutor.run` executes in the background. Commands containing a `sudo` token
   are routed through a GUI admin-password prompt (`osascript ... with administrator
   privileges`) because a background process has no TTY.
4. Result → macOS notification (✅/❌ + exit code); tapping it opens the full output
   window. If notifications are unavailable, the window opens directly (never lose output).

`Suggestion` carries only data (`suggestedCommand: String?`), no executable closures —
enforced by `GuardrailTests`.

## House rules (project-specific)

- **No silent fallbacks / no silent failure.** Surface errors; never substitute behavior
  the user didn't choose without telling them.
- i18n: `AppStrings` is the only place for user-facing text (English + Korean). Add new
  strings there, never hardcode UI text in views/controllers.
- Tests: `Tests/MacLoadAdvisorCoreTests`. Keep `GuardrailTests` green — it encodes the
  safety contract. Update it deliberately when the contract intentionally changes.
- Bundle id prefix for any new bundles: keep `as.kargn.*` consistent with the
  existing app bundle.
