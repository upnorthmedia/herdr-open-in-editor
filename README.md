# Open in Zed (herdr plugin)

Opens herdr workspaces, pane folders, and file paths printed by agents (Claude, Codex, Grok, or any pane) in [Zed](https://zed.dev).

## Use

- **Project folder:** right-click a workspace in the sidebar, choose **Open in Zed**.
- **Pane folder:** right-click a pane, choose **Open folder in Zed**. Opens the directory the pane's shell or agent is in.
- **A file an agent mentioned:** double-click or drag-select the path, right-click, choose **Open in Zed**. Handles `src/app.ts`, `./a/b.tsx:12`, `/abs/path:12:3`, `path#L12`, `Read(src/x.ts)`, and surrounding quotes, backticks, or punctuation. Relative paths resolve against the pane's directory, then the workspace's.
- **File links:** Ctrl+click a `file://` link, or an editor deep link (`vscode://file/...`, `cursor://file/...`), and it opens in Zed instead.

## Why selecting a path takes two steps

herdr link handlers only fire on URLs, not on plain text, and agents print file paths as plain text (no OSC 8 hyperlinks). Selecting the path and using the selection menu is the closest herdr's plugin API allows. If an agent starts emitting `file://` or `vscode://file/` links, Ctrl+click opens them directly.

## Install

```bash
herdr plugin link ~/Documents/code/herdr-open-in-zed
```

Remove with `herdr plugin unlink open-in-zed`.

The script finds Zed's CLI on `PATH`, then at `/Applications/Zed.app/Contents/MacOS/cli`. Set `ZED_CLI` to override. Requires `jq` (ships with macOS 15 and later).

To bind a key instead of using a menu, invoke an action by id, for example `herdr plugin action invoke open-workspace --plugin open-in-zed`.
