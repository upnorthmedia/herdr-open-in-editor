#!/usr/bin/env bash
# Opens a herdr workspace folder, pane folder, selected path, or clicked file
# link in the editor chosen in editor.conf. herdr passes the invocation context
# as JSON in HERDR_PLUGIN_CONTEXT_JSON; the first argument says which field to
# use.
set -euo pipefail

mode="${1:-}"
context="${HERDR_PLUGIN_CONTEXT_JSON:-}"
[ -n "$context" ] || context="{}"

# Keep the last invocation's context for debugging what herdr passed.
if [ -n "${HERDR_PLUGIN_STATE_DIR:-}" ]; then
  mkdir -p "$HERDR_PLUGIN_STATE_DIR"
  printf '%s\n' "$context" >"$HERDR_PLUGIN_STATE_DIR/last-context.json" 2>/dev/null || true
fi

field() {
  printf '%s' "$context" | jq -r --arg key "$1" '.[$key] // empty'
}

notify() {
  "${HERDR_BIN_PATH:-herdr}" notification show "Open in Editor" --body "$1" >/dev/null 2>&1 || true
}

config_file="${HERDR_PLUGIN_CONFIG_DIR:-}/editor.conf"

# Reads one "key = value" setting from editor.conf. The file is parsed rather
# than sourced, so it can't run code. The last matching line wins.
config() {
  [ -f "$config_file" ] || return 0
  awk -v key="$1" '
    /^[[:space:]]*(#|$)/ { next }
    {
      i = index($0, "=")
      if (!i) next
      k = substr($0, 1, i - 1)
      v = substr($0, i + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      if (k == key) val = v
    }
    END { print val }
  ' "$config_file"
}

# Single-value settings may be written with quotes: editor = "vscode".
unquote() {
  local value="$1"
  if [[ "$value" =~ ^\"(.*)\"$ || "$value" =~ ^\'(.*)\'$ ]]; then
    value="${BASH_REMATCH[1]}"
  fi
  printf '%s' "$value"
}

editor_label() {
  case "$1" in
    zed) printf 'Zed' ;;
    vscode) printf 'VS Code' ;;
    cursor) printf 'Cursor' ;;
    sublime) printf 'Sublime Text' ;;
  esac
}

# Finds an editor's command-line tool on PATH, then inside its app bundle in
# /Applications or ~/Applications, since the bundled CLIs work without the
# "install shell command" step.
find_cli() {
  local name bundle dir
  case "$1" in
    zed) name=zed bundle="Zed.app/Contents/MacOS/cli" ;;
    vscode) name=code bundle="Visual Studio Code.app/Contents/Resources/app/bin/code" ;;
    cursor) name=cursor bundle="Cursor.app/Contents/Resources/app/bin/cursor" ;;
    sublime) name=subl bundle="Sublime Text.app/Contents/SharedSupport/bin/subl" ;;
    *) return 0 ;;
  esac
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi
  for dir in /Applications "$HOME/Applications"; do
    if [ -x "$dir/$bundle" ]; then
      printf '%s' "$dir/$bundle"
      return 0
    fi
  done
}

# Replaces every occurrence of $2 in $1 with $3, without bash's pattern
# substitution, which treats "&" in the replacement specially in bash 5.2.
replace_all() {
  local text="$1" from="$2" to="$3" out=""
  while [[ "$text" == *"$from"* ]]; do
    out="$out${text%%"$from"*}$to"
    text="${text#*"$from"}"
  done
  printf '%s' "$out$text"
}

# Percent-decodes a URL path. "+" stays literal (it only means space in form
# data), and backslashes are escaped so printf %b decodes nothing else.
url_decode() {
  local encoded="${1//\\/\\\\}"
  printf '%b' "${encoded//%/\\x}"
}

# Turns agent output like `Read(src/app.ts)`, "./a/b.tsx:12:3,", or
# src/x.ts#L40 into "path line col" (line and col may be empty).
parse_target() {
  local text="$1" line="" col=""

  # First non-empty line, trimmed.
  text="$(printf '%s\n' "$text" | awk 'NF { print; exit }')"
  text="$(printf '%s' "$text" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"

  # Tool-call wrappers such as Read(path) or Edit(path).
  if [[ "$text" =~ ^[A-Za-z]+\((.*)\)$ ]]; then
    text="${BASH_REMATCH[1]}"
  fi

  # Surrounding quotes, backticks, brackets, and trailing punctuation.
  text="$(printf '%s' "$text" | sed -E 's/^[[`"'"'"'(<]+//; s/[]`"'"'"')>,;.]+$//')"

  case "$text" in
    file://localhost/*) text="$(url_decode "${text#file://localhost}")" ;;
    file://*) text="$(url_decode "${text#file://}")" ;;
  esac

  if [[ "$text" =~ ^(.+)#L([0-9]+)(-L?[0-9]+)?$ ]]; then
    text="${BASH_REMATCH[1]}"
    line="${BASH_REMATCH[2]}"
  elif [[ "$text" =~ ^(.+):([0-9]+):([0-9]+)$ ]]; then
    text="${BASH_REMATCH[1]}"
    line="${BASH_REMATCH[2]}"
    col="${BASH_REMATCH[3]}"
  elif [[ "$text" =~ ^(.+):([0-9]+)$ ]]; then
    text="${BASH_REMATCH[1]}"
    line="${BASH_REMATCH[2]}"
  fi

  # shellcheck disable=SC2088 # matches a literal "~/" in order to expand it
  case "$text" in
    "~") text="$HOME" ;;
    "~/"*) text="$HOME/${text#\~/}" ;;
  esac

  printf '%s\n%s\n%s\n' "$text" "$line" "$col"
}

# Relative paths resolve against the pane's directory first, then the
# workspace's, so paths an agent prints relative to its repo still open.
resolve_path() {
  local path="$1" base
  if [[ "$path" == /* ]]; then
    if [ -e "$path" ]; then
      printf '%s' "$path"
    fi
    return 0
  fi
  for base in "$(field focused_pane_cwd)" "$(field workspace_cwd)"; do
    if [ -n "$base" ] && [ -e "$base/$path" ]; then
      printf '%s' "$base/${path#./}"
      return
    fi
  done
}

target=""
line=""
col=""

case "$mode" in
  workspace)
    target="$(field workspace_cwd)"
    ;;
  pane)
    target="$(field focused_pane_cwd)"
    [ -n "$target" ] || target="$(field workspace_cwd)"
    ;;
  selection | link)
    if [ "$mode" = selection ]; then
      raw="$(field selected_text)"
      # Keybindings don't receive the selection, but herdr copies selected
      # text to the clipboard (ui.copy_on_select, on by default).
      if [ -z "$raw" ] && command -v pbpaste >/dev/null 2>&1; then
        raw="$(pbpaste 2>/dev/null | head -c 4096)"
      fi
    else
      raw="${HERDR_PLUGIN_CLICKED_URL:-$(field clicked_url)}"
      # Editor deep links: vscode://file/<abs path>[:line[:col]]
      if [[ "$raw" =~ ^[a-z-]+://file(/.*)$ ]]; then
        raw="$(url_decode "${BASH_REMATCH[1]}")"
      fi
    fi
    if [ -z "$raw" ]; then
      notify "Nothing selected."
      exit 0
    fi
    parsed="$(parse_target "$raw")"
    path="$(printf '%s\n' "$parsed" | sed -n 1p)"
    line="$(printf '%s\n' "$parsed" | sed -n 2p)"
    col="$(printf '%s\n' "$parsed" | sed -n 3p)"
    target="$(resolve_path "$path")"
    if [ -z "$target" ]; then
      notify "No file or folder found for: $path"
      exit 0
    fi
    ;;
  *)
    echo "usage: open-in-editor.sh workspace|pane|selection|link" >&2
    exit 2
    ;;
esac

if [ -z "$target" ] || [ ! -e "$target" ]; then
  notify "No folder to open."
  exit 0
fi

# Line numbers only make sense for files.
if [ ! -f "$target" ]; then
  line=""
  col=""
fi

editor="$(unquote "$(config editor)")"
if [ -z "$editor" ] || [ "$editor" = auto ]; then
  editor=default
  for candidate in zed cursor vscode sublime; do
    if [ -n "$(find_cli "$candidate")" ]; then
      editor="$candidate"
      break
    fi
  done
fi

case "$editor" in
  zed | vscode | cursor | sublime)
    cli="$(unquote "$(config editor_cli)")"
    [ -n "$cli" ] || cli="$(find_cli "$editor")"
    if [ -z "$cli" ] || [ ! -x "$cli" ]; then
      notify "Couldn't find $(editor_label "$editor")'s command-line tool. Install $(editor_label "$editor"), or set editor_cli in $config_file."
      exit 0
    fi
    location="$target${line:+:$line${col:+:$col}}"
    # VS Code and Cursor read a :line:col suffix only with --goto.
    if [ -n "$line" ] && { [ "$editor" = vscode ] || [ "$editor" = cursor ]; }; then
      "$cli" --goto "$location"
    else
      "$cli" "$location"
    fi
    ;;
  default)
    # The app macOS associates with the file type; folders open in Finder.
    open "$target"
    ;;
  custom)
    template="$(config editor_command)"
    if [ -z "$template" ]; then
      notify "editor = custom needs an editor_command in $config_file."
      exit 0
    fi
    # xargs splits the template into words, honoring quotes, without running
    # it through a shell.
    if ! words="$(printf '%s\n' "$template" | xargs -n 1 printf '%s\n' 2>/dev/null)"; then
      notify "Couldn't parse editor_command in $config_file. Check its quotes."
      exit 0
    fi
    argv=()
    while IFS= read -r word; do
      word="$(replace_all "$word" "{path}" "$target")"
      word="$(replace_all "$word" "{line}" "${line:-1}")"
      word="$(replace_all "$word" "{col}" "${col:-1}")"
      argv+=("$word")
    done <<<"$words"
    "${argv[@]}"
    ;;
  *)
    notify "Unknown editor \"$editor\" in $config_file. Use zed, vscode, cursor, sublime, default, or custom."
    exit 0
    ;;
esac
