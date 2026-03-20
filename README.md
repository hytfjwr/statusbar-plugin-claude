# Claude Code StatusBar Plugin

A [StatusBar](https://github.com/hytfjwr/StatusBar) plugin that displays Claude Code rate limit usage as a color-coded icon in the macOS status bar.

- Green: normal usage
- Yellow: warning threshold exceeded
- Red: critical threshold exceeded

Click the icon to see a detailed popup with 5-hour session and 7-day usage breakdowns.

## Requirements

- macOS 26 (Tahoe) or later
- Swift 6.2 or later
- [StatusBar](https://github.com/hytfjwr/StatusBar) installed
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed

## Installation

### 1. Set up the statusline script

Copy the script that extracts rate limit data from Claude Code:

```bash
cp scripts/statusline.sh ~/.claude/statusline_ratelimit.sh
chmod +x ~/.claude/statusline_ratelimit.sh
```

### 2. Configure Claude Code

Add the statusLine configuration to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline_ratelimit.sh"
  }
}
```

This causes Claude Code to periodically write rate limit data to `~/.claude/rate_limits.json`.

### 3. Build and install the plugin

```bash
git clone https://github.com/hytfjwr/statusbar-plugin-claude.git
cd statusbar-plugin-claude

# Build, bundle, and install in one step
make dev
```

`make dev` performs the following:

1. Release build (`swift build -c release`)
2. Creates a `.statusplugin` bundle
3. Copies it to `~/.config/statusbar/plugins/`

Restart StatusBar to load the plugin.

### Manual installation

Run individual steps if needed:

```bash
# Build only
make build

# Create bundle
make bundle

# Create distributable ZIP
make package
```

The ZIP is generated at `.build/release/claudecodeplugin.statusplugin.zip`. Extract it manually:

```bash
mkdir -p ~/.config/statusbar/plugins
unzip .build/release/claudecodeplugin.statusplugin.zip -d ~/.config/statusbar/plugins/
```

## Configuration

All settings are configurable from the StatusBar settings panel.

| Setting | Default | Description |
|---------|---------|-------------|
| Warning Threshold | 50% | Usage percentage to trigger warning color |
| Critical Threshold | 80% | Usage percentage to trigger critical color |
| Warning Color | Yellow (#FFD60A) | Icon color at warning level |
| Critical Color | Red (#FF453A) | Icon color at critical level |
| Update Interval | 10s | How often to reload data |
| Stale Threshold | 2min | Time after which data is considered stale |
| Data File Path | `~/.claude/rate_limits.json` | Path to the rate limit JSON file |

## Troubleshooting

### Icon appears gray

The data is stale. Check:

- Claude Code is running
- `~/.claude/settings.json` contains the `statusLine` configuration
- `~/.claude/rate_limits.json` exists and is being updated

```bash
cat ~/.claude/rate_limits.json | jq .
```

### Plugin does not load

- Restart StatusBar
- Verify the bundle exists at `~/.config/statusbar/plugins/claudecodeplugin.statusplugin/`
- Ensure the bundle contains both `plugin.dylib` and `manifest.json`

```bash
ls -la ~/.config/statusbar/plugins/claudecodeplugin.statusplugin/
```
