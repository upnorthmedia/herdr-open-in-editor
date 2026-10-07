# Open in Zed (herdr plugin)

Opens herdr workspaces and file paths printed by agents (Claude, Codex, Grok, or any pane) in [Zed](https://zed.dev).

## Use

herdr (through at least 0.9.3) can't add plugin items to its right-click menus: the sidebar and pane menus are hardcoded, and a manifest's `contexts` field isn't used yet. Run the actions with keys instead:

| Key | Action | What it opens |
| --- | --- | --- |
| `cmd+shift+z` | `open-in-zed.open-workspace` | The focused workspace's folder |
| `cmd+shift+e` | `open-in-zed.open-selection` | The selected path, at its line if one is given |

For a file an agent mentioned, double-click or drag-select the path, then press `cmd+shift+e`. herdr doesn't pass the selection to keybound actions, so the script reads it from the clipboard, where herdr copies selected text (`ui.copy_on_select`, on by default). It handles `src/app.ts`, `./a/b.tsx:12`, `/abs/path:12:3`, `path#L12`, `Read(src/x.ts)`, and surrounding quotes, backticks, or punctuation. Relative paths resolve against the pane's directory, then the workspace's.

Ctrl+click on a `file://` link or an editor deep link (`vscode://file/...`, `cursor://file/...`) also opens it in Zed. Agents print plain paths today, not links, so this mostly matters if that changes.

The `contexts` declared in the manifest are kept so the actions show up in herdr's menus if herdr adds plugin menu items later.

## Install

```bash
herdr plugin link ~/Documents/code/herdr-open-in-zed
```

Then add the bindings to `~/.config/herdr/config.toml` and run `herdr server reload-config`:

```toml
[[keys.command]]
key = "cmd+shift+z"
type = "plugin_action"
command = "open-in-zed.open-workspace"
description = "Open this workspace's folder in Zed"

[[keys.command]]
key = "cmd+shift+e"
type = "plugin_action"
command = "open-in-zed.open-selection"
description = "Open the selected path in Zed"
```

In Ghostty, `cmd+shift+z` is Redo by default, so free it for herdr in Ghostty's config, then reload Ghostty (`cmd+shift+,`):

```
keybind = super+shift+z=unbind
```

Remove with `herdr plugin unlink open-in-zed`.

The script finds Zed's CLI on `PATH`, then at `/Applications/Zed.app/Contents/MacOS/cli`. Set `ZED_CLI` to override. Requires `jq` (ships with macOS 15 and later).

## Debugging

Each run writes the context herdr passed to `$HERDR_PLUGIN_STATE_DIR/last-context.json`, and `herdr plugin log list --plugin open-in-zed` shows exit codes and output.
