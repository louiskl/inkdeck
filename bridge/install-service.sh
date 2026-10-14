#!/bin/sh
# Install the (optional) InkDeck bridge as a systemd service on a Linux box
# (Raspberry Pi, thin client, home server). Run as the user that did "setup":
#
#   python3 inkdeck_bridge.py setup      # once, connects Spotify
#   sh install-service.sh                # starts now and on every boot
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3)"
USER_NAME="$(id -un)"
UNIT=/etc/systemd/system/inkdeck-bridge.service

echo "Installing InkDeck bridge service for user '$USER_NAME' from $DIR"
sudo tee "$UNIT" >/dev/null <<EOF
[Unit]
Description=InkDeck bridge (optional data helper for InkDeck e-ink dashboards)
After=network-online.target
Wants=network-online.target

[Service]
User=$USER_NAME
WorkingDirectory=$DIR
ExecStart=$PY $DIR/inkdeck_bridge.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now inkdeck-bridge
sleep 1
systemctl --no-pager status inkdeck-bridge | head -n 5
echo
echo "Done. Logs: journalctl -u inkdeck-bridge -f"
