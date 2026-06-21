#!/usr/bin/env python3
# Count CoreGraphics windows per owning app via the public CGWindowList API.
# A WindowServer window-count leak (one service holding hundreds/thousands of
# off-screen windows) bloats every compositing pass, which shows up as laggy
# window dragging / overlay lag even when GPU is idle. There is no built-in CLI
# for this, hence Quartz.
#
# Run with uv so pyobjc is fetched without polluting any project env:
#   uv run --no-project --with pyobjc-framework-Quartz python3 window_count.py
#
# Reads no arguments and no env vars.

import collections
import sys

try:
    import Quartz
except ImportError:
    sys.exit("Quartz unavailable — run via: uv run --no-project "
             "--with pyobjc-framework-Quartz python3 window_count.py")

all_w = Quartz.CGWindowListCopyWindowInfo(
    Quartz.kCGWindowListOptionAll, Quartz.kCGNullWindowID)
on_w = Quartz.CGWindowListCopyWindowInfo(
    Quartz.kCGWindowListOptionOnScreenOnly, Quartz.kCGNullWindowID)

print(f"total windows: {len(all_w)}   on-screen: {len(on_w)}")
print("(large total with small on-screen => off-screen windows still composited)")
print("\ncount  owner   # normal apps hold a handful; 100s/1000s for one owner = LEAK")
counts = collections.Counter(
    x.get('kCGWindowOwnerName', '?') for x in all_w)
for name, n in counts.most_common(15):
    flag = "  <== LEAK?" if n >= 100 else ""
    print(f"{n:5d}  {name}{flag}")
