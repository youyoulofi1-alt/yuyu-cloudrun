#!/usr/bin/env bash
set -euo pipefail

# scripts/install_bot.sh - install Telegram bot listener as systemd service
# Usage: sudo ./install_bot.sh

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)"
  exit 1
fi

INSTALL_PATH=/usr/local/bin
SERVICE_FILE=/etc/systemd/system/bot-listener.service
ENV_FILE=/etc/default/yuyu_bot

echo "Copying scripts to ${INSTALL_PATH}..."
cp -v scripts/status.sh scripts/bot_listener.sh "${INSTALL_PATH}/"
chmod +x "${INSTALL_PATH}/status.sh" "${INSTALL_PATH}/bot_listener.sh"

# Backup existing env file if exists
if [ -f "${ENV_FILE}" ]; then
  echo "Backing up existing ${ENV_FILE} to ${ENV_FILE}.bak"
  cp -a "${ENV_FILE}" "${ENV_FILE}.bak"
fi

# Prompt for BOT_TOKEN and CHAT_ID
read -rp "Enter BOT_TOKEN: " BOT_TOKEN_INPUT
read -rp "Enter CHAT_ID: " CHAT_ID_INPUT
read -rp "Optional SERVICE_RESTART_CMD (or leave empty): " SERVICE_RESTART_CMD_INPUT

cat > "${ENV_FILE}" <<EOF
# /etc/default/yuyu_bot - environment for bot-listener
BOT_TOKEN="${BOT_TOKEN_INPUT}"
CHAT_ID="${CHAT_ID_INPUT}"
SERVICE_RESTART_CMD="${SERVICE_RESTART_CMD_INPUT}"
EOF

chmod 600 "${ENV_FILE}"

# Install jq if missing
if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found, attempting to install..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update && apt-get install -y jq
  elif command -v yum >/dev/null 2>&1; then
    yum install -y epel-release && yum install -y jq
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache jq
  else
    echo "Package manager not detected. Please install 'jq' manually and re-run."
    exit 1
  fi
fi

# Install systemd service
echo "Installing systemd service..."
cp -v systemd/bot-listener.service "${SERVICE_FILE}"

systemctl daemon-reload
systemctl enable --now bot-listener.service

echo "\nInstallation complete."
echo "Check service status: systemctl status bot-listener.service" 

echo "To test manually, run:\n sudo BOT_TOKEN=... CHAT_ID=... /usr/local/bin/status.sh" 

echo "Logs: journalctl -u bot-listener.service -f"

exit 0
