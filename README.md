# Claude Code Statusline MAC Only

A custom statusline for Claude Code showing usage limits, context, cost, and git info.

```
Opus 4.5 │ ctx █░░░░ 30% │ in:50k out:10k │ $1.23 │ 5hr ░░░░░ 19% │ wk ░░░░░ 9% │ main*
```

## Features
- **Model name** - Current Claude model
- **Context %** - Context window usage with color-coded bar
- **Tokens** - Input/output token counts
- **Cost** - Session cost in USD
- **5hr limit** - 5-hour rolling usage (Claude.ai Pro/Max only)
- **Weekly limit** - 7-day usage (Claude.ai Pro/Max only)
- **Git branch** - Current branch with dirty indicator

## Requirements
- Claude Code v2.0+
- `jq` - JSON processor (`brew install jq`)
- Claude.ai Pro/Max subscription (for 5hr/weekly limits)

## Installation

### Quick Install
```bash
curl -fsSL https://raw.githubusercontent.com/rmuthura/claude-statusline/main/install.sh | bash
```

### Manual Install
```bash
# Download the script
curl -o ~/.claude/statusline.sh https://raw.githubusercontent.com/rmuthura/claude-statusline/main/statusline.sh
chmod +x ~/.claude/statusline.sh

# Add to settings (backup first)
cp ~/.claude/settings.json ~/.claude/settings.json.bak

# Add statusLine config (requires jq)
jq '. + {"statusLine": {"type": "command", "command": "~/.claude/statusline.sh", "refreshInterval": 2}}' \
  ~/.claude/settings.json > /tmp/settings.json && mv /tmp/settings.json ~/.claude/settings.json
```

## Configuration

The statusline auto-detects:
- **OAuth credentials** from macOS Keychain (for Pro/Max users)
- **API usage** from Claude Code stdin JSON

To get 5hr/weekly limits, log in with your Claude.ai account:
```bash
claude logout
claude login
# Choose "Claude account with subscription"
```


