---
name: mac-optimizer
description: Diagnoses why a macOS system is slow by MEASURING which layer is the bottleneck (CPU thread / GPU / memory pressure / WindowServer compositor), flags a CRITICAL must-act-now state, then drills generically to the responsible process and recommends durable fixes. Works on any Mac with no hardcoded app list. Triggers on slow Mac, laggy, why is it slow, stuttering, slow window dragging, lag during screen share, check Mac performance, optimize my Mac, system health check.
user-invocable: true
allowed-tools: Bash(bash *), Bash(uv run *)
metadata:
  author: skalinets
  version: "3.0.0"
  license: MIT
---

# Mac Performance Optimizer

Finds WHY a Mac is slow by measurement, not by guessing which app to quit. The
collector script does all arithmetic and flags every threshold (including a
CRITICAL must-act-now gate); this skill identifies the bound *layer* from honest
signals, drills to the one responsible process generically, and returns a
prioritized, copy-paste-ready report.

## How This Skill Stays Reliable and Generic

- **The script computes; you interpret.** `mac-optimize.sh` pre-flags memory/CPU
  pressure, the `SYSTEM STATE` gate, browser/session counts, and vendor boot
  weight in deterministic bash. MUST report its values and flags verbatim — never
  recompute GB from raw `vm_stat`.
- **No hardcoded app list.** Detection keys off *measurements and roles* (a
  compositor that is CPU-bound, a non-Apple daemon pegging a core, a window-leak
  owner, a vendor with zero running jobs) — discovered live on whatever machine
  this runs on. MUST NOT tell the user to look at a specific named third-party app
  unless the live data itself surfaced it.
- **"Used RAM" lies; pressure tells the truth.** Judge memory ONLY by kernel
  pressure level + live swap-out delta, never by "free" or "used" GB.

---

## Procedure

Execute steps [S1]–[S7] in order. Each ends with a VERIFY gate — do NOT proceed
until it passes.

### Step 1 [S1]: Snapshot, then CONFIRM with a sustained monitor

The one-shot dump uses ps %CPU, which on macOS is a lifetime DECAYING AVERAGE — it
can both miss an intermittent hog and over-blame a process that just spiked. So
diagnosis is two phases: snapshot to find suspects, then a real-time window to
CONFIRM which suspect is actually sustained.

**Phase 1a — snapshot.** MUST run:

```bash
bash "$HOME/.claude/skills/mac-optimizer/mac-optimize.sh"
```

**Phase 1b — sustained monitor (the confirmation pass).** MUST run a 30s window
when ANY row below is true:

| Condition | Run `--monitor 30`? |
|---|---|
| `SYSTEM STATE` is CRITICAL or STRAINED | MUST |
| User reports lag / stutter / "slow sometimes" / drag or screen-share lag | MUST (run it *while reproducing* if possible) |
| Any process or the compositor looks bound in BOTTLENECK LAYERS | MUST |
| HEALTHY and the user only wanted a quick audit | MAY skip |

```bash
bash "$HOME/.claude/skills/mac-optimizer/mac-optimize.sh" --monitor 30
```

This samples for 30s and tags each process `SUSTAINED` (real culprit) /
`intermittent` / `transient-blip` (noise), plus the load trend and whether swap
thrashed during the window. MUST treat only `SUSTAINED` (or repeated
`intermittent`) processes as the cause — a `transient-blip` MUST NOT be reported as
the culprit even if its one-shot %CPU was high.

**VERIFY [S1]**: Snapshot output contains `=== DERIVED METRICS` and
`=== BOTTLENECK LAYERS`. If the monitor was required, its output contains
`=== SUSTAINED MONITOR` with a process-persistence table. If the snapshot is
absent → the script failed; report the error and STOP.

---

### Step 2 [S2]: Read the SYSTEM STATE gate FIRST

MUST read the `SYSTEM STATE:` line in DERIVED METRICS before anything else.

| SYSTEM STATE | Meaning | Action |
|---|---|---|
| `CRITICAL` | Box is actively degrading now | MUST open the report with a 🚨 **MUST-RUN NOW** section naming the single immediate action for the printed trigger, BEFORE any HIGH/MED/LOW advice |
| `STRAINED` | Under real load, not an emergency | Normal report; top items go in 🔴 HIGH |
| `HEALTHY` | No live degradation | Normal report; say so plainly |

Map the CRITICAL trigger → immediate action:

| CRITICAL trigger (from the line) | 🚨 MUST-RUN NOW action |
|---|---|
| `active memory thrash` | Free memory now: identify the top-RSS process/family (S4) and quit/kill it; `sudo purge` only as stopgap |
| `CPU oversubscribed` | Identify the top `%CPU` process (S4); `kill -TERM <PID>` if runaway, or `sudo renice 20 -p <PID>` |
| `disk almost full` | Free space now (empty Trash, remove large caches); the system cannot page or save until it has headroom |

**VERIFY [S2]**: SYSTEM STATE noted. If CRITICAL, a 🚨 MUST-RUN NOW action is chosen
from the table.

---

### Step 3 [S3]: Identify the bound layer

MUST read `=== BOTTLENECK LAYERS ===` and pick the bound layer(s). Multiple can be
bound at once — treat the top CPU consumers as a list and resolve each.

| Signal in BOTTLENECK LAYERS | Bound layer | Drilldown section |
|---|---|---|
| WindowServer high CPU **and** GPU idle residency high / low clock | Compositor, CPU-thread bound | window-count leak, then fill-rate |
| WindowServer high CPU **and** GPU active at high clock | Compositor, fill-rate bound | fill-rate |
| A non-Apple-**app** daemon (a system/3rd-party background process, not your foreground app) holds ~1+ core | CPU, runaway daemon | runaway daemon |
| `Memory pressure level` ≥2 **and** swap-out delta >0 | Memory (active thrash) | memory |
| pressure level 1 / swap delta 0 even if "used" looks huge | NOT memory — rule it out | re-check other rows |
| GPU active residency high at high clock, workload is render/ML/video | GPU | GPU |
| `UI Looks like` LARGER than native resolution | Compositor amplifier (supersampled scaling) | fill-rate |

**VERIFY [S3]**: At least one layer is named as bound, OR all layers are explicitly
ruled out (then the cause is process-level, go to S4).

---

### Step 4 [S4]: Drill to the responsible process (generic heuristics)

MUST read `TOP PROCESSES BY CPU`, `TOP PROCESSES BY MEMORY`, and
`HEAVY LONG-RUNNING PROCESSES`. Apply these role/measurement heuristics — none
names a third-party app; the data fills in the name:

| Generic signal | Meaning | Severity |
|---|---|---|
| WindowServer %CPU high (compositor) | see S3 — drill via `guides/drilldowns.md` compositor sections + `window_count.py` | HIGH |
| `kernel_task` high %CPU | thermal throttling defense | HIGH (check POWER & THERMAL) |
| A non-Apple-app daemon at ~1+ core (≈100%+ one core) | runaway background daemon | HIGH (drilldowns: runaway daemon) |
| Any single process `%CPU` > 100 that is not the app you're actively using | runaway / leak | HIGH |
| Any process with `CPU_TIME` accrued many hours (see the `(Xh)` value) | long-running leak candidate | MEDIUM |
| Any single process RSS > ~2 GB | memory-heavy helper | MEDIUM |
| `window_count.py` shows one owner with ≥100 windows | compositor window leak | HIGH |

**MUST cross-check every flagged process against the `=== SUSTAINED MONITOR ===`
verdict from [S1b]**: report it as the cause only if the monitor tagged it
`SUSTAINED` (or repeatedly `intermittent`). A `transient-blip` is sampling noise —
note it as ruled-out, do NOT recommend acting on it.

For any confirmed process, **MUST NOT guess from its name** — open
[guides/drilldowns.md](guides/drilldowns.md) and follow the matching section,
which uses `lsof` + `log show` to learn what the process is actually doing before
recommending a durable fix. For a suspected window leak, run:

```bash
uv run --no-project --with pyobjc-framework-Quartz python3 \
  "$HOME/.claude/skills/mac-optimizer/scripts/window_count.py"
```

**VERIFY [S4]**: Every process matching a row above is flagged with a severity, or
"no abnormal process patterns" is stated explicitly.

---

### Step 5 [S5]: Background / boot weight (vendor-generic)

MUST read `=== THIRD-PARTY LAUNCH JOBS ===` (vendor-grouped, Apple excluded) and
the pre-flagged `Browser TOTAL` / `Claude sessions` lines. These are discovered
from the machine, not a fixed list:

| Generic signal | Recommend |
|---|---|
| A vendor with jobs but `idle — 0 running` | Pure boot weight — disable that vendor's jobs if not used (do NOT assume unused; phrase as "disable if not in use") |
| A vendor carrying many jobs | Consolidate; the more login jobs, the more startup/background drain |
| `Browser TOTAL` flagged BLOAT | Close idle browser windows/tabs; run one browser family, not several |
| `Claude sessions` flagged TRIM | Close idle agent/terminal sessions |

**VERIFY [S5]**: Every `idle — 0 running` vendor and any BLOAT/TRIM flag appears in
the recommendations with a generic `launchctl bootout`+`disable` example.

---

### Step 6 [S6]: Bucket every finding by impact

| Bucket | Goes here |
|---|---|
| 🚨 MUST-RUN NOW | ONLY when SYSTEM STATE = CRITICAL — the single immediate action from S2 |
| 🔴 HIGH | The bound layer's fix; any runaway process; thermal; disk LOW-SPACE |
| 🟡 MEDIUM | Window/transparency/scaling amplifiers, browser/session bloat, >2GB helpers, long-running leaks |
| 🟢 LOW | Idle vendor boot weight, duplicate updaters, optional reboot |

**VERIFY [S6]**: Every flag from S2–S5 is in exactly one bucket. 🚨 appears only if
CRITICAL.

---

### Step 7 [S7]: Emit the report using this template

MUST output the sections below in order. This is a STRUCTURE template — fill
`{placeholders}` with THIS machine's data; copy no example values. The 🚨 section
appears ONLY when SYSTEM STATE = CRITICAL.

```markdown
## Mac Health Check — {chip} / {ram}GB / macOS {version}

{🚨 **MUST-RUN NOW** — only if SYSTEM STATE = CRITICAL:
one line naming the trigger + the single immediate command. Put this ABOVE the table.}

### Summary
| Metric | Value | Status |
|---|---|---|
| System state | {HEALTHY / STRAINED / CRITICAL + 1-line basis} | {🟢/🟡/🚨} |
| Memory | pressure level {N}, swap delta {N} ({"bound" only if ≥2 & delta>0}) | {icon} |
| Bound layer | {compositor / CPU / GPU / memory / none} | {icon} |
| CPU | {load} on {cores} cores = {util}% | {icon} |
| Disk | {free} GB free | {icon} |
| Uptime | {d days h hours} | {icon} |
| Confirmation | {"monitored Ns: <culprit> SUSTAINED" or "snapshot only (healthy quick audit)"} | {icon} |

{If pressure level is 1: one sentence stating memory is NOT the cause despite any large "used"/low "free", because pressure is normal and swap delta is 0.}

### Bound layer & responsible process
{What the measurement shows is bound, and the specific process the live data
named (from S3/S4), CONFIRMED by the 30s monitor (state it was SUSTAINED, not a
blip) — with the drilldown method used, not a guess.}

### Recommendations
{🚨 MUST-RUN NOW — only if CRITICAL}
**🔴 HIGH** — {item → why → fix}
**🟡 MEDIUM** — {item → why → fix}
**🟢 LOW** — {item → why → fix}

### Quick wins (copy-paste)
```bash
{only commands relevant to THIS machine's flags; GUI apps via quit, sudo handed to user}
```

### Next step — pick one
- {tailored option A}
- {tailored option B}
```

Status icon map: `HEALTHY`/`LOW`/`OK`/level 1 → 🟢; `STRAINED`/`MODERATE`/`MEDIUM`/level 2 → 🟡; `CRITICAL`/`HIGH`/level 4/`BLOAT`/`TRIM` → 🔴 (use 🚨 for the CRITICAL system state).

**VERIFY [S7]**: Final message has Summary, Bound layer & responsible process,
Recommendations, and a ```bash Quick wins block. If SYSTEM STATE was CRITICAL, a
🚨 MUST-RUN NOW line precedes the Summary.

---

## Quick Win Command Reference

Use only commands relevant to the flags raised. GUI apps → prefer `quit` over
`kill`. `sudo` commands MUST be handed to the user to run themselves.

```bash
# Restart a stuck GUI service (safe, auto-relaunches) — e.g. the file/UI layer
killall Finder

# Free memory under active thrash (stopgap; find+stop the real hog too)
sudo purge

# Lower a runaway process instead of killing it
sudo renice 20 -p <PID>
sudo taskpolicy -b -p <PID>      # confine to efficiency cores

# Quit an app not in use
osascript -e 'quit app "AppName"'

# Disable a launch job (modern macOS — NOT the deprecated launchctl unload)
sudo launchctl bootout system /Library/LaunchDaemons/<vendor.job>.plist
sudo launchctl disable system/<vendor.job-label>

# Terminate a specific heavy process by PID (warn the user first)
kill -TERM <PID>
```

`launchctl unload` is deprecated and fails on modern macOS — always use
`launchctl bootout` / `launchctl disable`. These need `sudo`; tell the user to run
them in their own terminal.

---

## Drilldowns and the window-leak detector

- **Per-layer durable fixes** (compositor leak/fill-rate, runaway daemon, memory,
  GPU): [guides/drilldowns.md](guides/drilldowns.md) — read the section for the
  bound layer from S3.
- `scripts/window_count.py` — EXECUTE via
  `uv run --no-project --with pyobjc-framework-Quartz python3`. Per-app CGWindow
  count; one owner with 100s–1000s = a compositor window leak (S4).

## Special Case: A Process That Keeps Respawning (launchd KeepAlive)

A process you `kill` returns with a new PID and **PPID=1** → a launchd job with
`KeepAlive=true` restarts it. The same program can be registered in MULTIPLE
domains at once — a `gui/<uid>` user agent AND a root `system` daemon — so
disabling only the user agent leaves the root daemon alive.

```bash
# Find every plist across all domains that launches the program
grep -rl "ProgramName" ~/Library/LaunchAgents /Library/LaunchAgents /Library/LaunchDaemons 2>/dev/null
# For each: bootout + disable (sudo only for the system daemon)
launchctl bootout      gui/$(id -u) ~/Library/LaunchAgents/<job>.plist
launchctl disable      gui/$(id -u)/<job-label>
sudo launchctl bootout system       /Library/LaunchDaemons/<job>.plist
sudo launchctl disable system/<job-label>
pgrep -fl "ProgramName"   # verify: prints nothing after a few seconds
```

Always warn the user before suggesting `kill` — prefer `osascript -e 'quit app'`
for GUI apps.
