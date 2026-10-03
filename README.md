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

Claude Code runs the script for every open session, and each passes the figures from its own last
request, so an idle session carries old numbers. The script therefore takes the 5-hour, 7-day and
per-model windows from the claude.ai usage endpoint, which is account-wide, and writes
`~/.claude/rate_limits.json` from that snapshot once a minute.

The script needs `jq`, `bc` and `curl` on `PATH`.

### Usage snapshot

The payload Claude Code hands the statusline script describes only that session, and carries no
per-model windows at all. The script therefore reads the claude.ai usage endpoint itself:

- it reads the claude.ai OAuth token from the login keychain (`Claude Code-credentials`), falling
  back to `~/.claude/.credentials.json`
- it snapshots `https://api.anthropic.com/api/oauth/usage` into `~/.claude/rate_limits_usage.json`
  at most once a minute, in a detached background process, and writes `~/.claude/rate_limits.json`
  from it with `fetched_at` set to the fetch time
- a failed fetch backs off for a full cycle and leaves both files in place, so the plugin marks the
  data stale once it ages past the Stale Threshold

macOS asks once for permission to read the keychain item; grant it. Deny it and the script falls
back to the payload of whichever session rendered last: the 5-hour and 7-day numbers can jump
between sessions, and the per-model cards are missing.

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

Toast notifications fire when session (5h) usage crosses the warning or critical threshold, at most
once per level for each 5-hour window. A stale reading never toasts.

## Data file format

The plugin reads a JSON file (default `~/.claude/rate_limits.json`) with the following structure:

```json
{
  "rate_limits": {
    "fetched_at": "2026-03-20T14:05:00Z",
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
| `rate_limits.fetched_at` | string | no | ISO 8601 time the numbers were observed. The stale check measures from it; when absent, the file's modification time is used |
| `rate_limits.five_hour` | object | no | 5-hour session window |
| `rate_limits.seven_day` | object | no | 7-day rolling window |
| `rate_limits.model_scoped` | array | no | Weekly windows scoped to a model bucket. Rendered as one card each, in order |
| `model_scoped[].display_name` | string | yes | Label for the bucket, as supplied by the server (e.g. `Fable`). Entries without one are ignored |
| `*.used_percentage` | number | no | Usage percentage (0–100). A window or entry without it is treated as unknown |
| `*.resets_at` | string | no | ISO 8601 timestamp for next reset (e.g. `2026-03-20T18:00:00Z` or `2026-03-20T18:00:00.000Z`) |

A window that is missing, `null`, lacks `used_percentage`, or whose `resets_at` has already passed is
shown as unknown (`—`, gray) rather than as 0%.

If you use a custom data source instead of the bundled statusline script, write this JSON to the path configured in the plugin settings.

## Troubleshooting

### Icon appears gray

The data is stale, or the 5-hour window is unknown. Check:

- Claude Code is running
- `~/.claude/settings.json` contains the `statusLine` configuration
- `~/.claude/rate_limits.json` exists and is being updated

```bash
cat ~/.claude/rate_limits.json | jq .
```

### Numbers jump between values

The script is running without a usage snapshot and falling back to each session's payload. Check
that the snapshot exists and is recent:

```bash
ls -l ~/.claude/rate_limits_usage.json
jq '.rate_limits.fetched_at' ~/.claude/rate_limits.json
```

If it is missing, see the next section.

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
