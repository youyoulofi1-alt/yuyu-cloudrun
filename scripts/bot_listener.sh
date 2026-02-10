#!/bin/bash
# bot_listener.sh - poll Telegram getUpdates and react to commands
# Requires: BOT_TOKEN, CHAT_ID (authorized chat id), optional SERVICE_RESTART_CMD

set -eu

BOT_TOKEN=${BOT_TOKEN:-}
AUTHORIZED_CHAT_ID=${CHAT_ID:-}
LAST_ID_FILE=${LAST_ID_FILE:-/var/tmp/yuyu_bot_last_id}
POLL_TIMEOUT=${POLL_TIMEOUT:-30}
SERVICE_RESTART_CMD=${SERVICE_RESTART_CMD:-}

if [ -z "$BOT_TOKEN" ] || [ -z "$AUTHORIZED_CHAT_ID" ]; then
  echo "BOT_TOKEN and CHAT_ID must be set in environment"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required but not installed. Install it (apt/yum) and retry."
  exit 1
fi

# Ensure last id file exists
mkdir -p "$(dirname "$LAST_ID_FILE")"
if [ ! -f "$LAST_ID_FILE" ]; then
  echo 0 > "$LAST_ID_FILE"
fi

echo "[bot_listener] starting loop (poll timeout ${POLL_TIMEOUT}s)"
while true; do
  OFFSET=$(cat "$LAST_ID_FILE" 2>/dev/null || echo 0)
  RESP=$(curl -s --max-time $((POLL_TIMEOUT+5)) "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates?timeout=${POLL_TIMEOUT}&offset=${OFFSET}")

  has=$(echo "$RESP" | jq '.result | length')
  if [ "$has" = "0" ]; then
    continue
  fi

  # iterate updates
  echo "$RESP" | jq -c '.result[]' | while read -r upd; do
    update_id=$(echo "$upd" | jq '.update_id')
    text=$(echo "$upd" | jq -r '.message.text // empty' | tr -d '\r')
    chat_id=$(echo "$upd" | jq -r '.message.chat.id | tostring')

    # ignore if from other chat
    if [ "$chat_id" != "${AUTHORIZED_CHAT_ID}" ]; then
      echo "[bot_listener] ignoring chat $chat_id"
      # still update offset
      echo $((update_id+1)) > "$LAST_ID_FILE"
      continue
    fi

    echo "[bot_listener] got command from $chat_id: '$text'"

    case "${text,,}" in
      "/update"|"update"|"/status"|"status")
        /bin/bash "$(dirname "$0")/status.sh" || true
        ;;
      "/users"|"users")
        # Provide a short users list
        USERS=$(ss -ntu | grep ":443" || true)
        if [ -z "$USERS" ]; then
          SEND_TEXT="No active TCP connections on :443"
        else
          SEND_TEXT="Active connections on :443:\n$(echo "$USERS" | head -n 20)"
        fi
        curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d chat_id="${AUTHORIZED_CHAT_ID}" --data-urlencode "text=${SEND_TEXT}" >/dev/null 2>&1 || true
        ;;
      "/restart"|"restart")
        if [ -n "$SERVICE_RESTART_CMD" ]; then
          /bin/bash -c "$SERVICE_RESTART_CMD" >/dev/null 2>&1 && RESULT="Restart executed" || RESULT="Restart failed"
        else
          RESULT="No SERVICE_RESTART_CMD defined"
        fi
        curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d chat_id="${AUTHORIZED_CHAT_ID}" --data-urlencode "text=${RESULT}" >/dev/null 2>&1 || true
        ;;
      "/reboot"|"reboot")
        # Reboot the server (requires proper privileges)
        (sleep 1; /sbin/shutdown -r now) >/dev/null 2>&1 &
        curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d chat_id="${AUTHORIZED_CHAT_ID}" --data-urlencode "text=Rebooting server..." >/dev/null 2>&1 || true
        ;;
      *)
        # unknown command
        curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d chat_id="${AUTHORIZED_CHAT_ID}" --data-urlencode "text=Unknown command: ${text}\nAvailable: update, users, restart, reboot" >/dev/null 2>&1 || true
        ;;
    esac

    echo $((update_id+1)) > "$LAST_ID_FILE"
  done

  # short sleep to avoid tight loop on some errors
  sleep 1
done
