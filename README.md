# Open in Editor

A [herdr](https://herdr.dev) plugin that opens file paths your coding agent prints, or the whole workspace, in Zed, VS Code, Cursor, or Sublime Text, at the exact line.

When Claude, Codex, or any other pane prints `src/app.ts:42`, double-click it and press one key. The file opens in your editor at line 42. Another key opens the workspace's folder as a project. There's no picker and nothing to type.

## Install

```bash
herdr plugin install upnorthmedia/herdr-open-in-editor
```

Requires herdr 0.9.0 or later, macOS, and `jq` (included with macOS 15 and later; `brew install jq` on older versions).

## Bind keys

herdr doesn't show plugin actions in its right-click menus yet, so bind the actions to keys in `~/.config/herdr/config.toml`, then run `herdr server reload-config`:

```toml
[[keys.command]]
key = "ctrl+alt+e"
type = "plugin_action"
command = "open-in-editor.open-selection"
description = "Open the selected path in my editor"

[[keys.command]]
key = "ctrl+alt+o"
type = "plugin_action"
command = "open-in-editor.open-workspace"
description = "Open this workspace's folder in my editor"
```

Any free chord works. herdr's docs recommend `ctrl+alt` chords because terminals leave them alone. If you'd rather use `cmd+shift` chords, check that your terminal passes them through. Ghostty, for example, takes `cmd+shift+z` for Redo until you add `keybind = super+shift+z=unbind` to its config.

| Action | What it opens |
| --- | --- |
| `open-in-editor.open-selection` | The selected path, at its line if one is given |
| `open-in-editor.open-workspace` | The focused workspace's folder |
| `open-in-editor.open-pane-folder` | The focused pane's working directory |

## Open a path an agent printed

Double-click or drag-select the path, then press your `open-selection` key. herdr copies selected text to the clipboard (`ui.copy_on_select`, on by default) but doesn't pass the selection to keybound actions, so the plugin reads the path from the clipboard.

It understands the formats agents print:

- `src/app.ts`, `./src/app.ts`, `~/notes.md`, `/abs/path/file.go`
- `src/app.ts:12` and `src/app.ts:12:3` (line and column)
- `src/app.ts#L12` and `src/app.ts#L12-L20`
- Tool-call wrappers such as `Read(src/app.ts)`
- Surrounding quotes, backticks, brackets, and trailing punctuation

Relative paths resolve against the focused pane's directory, then the workspace's.

Ctrl+click on a `file://` link or an editor deep link (`vscode://file/...`, `cursor://file/...`) opens it the same way.

## Choose your editor

With no configuration, the plugin uses the first editor it finds, in this order: Zed, Cursor, VS Code, Sublime Text. If none is installed, it uses the macOS default app for the file. It looks for each editor's command-line tool on `PATH`, then inside the app in `/Applications` or `~/Applications`, so you don't need to install the shell command first.

To pick one, create `editor.conf` in the plugin's config directory:

```bash
cd "$(herdr plugin config-dir open-in-editor)"
echo 'editor = vscode' > editor.conf
```

The setting takes effect on the next keypress.

| `editor =` | Opens with |
| --- | --- |
| `zed` | Zed |
| `vscode` | Visual Studio Code |
| `cursor` | Cursor |
| `sublime` | Sublime Text |
| `default` | The macOS default app for the file type; folders open in Finder; no line numbers |
| `custom` | The command in `editor_command` |

If your editor's command-line tool is somewhere else, point to it:

```ini
editor = vscode
editor_cli = /opt/homebrew/bin/code
```

For any other editor, use a command template. `{path}` is the file or folder, and `{line}` and `{col}` default to 1 when the path has no line. The command runs directly, not through a shell, and quotes group words:

```ini
editor = custom
# IntelliJ IDEA (install its command-line launcher first)
editor_command = idea --line {line} --column {col} {path}
# BBEdit
# editor_command = bbedit +{line} {path}
# An app by name, ignoring the line
# editor_command = open -a "Nova" {path}
```

`editor.conf` is read as plain `key = value` lines and never executed. Lines starting with `#` are comments.

## Debugging

Each run writes the context herdr passed to `$HERDR_PLUGIN_STATE_DIR/last-context.json` (on macOS, usually `~/.local/state/herdr/plugins/open-in-editor/`). `herdr plugin log list --plugin open-in-editor` shows each run's exit code and output. Problems such as a missing editor or a path that doesn't exist appear as a herdr notification.

## Uninstall

```bash
herdr plugin uninstall open-in-editor
```

## Development

```bash
herdr plugin link /path/to/herdr-open-in-editor
bash tests/run.sh                    # uses stub editors, opens nothing
TEST_BASH=/bin/bash bash tests/run.sh  # also check macOS's bash 3.2
```

## License

MIT
