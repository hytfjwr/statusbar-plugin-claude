# Claude Code StatusBar Plugin

A [StatusBar](https://github.com/hytfjwr/StatusBar) plugin that displays Claude Code rate limit usage as a color-coded icon in the macOS status bar.

- Green: normal usage
- Yellow: warning threshold exceeded
- Red: critical threshold exceeded

Click the icon to see a detailed popup with 5-hour session and 7-day usage breakdowns, plus any
per-model weekly windows the account has (Fable, for example).

<img width="640" height="576" alt="Widget" src="https://github.com/user-attachments/assets/a3e255f3-b266-4a58-9b45-0af400479a6e" />

## Install

In StatusBar preferences → Plugins → Add Plugin:

```
hytfjwr/statusbar-plugin-claude
```

### Requirements

- macOS 26 (Tahoe) or later
- [StatusBar](https://github.com/hytfjwr/StatusBar) installed
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed

### Set up the statusline script

Copy the script that extracts rate limit data from Claude Code:

```bash
cp scripts/statusline.sh ~/.claude/statusline_ratelimit.sh
chmod +x ~/.claude/statusline_ratelimit.sh
```

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

The script needs `jq`, `bc` and `curl` on `PATH`.

### Per-model weekly windows (Fable)

The payload Claude Code hands the statusline script only carries the 5-hour and 7-day windows.
The windows scoped to a single model bucket — `Fable` today — are only served by the claude.ai
usage endpoint, so the script fetches them itself:

- it reads the claude.ai OAuth token from the login keychain (`Claude Code-credentials`), falling
  back to `~/.claude/.credentials.json`
- it snapshots `https://api.anthropic.com/api/oauth/usage` into `~/.claude/rate_limits_usage.json`
  at most once every 5 minutes, in a detached background process
- a failed fetch backs off for a full cycle and leaves the previous snapshot in place

macOS asks once for permission to read the keychain item; grant it and the windows appear in the
popup. Deny it and everything else keeps working — only the per-model cards are missing.

### Build from source

```bash
git clone https://github.com/hytfjwr/statusbar-plugin-claude.git
cd statusbar-plugin-claude
make dev
```

`make dev` builds, bundles, and installs the plugin to `~/.config/statusbar/plugins/`. Requires Swift 6.2 or later.

## Configuration

All settings are configurable from the StatusBar settings panel.

<img width="459" height="646" alt="Settings" src="https://github.com/user-attachments/assets/a8d5a90d-a183-4f3f-8bb5-879a0f3ef0d3" />

| Setting | Default | Description |
|---------|---------|-------------|
| Warning Threshold | 50% | Usage percentage to trigger warning color |
| Critical Threshold | 80% | Usage percentage to trigger critical color |
| Warning Color | Yellow (#FFD60A) | Icon color at warning level |
| Critical Color | Red (#FF453A) | Icon color at critical level |
| Update Interval | 10s | How often to reload data |
| Stale Threshold | 2min | Time after which data is considered stale |
| Bar Display | Icon only | Whether the menu bar shows usage percentages next to the icon |
| Data File Path | `~/.claude/rate_limits.json` | Path to the rate limit JSON file |

## Data file format

The plugin reads a JSON file (default `~/.claude/rate_limits.json`) with the following structure:

```json
{
  "rate_limits": {
    "five_hour": {
      "used_percentage": 42.5,
      "resets_at": "2026-03-20T18:00:00Z"
    },
    "seven_day": {
      "used_percentage": 15.3,
      "resets_at": "2026-03-24T00:00:00Z"
    },
    "model_scoped": [
      {
        "display_name": "Fable",
        "used_percentage": 38,
        "resets_at": "2026-03-24T00:00:00Z"
      }
    ]
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `rate_limits` | object | yes | Top-level wrapper |
| `rate_limits.five_hour` | object | no | 5-hour session window |
| `rate_limits.seven_day` | object | no | 7-day rolling window |
| `rate_limits.model_scoped` | array | no | Weekly windows scoped to a model bucket. Rendered as one card each, in order |
| `model_scoped[].display_name` | string | yes | Label for the bucket, as supplied by the server (e.g. `Fable`). Entries without one are ignored |
| `*.used_percentage` | number | no | Usage percentage (0–100). Defaults to 0 |
| `*.resets_at` | string | no | ISO 8601 timestamp for next reset (e.g. `2026-03-20T18:00:00Z` or `2026-03-20T18:00:00.000Z`) |

If you use a custom data source instead of the bundled statusline script, write this JSON to the path configured in the plugin settings.

## Troubleshooting

### Icon appears gray

The data is stale. Check:

- Claude Code is running
- `~/.claude/settings.json` contains the `statusLine` configuration
- `~/.claude/rate_limits.json` exists and is being updated

```bash
cat ~/.claude/rate_limits.json | jq .
```

### Fable usage is missing from the popup

The per-model cards only appear once the usage snapshot exists:

```bash
jq '.limits[] | select(.kind == "weekly_scoped")' ~/.claude/rate_limits_usage.json
jq '.rate_limits.model_scoped' ~/.claude/rate_limits.json
```

If the snapshot is missing, the token lookup failed. Delete the backoff marker and run the script
by hand to see the keychain prompt:

```bash
rm -f ~/.claude/rate_limits_usage.attempt
echo '{}' | ~/.claude/statusline_ratelimit.sh
```

An account the server emits no model-scoped windows for simply has no such cards.

### Plugin does not load

- Restart StatusBar
- Verify the bundle exists at `~/.config/statusbar/plugins/claudecodeplugin.statusplugin/`
- Ensure the bundle contains both `plugin.dylib` and `manifest.json`

```bash
ls -la ~/.config/statusbar/plugins/claudecodeplugin.statusplugin/
```
