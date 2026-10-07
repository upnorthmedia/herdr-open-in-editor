#!/usr/bin/env bash
# Runs the plugin script against fixture files with stub editor CLIs and a
# stub herdr binary, then checks the argv the editor received.
# Usage: bash tests/run.sh  (TEST_BASH=/bin/bash checks macOS bash 3.2)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
script="$root/bin/open-in-editor.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/repo/src" "$tmp/state" "$tmp/config" "$tmp/bin" "$tmp/path"
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
# Stand-ins for editor CLIs and macOS open, found through PATH.
for name in zed open; do
  cp "$tmp/bin/editor" "$tmp/path/$name"
done
chmod +x "$tmp/bin/editor" "$tmp/bin/herdr" "$tmp/path/"*

# configure LINE... : writes editor.conf
configure() {
  printf '%s\n' "$@" >"$tmp/config/editor.conf"
}

failures=0

# run MODE CONTEXT_JSON [clicked_url]
run() {
  rm -f "$tmp/editor.args" "$tmp/notify.args" "$tmp/exit"
  HERDR_PLUGIN_CONTEXT_JSON="$2" \
    HERDR_PLUGIN_CLICKED_URL="${3:-}" \
    HERDR_PLUGIN_STATE_DIR="$tmp/state" \
    HERDR_PLUGIN_CONFIG_DIR="$tmp/config" \
    HERDR_BIN_PATH="$tmp/bin/herdr" \
    PATH="$tmp/path:$PATH" \
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

configure "editor = zed" "editor_cli = $tmp/bin/editor"

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

# shellcheck disable=SC2016 # the backticks are part of the selected text
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
expect "missing relative path notifies" "<editor not run: notification show Open in Editor --body No file or folder found for: src/missing.ts>"

run selection "$(ctx '/nonexistent/file.ts')"
expect "missing absolute path notifies" "<editor not run: notification show Open in Editor --body No file or folder found for: /nonexistent/file.ts>"

# Editor presets.

configure "editor = vscode" "editor_cli = $tmp/bin/editor"
run selection "$(ctx 'src/app.ts:12:3')"
expect "vscode uses --goto for a line" "--goto
$repo/src/app.ts:12:3"
run workspace "$(ctx)"
expect "vscode opens a folder without --goto" "$repo"

configure 'editor = "cursor"' "editor_cli = '$tmp/bin/editor'"
run selection "$(ctx 'src/app.ts:5')"
expect "cursor with quoted settings" "--goto
$repo/src/app.ts:5"

configure "editor = sublime" "editor_cli = $tmp/bin/editor"
run selection "$(ctx 'src/app.ts:5')"
expect "sublime takes a :line suffix" "$repo/src/app.ts:5"

configure "editor = zed" "editor_cli = $tmp/bin/editor"
run workspace "$(ctx)"
run selection "$(ctx 'src:5')"
expect "a folder drops the line" "$repo/src"

configure "editor = default"
run selection "$(ctx 'src/app.ts:5')"
expect "default opens the file with open, without the line" "$repo/src/app.ts"

configure "editor = custom" "editor_command = $tmp/bin/editor --line {line} \"{path}\""
run selection "$(ctx 'src/with space.ts:8')"
expect "custom command template" "--line
8
$repo/src/with space.ts"
run workspace "$(ctx)"
expect "custom command defaults the line to 1" "--line
1
$repo"

configure "editor = custom"
run workspace "$(ctx)"
expect "custom without a command notifies" "<editor not run: notification show Open in Editor --body editor = custom needs an editor_command in $tmp/config/editor.conf.>"

configure "editor = notepad"
run workspace "$(ctx)"
expect "unknown editor notifies" "<editor not run: notification show Open in Editor --body Unknown editor \"notepad\" in $tmp/config/editor.conf. Use zed, vscode, cursor, sublime, default, or custom.>"

configure "editor = vscode" "editor_cli = $tmp/missing"
run workspace "$(ctx)"
expect "missing editor CLI notifies" "<editor not run: notification show Open in Editor --body Couldn't find VS Code's command-line tool. Install VS Code, or set editor_cli in $tmp/config/editor.conf.>"

# With no editor set, the first editor found wins; the stub zed on PATH is
# found before any installed app.
configure "# editor = vscode"
run workspace "$(ctx)"
expect "auto-detects an editor when none is set" "$repo"

if [ "$failures" -gt 0 ]; then
  printf '%d failed\n' "$failures"
  exit 1
fi
printf 'all passed\n'
