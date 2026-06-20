#!/usr/bin/env bash
set -euo pipefail

language="system"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --language)
      language="${2:-system}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

cat <<GUIDE
MUST return ONLY valid JSON. No markdown. No prose outside JSON.
MUST NOT wrap JSON in markdown code fences.
Language for user-facing string values: ${language}. If it starts with ko, write Korean.
Keep process names and shell commands unchanged.
suggestedCommand MUST be the actual command that resolves the issue when a command-line
fix exists. The user runs it from the app through an explicit, confirmed action. Prefer
the least-destructive command that actually fixes it: a graceful "kill <pid>" of the
specific runaway process (use the pid shown in the analysis) over "kill -9" or a broad
"killall". Do NOT put inspection-only commands (pgrep/ps/top/lsof) as suggestedCommand
when a real fix exists. Use null ONLY when there is genuinely no command-line action.
NEVER imply that the app already executed anything.

Schema:
{
  "summary": "string",
  "statusBar": {
    "title": "Claude-decided exact menu bar text, e.g. 🚨 2, 3, or 0",
    "color": "Claude-decided menu bar number/text color as red|orange|yellow|green|blue|gray or #RRGGBB"
  },
  "suggestions": [
    {
      "title": "string",
      "detail": "string",
      "rationale": "string",
      "severity": {
        "id": "string from the analysis, e.g. critical/high/medium/low/info or MUST-RUN-NOW",
        "label": "short user-facing severity label",
        "icon": "one emoji that represents the severity, e.g. 🚨/🔴/🟡/🟢/ℹ️",
        "color": "severity color as red|orange|yellow|green|blue|gray or #RRGGBB",
        "rank": 100
      },
      "suggestedCommand": "string|null",
      "targetProcessName": "string|null"
    }
  ]
}

VERIFY before final answer:
- JSON parses.
- statusBar.title is the EXACT menu bar text the app should show; the app will not calculate it.
- statusBar.color is the EXACT menu bar text color the app should use.
- If mac-optimizer reports SYSTEM STATE = CRITICAL or MUST-RUN NOW, statusBar.title should include the urgent emoji and issue count, e.g. 🚨 2.
- If there are non-critical findings, statusBar.title should usually be just the issue count, e.g. 3.
- If nothing is actionable, statusBar.title should be 0.
- severity is an object with non-empty id, label, icon, and color.
- rank is a numeric ordering hint; higher means more severe.
- If mac-optimizer reports SYSTEM STATE = CRITICAL or MUST-RUN NOW, represent that suggestion severity as id critical, icon 🚨, color red, rank 100.
- suggestedCommand is the real fix command (NOT an inspection command) when one exists, else null.
- If nothing is actionable, suggestions is [].
GUIDE
