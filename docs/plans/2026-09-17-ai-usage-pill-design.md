# AI usage pill: design

Date: 2026-09-17. Status: approved.

## Problem

The Claude pill (`omacchiato-claude-usage`) reports Claude only. A user who
also has Codex or Copilot has no pill for those plans. The script also holds
its own copy of the Claude token logic: a keychain read, the OAuth usage
call and a statusline fallback. tokscale 4.17.0 already reads the quota of
each provider through `tokscale usage --json`, and the pill already runs
tokscale for its seven-day stats.

## Scope

In scope: one pill, `omacchiato-ai-usage`, that reads quotas from
`tokscale usage --json`, token stats from `tokscale graph`, and health from
each provider's status page. The first providers are Claude, Codex and
Copilot.

Out of scope: a provider that `tokscale usage` does not report, and a
Settings page for the choice of providers.

Removed:

- The "Extra usage" credits row. tokscale does not report Claude's `spend`
  object.
- The statusline fallback and `bin/omacchiato-claude-statusline`. Without a
  valid token, a provider shows no quota rows.
- The direct call to `api.anthropic.com` and the keychain read in our code.

## Configuration

The command line in `bar-plugins.conf` holds the settings, as it does for
`omacchiato-github-prs`:

```ini
[ai]
command = omacchiato-ai-usage --pill claude --panel claude,codex
interval = 120
icon = 
icon_color = #D97757
```

- `--pill <id>[:<metric>],...`: the providers that the bar label reports,
  and the metric for each one. The default is `claude`.
- `--panel <ids>`: the providers that the popup shows. The default is the
  `--pill` list without the metrics.
- An id is lowercase: `claude`, `codex` or `copilot`. An id that tokscale
  does not return gets one dim row, "No data for <id>".
- A metric is a tokscale metric label, such as `weekly` or `fable`. Case
  does not matter. `5h` also matches Claude's `Session` label. `max` takes
  the metric with the highest `used_percent`.
- With no metric, the pill uses `5h`. If the provider has no 5-hour
  window, it uses `max`. If the named metric is missing, it also uses
  `max`.

Example: `--pill claude,codex:weekly` shows Claude's 5-hour window and
Codex's weekly window.

## What you see

### Label

- For each `--pill` provider, take the metric that `--pill` selects.
- One provider: `23% · 2:25`, the percent and the time until that window
  resets. With the default metric, this is the label of today's pill.
- More than one provider: the logo of each provider in its brand colour,
  then its percent, in `--pill` order. No clock. The script sends these as
  `parts`, a bar plugin key that draws each icon in its own colour. The
  parts replace the configured icon, because one icon cannot name more
  than one provider.
- The colour is the worst colour of the metrics in the label: green under
  50%, yellow under 80%, red above. Today's pill uses the same rule.
- The icon gets the health mark (🏥 minor, 🪦 major) of the worst
  `--pill` provider.

### Popup

For each `--panel` provider, in order:

1. A hero row: the logo in its brand colour, then `Claude`, with the plan
   as its detail. tokscale can return
   more than one Codex account. Each account gets its own section, with the
   account label after the plan.
2. The health row and open incidents, as today.
3. One title row and one slider for each metric, as `window_rows` draws
   them today.

Each provider hero row is a section header (`"section": "closed"`), so the
popup opens as a short list of headers. A click on a header opens or
closes its section.

After the providers:

4. Last 7 days, from `tokscale graph --week -c <panel ids>`, in a closed
   section. One combined block, as today.
5. The "Token usage" row that opens tokscale in a terminal.

## How it works

### Provider table

One table in the script. To add a provider, add one line.

| id | tokscale `provider` | status page | component prefix | default span | glyph |
|---|---|---|---|---|---|
| claude | Claude | https://status.claude.com | `Claude Code` | 7 d | U+EC82 `cod-claude` |
| codex | Codex | https://status.openai.com | `Codex` | 7 d | U+EC81 `cod-openai` |
| copilot | Copilot | https://www.githubstatus.com | `Copilot` | 30 d | U+EC1E `cod-copilot` |

- Match the tokscale `provider` field to the id, ignoring case.
- Health: read `<page>/api/v2/summary.json`. Take each component whose
  name starts with the prefix. The worst status wins.
- status.openai.com returns no `incidents` list, so Codex shows the
  component status only.

### Span for the pace tick

The slider tick needs the length of the window. The metric label gives it:
`Session` and `5h` are 5 h, `Weekly` is 7 d and `30d` is 30 d. Any other
label, such as a Claude model name, uses the default span of the provider.
Without a span, the slider has no tick and the colour comes from the
percent only. `pace_colour` already does this.

### Cache

One file, `~/.config/omacchiato/ai-usage-cache.json`:

- `usage.<id>`: the `tokscale usage --json` entries for each provider.
  One run for all providers every 5 min. If a provider is missing from a
  run, keep its last entries for 15 min more, then drop them.
- `health.<id>`: status and incidents for each provider. Fresh for 5 min.
- `week`: the graph stats, keyed by the `--panel` list. Fresh for 10 min.

`tokscale usage` asks every provider it knows on each run (0.8 s here).
tokscale has no provider filter, so the cache keeps the call count low.

### Token safety

The rule stays: nothing refreshes Claude Code's token. Our code no longer
touches the token. tokscale 4.17.0 reads it and never writes it back (see
the comment at issue #1001 in `crates/tokscale-cli/src/commands/usage/claude.rs`).
Before a raise of `TOKSCALE_VERSION` in `install.sh`, check that this is
still true.

## Migration

`install.sh`:

- Links `bin/omacchiato-ai-usage` into `~/.local/bin`.
- In `~/.config/omacchiato/bar-plugins.conf`, replaces
  `omacchiato-claude-usage` with `omacchiato-ai-usage`. The default
  `--pill claude` gives the label of today's pill. The section name, such
  as `[claude]`, stays.
- Removes the `omacchiato-claude-usage` link, or its copy in a
  TCC-protected clone, and `claude-usage-cache.json`.
- `install.sh` never linked `omacchiato-claude-statusline`. A user whose
  `~/.claude/settings.json` runs it gets a broken statusline, so
  `install.sh` warns when that file names the script.

`uninstall.sh` needs no change: it removes every `omacchiato-*` link.
`migrate-omacosy.sh` runs first and renames `omacosy-claude-usage` to
`omacchiato-claude-usage`, so the step above also moves an omacosy
install.

## Build order

1. `git mv bin/omacchiato-claude-usage bin/omacchiato-ai-usage`. Replace
   `usage_body`, `render_api`, `capture_body`, `render_capture` and
   `access_token` with the tokscale read and a generic renderer.
2. Add the provider table, the argument parser and per-provider health.
3. Delete `bin/omacchiato-claude-statusline`.
4. Migration in `install.sh`, and the tokscale comment and warning there,
   which name the Claude pill.
5. README:
   - "Bar" list: the plugin pills line names an AI usage pill.
   - "Plugin pills": replace the Claude usage bullet. Keep the screenshot
     `docs/screenshots/popup-claude.png` until a new one exists, and
     update its alt text.
   - "Fetched or wired by install.sh": the tokscale row.
   - "Plugins and scripts in this repo": replace the two Claude rows with
     one `omacchiato-ai-usage` row. It talks to tokscale and the status
     pages.
   - Permissions table: the Keychain row. tokscale reads the Claude Code
     token with `security`, and never writes or refreshes it. Without the
     grant, the Claude section shows no quota rows.
   - "What it does not do": the hosts that the pill calls.
   - "Adding pills": the JSON example and the `marker` sentence.
   - Replace "The Claude pill" with "The AI usage pill": the `--pill` and
     `--panel` settings with examples, the default 5-hour metric, health
     per provider, the seven-day stats and the Nerd Font Claude glyph.
     Remove the statusline section.
6. CLAUDE.md: the `omacchiato-claude-usage` note under "Pill scripts".

## Testing

- `python3 bin/omacchiato-ai-usage --pill claude` prints JSON. The label
  and rows match `tokscale usage --json`.
- `--pill claude,codex --panel claude,codex,copilot` gives two percents
  and three sections.
- `--pill claude` shows the `Session` percent. `--pill claude:weekly`
  shows the `Weekly` percent. `--pill claude:nope` and `--pill copilot`
  show the highest percent.
- `--panel nope` gives the "No data for nope" row.
- `HOME=$(mktemp -d)` (no credentials): `tokscale usage --json` prints
  `[]`, and the pill shows `--`.
- Restart the bar, open the popup with `omacchiato-popup claude`, and take a
  screenshot.
- `bash -n install.sh uninstall.sh`.
