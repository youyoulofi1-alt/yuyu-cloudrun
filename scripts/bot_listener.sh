#!/usr/bin/env bash
# bot_listener.sh - robust Telegram polling listener
# Polling interval: configurable (default 60s)
# Requirements: BOT_TOKEN, CHAT_ID, jq

set -euo pipefail

BOT_TOKEN=${BOT_TOKEN:-}
AUTHORIZED_CHAT_ID=${CHAT_ID:-}
POLL_INTERVAL=${POLL_INTERVAL:-60}    # seconds between polling cycles
POLL_TIMEOUT=${POLL_TIMEOUT:-60}      # long polling timeout for getUpdates
LAST_ID_FILE=${LAST_ID_FILE:-/var/lib/yuyu_bot/last_update_id}
SERVICE_RESTART_CMD=${SERVICE_RESTART_CMD:-}
ALLOW_REBOOT=${ALLOW_REBOOT:-no}      # set to "yes" to allow reboot

LOG_PREFIX="[bot_listener]"

# minimal sanity checks
if [ -z "$BOT_TOKEN" ] || [ -z "$AUTHORIZED_CHAT_ID" ]; then
  echo "$LOG_PREFIX BOT_TOKEN and CHAT_ID must be set in environment"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "$LOG_PREFIX jq is required but not installed. Install it and retry."
  exit 1
fi

# ensure last id directory exists and is writable
mkdir -p "$(dirname "$LAST_ID_FILE")"
if [ ! -f "$LAST_ID_FILE" ]; then
  echo 0 > "$LAST_ID_FILE"
fi

send_message() {
  local chat="$1"; shift
  local text="$*"
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="${chat}" \
    --data-urlencode "text=${text}" \
    -d "parse_mode=HTML" >/dev/null 2>&1 || true
}

process_update() {
  local upd_json="$1"
  local update_id
  update_id=$(echo "$upd_json" | jq '.update_id')
  local text
  text=$(echo "$upd_json" | jq -r '.message.text // empty' | tr -d '\r')
  local chat_id
  chat_id=$(echo "$upd_json" | jq -r '.message.chat.id | tostring')

  # only process authorized chat
  if [ "$chat_id" != "$AUTHORIZED_CHAT_ID" ]; then
    echo "$LOG_PREFIX ignoring chat $chat_id"
    echo $((update_id + 1)) > "$LAST_ID_FILE"
    return
  fi

  echo "$LOG_PREFIX got command from $chat_id: '$text'"

  # normalize command text and add common aliases
  cmd="${text,,}"
  # strip surrounding spaces
  cmd="$(echo "$cmd" | sed -e 's/^ *//' -e 's/ *$//')"
  # map common typos/aliases
  case "$cmd" in
    "state"|"states") cmd="status" ;;
    "user" ) cmd="users" ;;
  esac

  case "$cmd" in
    "/update"|"update"|"/status"|"status")
      /bin/bash "$(dirname "$0")/status.sh" || true
      ;;
    "/users"|"users")
      # gather IPs from ss and xray access.log (if exists), count occurrences
      CONN_IPS=$(ss -ntu 2>/dev/null | awk '{print $5}' | sed -E 's/\[[^]]+\]://g' | sed -E 's/:.*$//g' | grep -E '^[0-9]+' || true)
      LOG_IPS=$(grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' /var/log/xray/access.log 2>/dev/null || true)
      ALL_IPS=$(printf "%s\n%s\n" "$CONN_IPS" "$LOG_IPS" | sed '/^$/d')
      if [ -z "$ALL_IPS" ]; then
        SEND_TEXT="No active TCP connections on :443"
        send_message "$AUTHORIZED_CHAT_ID" "$SEND_TEXT"
      else
        TOTAL=$(echo "$ALL_IPS" | wc -l | tr -d '[:space:]')
        TOP=$(echo "$ALL_IPS" | sort | uniq -c | sort -nr | awk '{print $2" ("$1")"}' | head -n 30)
        SEND_TEXT="<b>Connections:</b> ${TOTAL}\n<b>Top IPs:</b>\n${TOP}"
        send_message "$AUTHORIZED_CHAT_ID" "$SEND_TEXT"
      fi
      ;;
    "/restart"|"restart")
      if [ -n "$SERVICE_RESTART_CMD" ]; then
        if /bin/bash -c "$SERVICE_RESTART_CMD" >/dev/null 2>&1; then
          send_message "$AUTHORIZED_CHAT_ID" "Restart command executed"
        else
          send_message "$AUTHORIZED_CHAT_ID" "Restart command failed"
        fi
      else
        send_message "$AUTHORIZED_CHAT_ID" "Restart not configured on this host (SERVICE_RESTART_CMD not set)"
      fi
      ;;
    "/reboot"|"reboot")
      if [ "${ALLOW_REBOOT,,}" = "yes" ]; then
        send_message "$AUTHORIZED_CHAT_ID" "Rebooting server now..."
        (sleep 1; /sbin/shutdown -r now) >/dev/null 2>&1 &
      else
        send_message "$AUTHORIZED_CHAT_ID" "Reboot is disabled on this host (set ALLOW_REBOOT=yes to enable)"
      fi
      ;;
    "/info"|"info")
      IP=$(curl -s --max-time 5 https://ifconfig.me || echo "unknown")
      UPTIME=$(uptime -p 2>/dev/null || echo "unknown")
      send_message "$AUTHORIZED_CHAT_ID" "<b>Info</b>\nIP: ${IP}\nUptime: ${UPTIME}"
      ;;
    "/help"|"help")
      HELP_TXT="Available commands:\n- update / status: send server status\n- users: list active connections\n- info: basic info (IP, uptime)\n- restart: restart configured service (if set)\n- reboot: reboot server (if enabled)\n\nYou can also use the keyboard buttons for quick actions."
      send_message "$AUTHORIZED_CHAT_ID" "$HELP_TXT"
      # send a quick reply keyboard
      REPLY_KEYS='{"keyboard":[["update","info","users"]],"one_time_keyboard":true,"resize_keyboard":true}'
      curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d chat_id="${AUTHORIZED_CHAT_ID}" --data-urlencode "text=Choose an action:" --data-urlencode "reply_markup=${REPLY_KEYS}" >/dev/null 2>&1 || true
      ;;
    "/menu"|"menu")
      REPLY_KEYS='{"keyboard":[["update","info","users"]],"one_time_keyboard":true,"resize_keyboard":true}'
      curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d chat_id="${AUTHORIZED_CHAT_ID}" --data-urlencode "text=Menu:" --data-urlencode "reply_markup=${REPLY_KEYS}" >/dev/null 2>&1 || true
      ;;
    *)
      send_message "$AUTHORIZED_CHAT_ID" "Unknown command: ${text}\nAvailable: update, users, info, restart, reboot, help"
      ;;
  esac

  # advance offset
  echo $((update_id + 1)) > "$LAST_ID_FILE"
}

main_loop() {
  echo "$LOG_PREFIX starting polling loop (interval=${POLL_INTERVAL}s, timeout=${POLL_TIMEOUT}s)"
  while true; do
    OFFSET=$(cat "$LAST_ID_FILE" 2>/dev/null || echo 0)
    RESP=$(curl -s --max-time $((POLL_TIMEOUT+5)) "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates?timeout=${POLL_TIMEOUT}&offset=${OFFSET}")

    # safe check for json
    if ! echo "$RESP" | jq -e . >/dev/null 2>&1; then
      echo "$LOG_PREFIX invalid response from Telegram, sleeping ${POLL_INTERVAL}s"
      sleep "$POLL_INTERVAL"
      continue
    fi

    count=$(echo "$RESP" | jq '.result | length')
    if [ "$count" -gt 0 ]; then
      echo "$LOG_PREFIX received $count updates"
      echo "$RESP" | jq -c '.result[]' | while read -r upd; do
        process_update "$upd"
      done
    fi

    sleep "$POLL_INTERVAL"
  done
}

# run
main_loop
