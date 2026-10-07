#!/usr/bin/env bash
# Opens a herdr workspace folder, pane folder, selected path, or clicked file
# link in Zed. herdr passes the invocation context as JSON in
# HERDR_PLUGIN_CONTEXT_JSON; the first argument says which field to use.
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
  "${HERDR_BIN_PATH:-herdr}" notification show "Open in Zed" --body "$1" >/dev/null 2>&1 || true
}

zed_cli() {
  if [ -n "${ZED_CLI:-}" ]; then
    printf '%s' "$ZED_CLI"
  elif command -v zed >/dev/null 2>&1; then
    command -v zed
  elif [ -x /Applications/Zed.app/Contents/MacOS/cli ]; then
    printf '%s' /Applications/Zed.app/Contents/MacOS/cli
  elif [ -x "$HOME/Applications/Zed.app/Contents/MacOS/cli" ]; then
    printf '%s' "$HOME/Applications/Zed.app/Contents/MacOS/cli"
  fi
}

url_decode() {
  local encoded="${1//+/ }"
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
    [ -e "$path" ] && printf '%s' "$path"
    return
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
    echo "usage: open-in-zed.sh workspace|pane|selection|link" >&2
    exit 2
    ;;
esac

if [ -z "$target" ] || [ ! -e "$target" ]; then
  notify "No folder to open."
  exit 0
fi

zed="$(zed_cli)"
if [ -z "$zed" ]; then
  notify "Zed's CLI wasn't found. Install Zed, or set ZED_CLI to its cli path."
  exit 0
fi

if [ -n "$line" ] && [ -f "$target" ]; then
  target="$target:$line${col:+:$col}"
fi

"$zed" "$target"
