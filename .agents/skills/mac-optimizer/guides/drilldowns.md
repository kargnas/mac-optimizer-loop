# Per-layer drilldowns (generic, measurement-driven)

Once the collector's `=== BOTTLENECK LAYERS ===` block tells you WHICH layer is
bound, follow the matching section. Each section is a method that works on ANY
Mac — it discovers the responsible process from live signals, never from a
hardcoded list of apps. Each ends with a *durable* fix, because most macOS
culprits are SIP-protected daemons that respawn (killing them is whack-a-mole;
the durable fix removes the work source).

## Table of contents
- [Compositor: window-count leak](#compositor-window-count-leak)
- [Compositor: fill-rate (transparency / display scaling)](#compositor-fill-rate)
- [CPU: runaway daemon or process](#cpu-runaway-daemon-or-process)
- [Memory: confirm it is or is NOT the cause](#memory-confirm-it-is-or-is-not-the-cause)
- [GPU](#gpu)

---

## Compositor: window-count leak

Symptom (from the probe): WindowServer high CPU **and** GPU idle residency high /
low clock. The compositor is CPU-thread bound because each frame walks too many
windows.

Drill — count windows per owning app (no hardcoded names; flags whatever owner is
leaking):
```bash
uv run --no-project --with pyobjc-framework-Quartz python3 \
  "$HOME/.claude/skills/mac-optimizer/scripts/window_count.py"
```
Any single owner holding 100s–1000s of windows is the leak (normal apps hold a
handful). Whatever owner the script flags is the target — read its name from the
output, do not assume.

Durable fix (the flagged owner respawns clean with 1 window, safe):
```bash
kill -9 $(pgrep -x "<OwnerNameFromScript>")   # use the exact owner the script flagged
```
Re-run `window_count.py` to confirm the count dropped to single digits.

---

## Compositor: fill-rate

If WindowServer is busy **and** GPU is NOT idle (active residency high at high
clock), the cost is per-pixel fill-rate. Two universal levers, both user-side:

1. **Transparency** — blur behind menu bar / Dock / sidebars is a full-screen GPU
   pass recomputed on every motion. Turn off: System Settings → Accessibility →
   Display → **Reduce transparency** ON. Often the single biggest win; verify by
   re-probing (GPU active residency should drop toward idle).
2. **Display scaling** — in the probe's `Displays` line, if "UI Looks like" is
   LARGER than the panel's native resolution, the Mac renders a supersampled
   framebuffer then downscales (e.g. rendering 4608×2592 for a 4K panel). Set the
   display to its **default / native** scale: System Settings → Displays → Default.
   Cuts framebuffer pixels and removes the non-integer downscale step.

Screen sharing/recording adds a framebuffer capture+encode every frame on top of
compositing, so these levers matter most while sharing.

---

## CPU: runaway daemon or process

Symptom: a process (often a background daemon, not the app you are using) holds
~1+ core. Identify what it is actually doing — **do NOT guess from the name**.
This method finds the work source for ANY daemon:

```bash
P=<PID from the CPU list>
# What is it touching? (open files reveal the data/feature driving it)
sudo lsof -p $P 2>/dev/null | awk '{print $NF}' | grep -iE '\.(sqlite|db|photoslibrary|log)$|Library|Caches' | sort -u | head
# What task is it running? (recent log reveals the activity type)
sudo log show --last 2m --predicate "processID == $P" 2>/dev/null | tail -15
```
The open files reveal the target (e.g. a photo/media library, a sync folder); the
log reveals the task type (e.g. a text-recognition or indexing task). Together
they name the **feature** to turn off — which is the durable fix, because the
daemon is SIP-protected and `launchctl bootout` is blocked for it.

Durable-fix principle (generic):
1. The open files/log point to a user-facing feature or a third-party app.
2. If it is an OS feature → turn that feature off in System Settings (e.g. a
   visual/text-recognition feature, indexing of a specific volume, a sync option).
3. If it is a third-party app's helper → quit that app (`osascript -e 'quit app
   "<Name>"'` or `pkill -i "<name>"`).
4. Many analysis backlogs are FINITE (photo/media/spotlight indexing): left
   plugged in + idle they drain and stop on their own. The Settings toggle is for
   reclaiming the cores *now*.

Temporary relief while you find the source (does NOT survive respawn):
```bash
sudo renice 20 -p $P       # lowest priority
sudo taskpolicy -b -p $P   # confine to efficiency (E) cores
```

For a process *family* leak (a parent respawning children without reaping), kill
the orphaned subtree, keep the parent:
```bash
collect(){ for c in $(pgrep -P "$1"); do echo "$c"; collect "$c"; done; }
echo $(collect <PARENT_PID>) | xargs kill -TERM
```

---

## Memory: confirm it is or is NOT the cause

On a high-RAM Mac, "memory full" is almost always a red herring: macOS counts
reclaimable cache + compressor inside "used". Trust only the two honest signals
from the probe:
- **kernel pressure level** — must be ≥2 (warn) or 4 (critical) to matter. 1 = fine.
- **live swap-out delta** — the `(N)` before `swapouts` in the VM line. >0 means
  actively paging out NOW. A large *cumulative* `vm.swapusage` with delta 0 is
  stale leftover from a past spike — harmless, clears on reboot.

Memory is the bottleneck ONLY when pressure ≥2 **AND** swap-out delta >0 (this is
also the collector's CRITICAL "active memory thrash" trigger). Then find the hog
generically:
```bash
ps axro 'rss,pid,comm' | head -16                          # top RSS processes
# sum RSS by command name to catch a leaking multi-process family:
ps axo rss,comm | awk '{g[$2]+=$1} END{for(c in g) printf "%.1fGB\t%s\n", g[c]/1048576, c}' | sort -rn | head
```
Kill the worst offender or its orphaned subtree (see the family-leak snippet
above). If pressure is 1 / delta 0, STOP blaming memory and re-check the other
layers.

---

## GPU

If the probe shows high GPU active residency at high clock, the GPU is the
bottleneck (rare for UI lag; common for video/render/ML). There is no quick kill —
reduce the workload: close the rendering/encoding app, stop on-device ML/analysis
daemons surfaced in the CPU section, or lower capture/export resolution.
