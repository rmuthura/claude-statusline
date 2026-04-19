#!/bin/bash
# Claude Code Statusline Installer

set -e

SCRIPT_URL="https://raw.githubusercontent.com/YOUR_USERNAME/claude-statusline/main/statusline.sh"
INSTALL_PATH="$HOME/.claude/statusline.sh"
SETTINGS_PATH="$HOME/.claude/settings.json"

echo "Installing Claude Code Statusline..."

# Check dependencies
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required. Install with: brew install jq"
    exit 1
fi

# Create .claude directory if needed
mkdir -p "$HOME/.claude"

# Download statusline script
echo "Downloading statusline.sh..."
curl -fsSL "$SCRIPT_URL" -o "$INSTALL_PATH"
chmod +x "$INSTALL_PATH"

# Update settings.json
if [ -f "$SETTINGS_PATH" ]; then
    echo "Updating settings.json..."
    cp "$SETTINGS_PATH" "$SETTINGS_PATH.bak"
    jq '. + {"statusLine": {"type": "command", "command": "'"$INSTALL_PATH"'", "refreshInterval": 2}}' \
      "$SETTINGS_PATH" > /tmp/claude-settings.json && mv /tmp/claude-settings.json "$SETTINGS_PATH"
else
    echo "Creating settings.json..."
    echo '{"statusLine": {"type": "command", "command": "'"$INSTALL_PATH"'", "refreshInterval": 2}}' > "$SETTINGS_PATH"
fi

echo ""
echo "✓ Installed successfully!"
echo ""
echo "Restart Claude Code to see your new statusline."
echo ""
echo "For 5hr/weekly usage limits, log in with Claude.ai:"
echo "  claude logout && claude login"
echo "  Choose 'Claude account with subscription'"
