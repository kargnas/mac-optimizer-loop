#!/usr/bin/env bash
# mac-optimize.sh — Collects macOS performance data for analysis
set -uo pipefail

# Redact sensitive patterns from process output
redact() {
    sed -E 's/(token|key|password|secret|credential|auth)=[^ ]*/\1=REDACTED/gi'
}

echo "WARNING: This output may contain sensitive information (process arguments,"
echo "paths, usernames). Review before sharing publicly."
echo ""

# ── Sustained monitor mode ───────────────────────────────────────────────────
# Why: the default one-shot dump reads ps %CPU, which on macOS is a lifetime
# DECAYING AVERAGE (not "right now") and misses intermittent hogs. `--monitor
# [SECONDS]` samples a real window (default 30s) via a single `top -l` capture and
# separates SUSTAINED culprits from transient blips — this is the confirmation
# pass the analysis runs AFTER the one-shot flags a suspect.
if [ "${1:-}" = "--monitor" ]; then
  DUR="${2:-30}"; case "$DUR" in ''|*[!0-9]*) DUR=30 ;; esac
  INT=3; N=$(( DUR / INT + 1 )); [ "$N" -lt 3 ] && N=3
  echo "=== SUSTAINED MONITOR (${DUR}s window, ${INT}s interval, $((N-1)) measured samples) ==="
  TMP="$(mktemp)"
  # One capture yields per-sample process CPU rows, Load Avg, and the VM swap line,
  # so load trend + swap thrash + process persistence all come from one 30s run.
  # -stats pid,cpu,command puts %CPU in field 2 (single token) so multi-word
  # command names (e.g. "Code Helper (Renderer)") parse cleanly as the remainder.
  top -l "$N" -s "$INT" -n 12 -o cpu -stats pid,cpu,command 2>/dev/null > "$TMP"

  echo "-- Load average trend (skip warmup sample) --"
  grep -i "Load Avg:" "$TMP" | sed -E 's/.*Load Avg:[[:space:]]*//; s/,.*//' \
    | awk -v nc="$(sysctl -n hw.ncpu 2>/dev/null || echo 1)" '
        NR>1 { v=$1+0; if(n==0)first=v; s+=v; n++; if(v>mx)mx=v; last=v }
        END { if(n>0) printf "  samples=%d first=%.2f last=%.2f peak=%.2f (cores=%s, peak util=%.0f%%)\n", n, first, last, mx, nc, mx/nc*100; else print "  (no load samples)" }'

  echo "-- Swap-out delta per sample (any >0 => intermittent thrash during window) --"
  grep -i "^VM:" "$TMP" | sed -nE 's/.*[0-9]+\(([0-9]+)\) swapouts.*/\1/p' \
    | awk 'NR>1{ n++; tot+=$1; if($1>0)thr++ }
           END{ printf "  measured=%d samples_swapping=%d total_swapout_delta=%d -> %s\n", n+0, thr+0, tot+0, (thr>0?"THRASHED during window":"no active swapping") }'

  echo "-- Process CPU persistence (SUSTAINED = real culprit; blip = ignore) --"
  # Aggregate by PID (one row per PID per sample) so "seen K/N" is a valid sample
  # count — grouping by command name would double-count multi-process apps (e.g.
  # several "Code Helper" renderers) and print impossible ratios like 4/3.
  awk '
    /^Processes:/ { samp++ }
    samp>=2 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9.]+$/ {
      pid=$1; cpu=$2; line=$0;
      sub(/^[[:space:]]*[0-9]+[[:space:]]+[0-9.]+[[:space:]]+/,"",line);
      sub(/[[:space:]]+$/,"",line);
      cnt[pid]++; sum[pid]+=cpu; if(cpu>mx[pid])mx[pid]=cpu; name[pid]=line;
    }
    END {
      meas=samp-1; if(meas<1)meas=1;
      for(p in cnt){
        avg=sum[p]/cnt[p]; seen=(cnt[p]>meas?meas:cnt[p]);
        if(avg<5 && mx[p]<15) continue;                       # drop low-noise
        v=(seen>=meas*0.6 && avg>=10)?"SUSTAINED":(seen<=1?"transient-blip":"intermittent");
        printf "%d/%d\t%.0f\t%.0f\t%s\t%s\n", seen, meas, avg, mx[p], v, name[p];
      }
    }' "$TMP" \
    | sort -t"$(printf '\t')" -k2 -nr | head -12 \
    | awk -F'\t' 'BEGIN{print "  seen   avg%  peak%  verdict        process"}
                  {printf "  %-6s %-5s %-6s %-14s %s\n", $1, $2, $3, $4, $5}'

  rm -f "$TMP"
  echo "=== MONITOR DONE ==="
  exit 0
fi

echo "=== SYSTEM INFO ==="
sysctl -n machdep.cpu.brand_string
echo "Cores: $(sysctl -n hw.ncpu)"
echo "RAM: $(( $(sysctl -n hw.memsize) / 1073741824 )) GB"
sw_vers
uptime

echo ""
echo "=== MEMORY ==="
vm_stat
echo "---SWAP---"
sysctl vm.swapusage

echo ""
echo "=== DERIVED METRICS (computed — report these values directly) ==="
# Why: weaker LLMs miscompute vm_stat page-math (page size is 16KB on Apple
# Silicon, not 4KB) and misread "free" as the only pressure signal. We do the
# arithmetic + flagging here in deterministic bash so the model only transcribes
# the values and applies the printed flags — matching a stronger model's output.
_VMSTAT="$(vm_stat 2>/dev/null)"
_PAGESIZE="$(printf '%s\n' "$_VMSTAT" | sed -n 's/.*page size of \([0-9][0-9]*\) bytes.*/\1/p')"
: "${_PAGESIZE:=16384}"
_RAM_BYTES="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
_NCPU="$(sysctl -n hw.ncpu 2>/dev/null || echo 1)"
_LOAD1="$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')"; : "${_LOAD1:=0}"
# Pull one vm_stat counter by label (handles 16KB pages + trailing period)
_vmget() { printf '%s\n' "$_VMSTAT" | awk -F: -v k="$1" 'index($0,k)==1{gsub(/[^0-9]/,"",$2);print $2; exit}'; }
_FREE_P="$(_vmget "Pages free")";                    : "${_FREE_P:=0}"
_INACT_P="$(_vmget "Pages inactive")";               : "${_INACT_P:=0}"
_SPEC_P="$(_vmget "Pages speculative")";             : "${_SPEC_P:=0}"
_PURG_P="$(_vmget "Pages purgeable")";               : "${_PURG_P:=0}"
_ACT_P="$(_vmget "Pages active")";                   : "${_ACT_P:=0}"
_WIRE_P="$(_vmget "Pages wired down")";              : "${_WIRE_P:=0}"
_COMP_P="$(_vmget "Pages occupied by compressor")";  : "${_COMP_P:=0}"
_SWAP_LINE="$(sysctl -n vm.swapusage 2>/dev/null)"
_SWAP_USED_M="$(printf '%s\n' "$_SWAP_LINE" | sed -n 's/.*used = \([0-9.]*\)M.*/\1/p')"; : "${_SWAP_USED_M:=0}"
_SWAP_TOT_M="$(printf '%s\n' "$_SWAP_LINE" | sed -n 's/.*total = \([0-9.]*\)M.*/\1/p')";  : "${_SWAP_TOT_M:=0}"
_DISK_FREE_GB="$(df -g / 2>/dev/null | awk 'NR==2{print $4}')"; : "${_DISK_FREE_GB:=0}"
# boottime line: "{ sec = 1718900000, usec = 0 } ...". Split on spaces/commas, take
# field 4 (the sec value). A greedy ".*sec" sed wrongly matches "usec" -> boot=0.
_BOOT="$(sysctl -n kern.boottime 2>/dev/null | awk -F'[ ,]+' '{print $4}')"; : "${_BOOT:=0}"
case "$_BOOT" in ''|*[!0-9]*) _BOOT=$(date +%s) ;; esac
_NOW="$(date +%s)"
# Honest "is it bad RIGHT NOW" inputs (also reused by BOTTLENECK LAYERS below):
# kernel memory pressure level (1=normal 2=warn 4=critical) + the LIVE swap-out
# delta (the (N) before 'swapouts'). delta>0 means actively paging out = thrashing.
_PL="$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null || echo 1)"; case "$_PL" in ''|*[!0-9]*) _PL=1 ;; esac
_VMLINE="$(top -l 2 -n 0 2>/dev/null | grep -i '^VM:' | tail -1)"
_SWAPOUT_DELTA="$(printf '%s\n' "$_VMLINE" | sed -nE 's/.*[0-9]+\(([0-9]+)\) swapouts.*/\1/p')"; : "${_SWAPOUT_DELTA:=0}"
awk -v ps="$_PAGESIZE" -v ram="$_RAM_BYTES" -v ncpu="$_NCPU" -v load="$_LOAD1" \
    -v free="$_FREE_P" -v inact="$_INACT_P" -v spec="$_SPEC_P" -v purg="$_PURG_P" \
    -v act="$_ACT_P" -v wire="$_WIRE_P" -v comp="$_COMP_P" \
    -v swu="$_SWAP_USED_M" -v swt="$_SWAP_TOT_M" -v disk="$_DISK_FREE_GB" \
    -v pl="$_PL" -v swod="$_SWAPOUT_DELTA" \
    -v boot="$_BOOT" -v now="$_NOW" 'BEGIN{
  g=1073741824; ramgb=ram/g;
  freegb=free*ps/g; inactgb=inact*ps/g; specgb=spec*ps/g; purggb=purg*ps/g;
  actgb=act*ps/g; wiregb=wire*ps/g; compgb=comp*ps/g;
  reclaim=inactgb+specgb+purggb; availgb=freegb+reclaim; swugb=swu/1024; swtgb=swt/1024;
  printf "RAM total: %.0f GB\n", ramgb;
  printf "Memory active (apps): %.1f GB\n", actgb;
  printf "Memory wired (kernel): %.1f GB\n", wiregb;
  printf "Memory compressor: %.1f GB\n", compgb;
  printf "Memory free: %.1f GB\n", freegb;
  printf "Memory reclaimable (inactive+spec+purgeable): %.1f GB\n", reclaim;
  printf "Memory available (free+reclaimable): %.1f GB\n", availgb;
  printf "Swap used/total: %.2f / %.2f GB\n", swugb, swtgb;
  mp="LOW";
  if (swugb > 0.5*ramgb || availgb < 2) mp="HIGH";
  else if (swugb > 0 || availgb < 8) mp="MEDIUM";
  printf "Memory pressure: %s  [HIGH if swap>0.5xRAM or avail<2GB; MED if swap>0 or avail<8GB; else LOW]\n", mp;
  util=(ncpu>0)?load/ncpu*100:0; cp="LOW";
  if (util>90) cp="HIGH"; else if (util>50) cp="MEDIUM"; else if (util>25) cp="MODERATE";
  printf "Load avg(1m): %.2f on %d cores = %.0f%% util -> CPU pressure: %s\n", load, ncpu, util, cp;
  printf "Disk free (root): %s GB -> %s\n", disk, (disk+0<20?"LOW-SPACE (<20GB)":"OK");
  up=now-boot; d=int(up/86400); h=int((up%86400)/3600);
  printf "Uptime: %d days %d hours -> %s\n", d, h, (up>604800?"reboot RECOMMENDED (>7 days)":"reboot optional");

  # ---- SYSTEM STATE: the MUST-ACT-NOW gate ----
  # CRITICAL = the box is actively degrading right now (not "could be tidier").
  # Each trigger is an HONEST live signal, generic to any Mac:
  state="HEALTHY"; why="";
  if (pl>=2 && swod>0)      { state="CRITICAL"; why=why "active memory thrash (pressure " pl ", swapping out now); " }
  if (util>200)             { state="CRITICAL"; why=why "CPU oversubscribed " sprintf("%.0f",util) "% (load>2x cores); " }
  if (disk+0 < 5)           { state="CRITICAL"; why=why "disk almost full (" disk "GB); " }
  if (state!="CRITICAL") {
    if (pl>=2 || util>100 || availgb<4 || swugb>0.5*ramgb || disk+0<20) {
      state="STRAINED";
      why="pressure=" pl ", cpu=" sprintf("%.0f",util) "%, avail=" sprintf("%.1f",availgb) "GB, disk=" disk "GB";
    } else { why="pressure=" pl ", swap delta=" swod ", cpu=" sprintf("%.0f",util) "%, avail=" sprintf("%.1f",availgb) "GB"; }
  }
  printf "SYSTEM STATE: %s  (%s)\n", state, why;
  if (state=="CRITICAL") print "  >>> MUST ACT NOW: surface the single immediate action for the trigger above, before any HIGH/MED/LOW advice.";
}'

echo ""
echo "=== BOTTLENECK LAYERS (measurement-first — which layer is bound?) ==="
# Why: a slow Mac is bound by ONE of four layers (CPU / GPU / memory / compositor).
# Naming an app to quit is guessing. These are the *honest* per-layer signals so
# the analysis can identify the bound layer first, then drill to the responsible
# process generically — on ANY Mac, with no hardcoded app list.

# MEMORY — kernel pressure level is the truth, NOT "used GB". Reuse values already
# captured above (avoids a second slow `top -l 2` call). delta 0 = NOT swapping now.
echo "Memory pressure level (kernel): $_PL  (1=normal 2=warn 4=critical — memory-bound ONLY if >=2)"
echo "Swap delta this sample (the (N) before swapins/outs = live delta; 0 = not swapping now):"
echo "  ${_VMLINE:-(swap delta unavailable)}"

# GPU — is it even the bottleneck? High idle residency + low clock => GPU is NOT bound
# (rules out fill-rate / GPU compositing). Needs root; skipped cleanly if unavailable.
echo "GPU residency (idle-heavy + low clock => GPU is NOT the bottleneck):"
if sudo -n true 2>/dev/null; then
  sudo -n powermetrics --samplers gpu_power -n 1 -i 400 2>/dev/null | \
    grep -iE 'GPU.*(active|idle).*residency|GPU Power|GPU HW active frequency' | head -3 || echo "  (no GPU sample)"
else
  echo "  (skipped: passwordless sudo unavailable — run 'sudo powermetrics --samplers gpu_power -n 1' to measure GPU)"
fi

# COMPOSITOR — WindowServer found by name (NOT a hardcoded PID). High CPU here + GPU
# idle (above) => CPU-single-thread compositor bound (window-count leak / transparency).
_WS_PID="$(pgrep -x WindowServer | head -1)"
if [ -n "${_WS_PID:-}" ]; then
  ps -o pid,pcpu,rss,etime -p "$_WS_PID" 2>/dev/null | tail -1 | \
    awk '{printf "WindowServer (compositor): pid=%s cpu=%s%% rss=%.0fMB uptime=%s\n",$1,$2,$3/1024,$4}'
else
  echo "WindowServer: not found"
fi
echo "Displays ('UI Looks like' LARGER than native => supersampled framebuffer = expensive):"
system_profiler SPDisplaysDataType 2>/dev/null | grep -iE 'Resolution:|UI Looks like:' || echo "  (display info unavailable)"

echo ""
echo "=== TOP PROCESSES BY CPU ==="
ps auxc -r | head -25 || true

echo ""
echo "=== TOP PROCESSES BY MEMORY ==="
ps auxc -m | head -25 || true

echo ""
echo "=== PROCESS SUMMARY ==="
echo "Total processes: $(ps aux | wc -l | tr -d ' ')"
echo "Total threads: $(ps -M -e | wc -l | tr -d ' ')"

echo ""
echo "=== BROWSER PROCESSES ==="
_btotal=0; _bcount=0
for browser in "Google Chrome" "Brave Browser" "Firefox" "Safari" "Arc" "Microsoft Edge"; do
    count=$(ps aux | grep -iF "$browser" | grep -v grep | wc -l | tr -d ' ')
    if [ "$count" -gt 0 ]; then
        mem=$(ps aux | grep -iF "$browser" | grep -v grep | awk '{sum+=$4} END {printf "%.1f", sum}')
        cpu=$(ps aux | grep -iF "$browser" | grep -v grep | awk '{sum+=$3} END {printf "%.1f", sum}')
        echo "$browser: $count processes, ${mem}% RAM, ${cpu}% CPU"
        _btotal=$((_btotal + count)); _bcount=$((_bcount + 1))
    fi
done
# Pre-flagged: >50 procs OR >1 chromium family running = browser bloat
echo "Browser TOTAL: $_btotal processes across $_bcount browsers -> $([ "$_btotal" -gt 50 ] || [ "$_bcount" -gt 1 ] && echo "BLOAT (close idle browsers/tabs)" || echo "OK")"

echo ""
echo "=== CLAUDE CODE SESSIONS ==="
ps aux | grep -w "claude" | grep -v grep | awk '{printf "PID:%s CPU:%s%% MEM:%s%% RSS:%dMB\n", $2, $3, $4, $6/1024}' | redact || echo "None"
# Pre-flagged: count sessions holding >200MB RSS (real sessions, not MCP stubs); >3 = trim
ps aux | grep -w "claude" | grep -v grep | awk '{if($6/1024>200){n++; sum+=$6}} END {printf "Claude sessions >200MB: %d, RSS sum: %.1f GB -> %s\n", n+0, sum/1048576, (n>3?"TRIM idle sessions":"OK")}'

echo ""
echo "=== DISK USAGE ==="
df -h /
diskutil info / | grep -E "Free|Available|Purgeable" || true

echo ""
echo "=== POWER & THERMAL ==="
pmset -g 2>/dev/null | grep -E "lowpowermode|sleep|displaysleep" || true
pmset -g therm 2>/dev/null || true

echo ""
echo "=== LOGIN ITEMS ==="
osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null || echo "Unable to read"

echo ""
echo "=== USER LAUNCH AGENTS ==="
ls "$HOME/Library/LaunchAgents/" 2>/dev/null || echo "None"

echo ""
echo "=== SYSTEM LAUNCH DAEMONS ==="
ls /Library/LaunchDaemons/ 2>/dev/null || echo "None"

echo ""
echo "=== THIRD-PARTY LAUNCH JOBS (login/gui domain, vendor-grouped, Apple excluded) ==="
# Why: instead of hardcoding 'is ExpressVPN running?', ask launchd itself. Each
# login/agent job is discovered from `launchctl list` (authoritative, sudo-free):
# a numeric PID = currently running, '-' = loaded but idle. Group by reverse-domain
# vendor so the analysis sees, on ANY Mac, which third-party vendors carry the most
# login weight and which have ZERO running jobs (pure boot weight to disable).
launchctl list 2>/dev/null \
  | awk 'NR>1 {
      lbl=$3; sub(/^application\./,"",lbl);
      if (lbl ~ /^com\.apple/) next;   # exclude Apple, incl. application.com.apple.*
      n=split(lbl,a,".");
      v=(a[1] ~ /^(com|org|io|net|us|kr|co|dev|app|me)$/ && n>=2)? a[2] : a[1];
      jobs[v]++; if ($1 ~ /^[0-9]+$/) run[v]++;
    }
    END { for (v in jobs) printf "%s\t%d\t%d\n", v, jobs[v], run[v]+0 }' \
  | sort -t"$(printf '\t')" -k2 -nr \
  | while IFS="$(printf '\t')" read -r vendor jobs run; do
      [ -z "$vendor" ] && continue
      if [ "${run:-0}" -gt 0 ]; then
        verdict="in use ($run running)"
      else
        verdict="idle — 0 running (boot weight; disable if unused)"
      fi
      echo "$vendor: $jobs job(s), $verdict"
    done

echo ""
echo "=== HEAVY LONG-RUNNING PROCESSES (>1hr CPU time) ==="
# ps TIME is MM:SS.ss (or HH:MM:SS). Convert to hours inline so models don't
# misread "662:30" (662 min = 11h) as 662 hours.
ps aux | awk 'NR>1 {n=split($10,t,":"); mins=(n==3)?t[1]*60+t[2]:t[1]; if(mins>=60) printf "PID:%s CPU_TIME:%s (%.1fh) CMD:%s\n", $2, $10, mins/60, $11}' | head -20 | redact || true

echo ""
echo "=== DOCKER / VM ==="
if pgrep -q "Docker|OrbStack|colima|qemu"; then
    echo "Container runtime detected:"
    ps aux | grep -F $'Docker\nOrbStack\ncolima\nqemu' | grep -v grep | awk '{printf "PID:%s CPU:%s%% MEM:%s%% CMD:%s\n", $2, $3, $4, $11}' | redact
else
    echo "No container runtime detected"
fi

echo ""
echo "=== NETWORK CONNECTIONS (established) ==="
netstat -an 2>/dev/null | grep ESTABLISHED | wc -l | tr -d ' '
echo "established connections"
