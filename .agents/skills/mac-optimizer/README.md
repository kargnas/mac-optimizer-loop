# Mac Optimizer

A Claude Code skill that finds WHY a Mac is slow by measurement, then returns a
prioritized, copy-paste-ready optimization report. Works on any Mac — detection
keys off live measurements and roles, with no hardcoded list of apps to quit.

## What It Does

1. **Measures the four bottleneck layers** — CPU thread, GPU residency, memory
   pressure (kernel level + live swap delta), and the WindowServer compositor —
   and identifies which layer is actually bound.
2. **Flags a CRITICAL `SYSTEM STATE`** (active memory thrash, CPU oversubscription,
   near-full disk) so a "must act now" emergency is surfaced before tidy-up advice.
3. **Drills to the responsible process generically** — using `lsof` + `log show`
   to learn what a daemon is *doing*, and a CGWindow counter to catch compositor
   window leaks — instead of guessing from process names.
4. **Surfaces background/boot weight** — third-party launch jobs grouped by vendor
   (via `launchctl`), flagging vendors with zero running jobs.
5. Returns recommendations bucketed 🚨 MUST-RUN NOW / 🔴 HIGH / 🟡 MEDIUM / 🟢 LOW
   with durable fixes (most macOS culprits are SIP daemons that respawn — the
   durable fix removes the work source, not a whack-a-mole `kill`).

The collector script does all arithmetic and pre-flags every threshold in
deterministic bash, so the report stays consistent across models.

## Contents

- `mac-optimize.sh` — the collector (EXECUTE). Emits `DERIVED METRICS`,
  `BOTTLENECK LAYERS`, `SYSTEM STATE`, vendor boot weight, and raw process tables.
- `scripts/window_count.py` — per-app CGWindow counter for compositor window-leak
  detection (EXECUTE via `uv run --no-project --with pyobjc-framework-Quartz`).
- `guides/drilldowns.md` — per-layer durable fixes (generic, measurement-driven).
- `SKILL.md` — the workflow Claude follows.

## Usage

In any Claude Code session:

```
/mac-optimizer
```

Or conversationally: "Why is my Mac slow?", "My Mac lags during screen share",
"Check my Mac performance".

## Running the Script Standalone

```bash
bash ~/.claude/skills/mac-optimizer/mac-optimize.sh            # one-shot snapshot
bash ~/.claude/skills/mac-optimizer/mac-optimize.sh --monitor 30   # 30s sustained monitor
```

The snapshot prints raw + computed metrics (GPU block needs passwordless `sudo`
for `powermetrics`; skipped without it). `--monitor [seconds]` samples for a real
window and tags each process `SUSTAINED` / `intermittent` / `transient-blip`, plus
the load trend and whether swap thrashed — the confirmation pass that separates a
real culprit from a one-off spike (ps %CPU alone is a misleading lifetime average).

## Requirements

- macOS (Apple Silicon tested)
- Claude Code CLI
- `uv` (only for the optional window-leak detector)
- Built-in macOS tools otherwise (`ps`, `vm_stat`, `sysctl`, `top`, `launchctl`,
  `powermetrics`, `system_profiler`)
