#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: mac-optimizing-looper-format-json.sh --analysis-file PATH [--language LOCALE] [--model MODEL] [--output-dir DIR] [--claude PATH]
USAGE
}

language="system"
model="${CLAUDE_MODEL:-sonnet}"
analysis_file=""
output_dir="${TMPDIR:-/tmp}"
claude_bin="${CLAUDE_CLI_PATH:-}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --analysis-file)
      analysis_file="${2:-}"
      shift 2
      ;;
    --language)
      language="${2:-system}"
      shift 2
      ;;
    --model)
      model="${2:-sonnet}"
      shift 2
      ;;
    --output-dir)
      output_dir="${2:-}"
      shift 2
      ;;
    --claude)
      claude_bin="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [ -z "$analysis_file" ] || [ ! -r "$analysis_file" ]; then
  echo "--analysis-file is required and must be readable" >&2
  exit 2
fi

if [ -z "$output_dir" ]; then
  echo "--output-dir must not be empty" >&2
  exit 2
fi

if [ -z "$claude_bin" ]; then
  claude_bin="$(command -v claude || true)"
fi

if [ -z "$claude_bin" ] || [ ! -x "$claude_bin" ]; then
  echo "claude CLI not found; set --claude or CLAUDE_CLI_PATH" >&2
  exit 127
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to validate and emit formatter output" >&2
  exit 127
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
guide_script="$script_dir/mac-optimizing-looper-response-guide.sh"

if [ ! -x "$guide_script" ]; then
  echo "response guide script not found: $guide_script" >&2
  exit 127
fi

mkdir -p "$output_dir"
run_id="$(uuidgen 2>/dev/null || date +%s)"
run_dir="$output_dir/mac-optimizing-looper-format-$run_id"
mkdir -p "$run_dir"

prompt_path="$run_dir/prompt.txt"
raw_path="$run_dir/claude.raw.txt"
json_path="$run_dir/advice.json"
candidate_path="$run_dir/candidate.json"

system_prompt="Format the supplied macOS load analysis. Follow the response guide exactly. Return only final JSON."

{
  "$guide_script" --language "$language"
  printf '\nAnalysis notes to format:\n'
  cat "$analysis_file"
} >"$prompt_path"

"$claude_bin" \
  -p \
  --no-session-persistence \
  --output-format text \
  --effort low \
  --system-prompt "$system_prompt" \
  --model "$model" \
  <"$prompt_path" \
  >"$raw_path"

if ! jq -e . "$raw_path" >"$json_path" 2>/dev/null; then
  perl -0ne '
    my $s = $_;
    my $start = index($s, "{");
    exit 1 if $start < 0;
    my ($depth, $in_string, $escape, $end) = (0, 0, 0, -1);
    for (my $i = $start; $i < length($s); $i++) {
      my $c = substr($s, $i, 1);
      if ($in_string) {
        if ($escape) {
          $escape = 0;
        } elsif ($c eq "\\") {
          $escape = 1;
        } elsif ($c eq "\"") {
          $in_string = 0;
        }
        next;
      }
      if ($c eq "\"") {
        $in_string = 1;
      } elsif ($c eq "{") {
        $depth++;
      } elsif ($c eq "}") {
        $depth--;
        if ($depth == 0) {
          $end = $i;
          last;
        }
      }
    }
    exit 1 if $end < $start;
    print substr($s, $start, $end - $start + 1);
  ' "$raw_path" >"$candidate_path"
  jq -e . "$candidate_path" >"$json_path"
fi

jq -e '
  type == "object" and
  (.summary | type == "string") and
  (.statusBar | type == "object") and
  (.statusBar.title | type == "string" and length > 0) and
  (.statusBar.color | type == "string" and length > 0) and
  (.suggestions | type == "array") and
  all(.suggestions[]; (
    (.title | type == "string") and
    (.detail | type == "string") and
    (.rationale | type == "string") and
    (.severity | type == "object") and
    (.severity.id | type == "string" and length > 0) and
    (.severity.label | type == "string") and
    (.severity.icon | type == "string" and length > 0) and
    (.severity.color | type == "string" and length > 0) and
    ((.severity.rank == null) or (.severity.rank | type == "number")) and
    ((.suggestedCommand == null) or (.suggestedCommand | type == "string")) and
    ((.targetProcessName == null) or (.targetProcessName | type == "string"))
  ))
' "$json_path" >/dev/null

jq -n \
  --arg jsonPath "$json_path" \
  --arg rawPath "$raw_path" \
  --arg promptPath "$prompt_path" \
  --arg language "$language" \
  --arg model "$model" \
  '{
    jsonPath: $jsonPath,
    rawPath: $rawPath,
    promptPath: $promptPath,
    language: $language,
    model: $model
  }'
