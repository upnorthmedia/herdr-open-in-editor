#!/usr/bin/env bash
# Runs the plugin script against fixture files with a stub editor CLI and a
# stub herdr binary, then checks the argv the editor received.
# Usage: bash tests/run.sh  (TEST_BASH=/bin/bash checks macOS bash 3.2)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
script="$root/bin/open-in-zed.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/repo/src" "$tmp/state" "$tmp/bin"
touch "$tmp/repo/src/app.ts" "$tmp/repo/src/a+b.ts" "$tmp/repo/src/with space.ts"

# Stub editor CLI: records its argv, one argument per line.
cat >"$tmp/bin/editor" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$@" >"$tmp/editor.args"
STUB
# Stub herdr: records notification bodies.
cat >"$tmp/bin/herdr" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >"$tmp/notify.args"
STUB
chmod +x "$tmp/bin/editor" "$tmp/bin/herdr"

failures=0

# run MODE CONTEXT_JSON [clicked_url]
run() {
  rm -f "$tmp/editor.args" "$tmp/notify.args" "$tmp/exit"
  HERDR_PLUGIN_CONTEXT_JSON="$2" \
    HERDR_PLUGIN_CLICKED_URL="${3:-}" \
    HERDR_PLUGIN_STATE_DIR="$tmp/state" \
    HERDR_BIN_PATH="$tmp/bin/herdr" \
    ZED_CLI="$tmp/bin/editor" \
    "${TEST_BASH:-bash}" "$script" "$1" >/dev/null 2>"$tmp/stderr" || printf 'exit %s\n' "$?" >"$tmp/exit"
}

# expect NAME EXPECTED_ARGS (newline-separated)
expect() {
  local got
  if [ -f "$tmp/exit" ]; then
    got="<$(cat "$tmp/exit")>"
  else
    got="$(cat "$tmp/editor.args" 2>/dev/null || printf '<editor not run: %s>' "$(cat "$tmp/notify.args" 2>/dev/null)")"
  fi
  if [ "$got" = "$2" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s\n  expected: %s\n  got:      %s\n' "$1" "$2" "$got"
    failures=$((failures + 1))
  fi
}

ctx() {
  jq -cn --arg cwd "$tmp/repo" --arg sel "${1:-}" \
    '{workspace_cwd: $cwd, focused_pane_cwd: $cwd} + (if $sel == "" then {} else {selected_text: $sel} end)'
}

repo="$tmp/repo"

run workspace "$(ctx)"
expect "workspace opens the workspace folder" "$repo"

run pane "$(ctx)"
expect "pane opens the pane folder" "$repo"

run selection "$(ctx 'src/app.ts')"
expect "relative path" "$repo/src/app.ts"

run selection "$(ctx './src/app.ts:12')"
expect "path with line" "$repo/src/app.ts:12"

run selection "$(ctx "$repo/src/app.ts:12:3")"
expect "absolute path with line and column" "$repo/src/app.ts:12:3"

run selection "$(ctx 'src/app.ts#L40-L45')"
expect "GitHub-style line anchor" "$repo/src/app.ts:40"

run selection "$(ctx 'Read(src/app.ts)')"
expect "tool-call wrapper" "$repo/src/app.ts"

run selection "$(ctx '`src/app.ts:7`,')"
expect "backticks and trailing punctuation" "$repo/src/app.ts:7"

run selection "$(ctx '"src/with space.ts"')"
expect "quoted path with a space" "$repo/src/with space.ts"

run link "$(ctx)" "file://$repo/src/with%20space.ts"
expect "file URL with an encoded space" "$repo/src/with space.ts"

run link "$(ctx)" "file://$repo/src/a+b.ts"
expect "file URL keeps a literal plus" "$repo/src/a+b.ts"

run link "$(ctx)" "file://localhost$repo/src/app.ts"
expect "file URL with localhost host" "$repo/src/app.ts"

run link "$(ctx)" "vscode://file$repo/src/app.ts:9:2"
expect "editor deep link" "$repo/src/app.ts:9:2"

run selection "$(ctx 'src/missing.ts')"
expect "missing relative path notifies" "<editor not run: notification show Open in Zed --body No file or folder found for: src/missing.ts>"

run selection "$(ctx '/nonexistent/file.ts')"
expect "missing absolute path notifies" "<editor not run: notification show Open in Zed --body No file or folder found for: /nonexistent/file.ts>"

if [ "$failures" -gt 0 ]; then
  printf '%d failed\n' "$failures"
  exit 1
fi
printf 'all passed\n'
