#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_FILE="$SCRIPT_DIR/hawk-translations.service"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"

echo "Installing Hawk Translations service..."

chmod +x "$SCRIPT_DIR/bin/start-service"
mkdir -p "$SYSTEMD_USER_DIR"
cp "$SERVICE_FILE" "$SYSTEMD_USER_DIR/"
systemctl --user daemon-reload
systemctl --user enable hawk-translations
systemctl --user start hawk-translations

# Allow service to survive after terminal is closed
loginctl enable-linger "$USER"

echo ""
echo "Done. Useful commands:"
echo "  Status:  systemctl --user status hawk-translations"
echo "  Logs:    journalctl --user -u hawk-translations -f"
echo "  Stop:    systemctl --user stop hawk-translations"
echo "  Restart: systemctl --user restart hawk-translations"
