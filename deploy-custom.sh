#!/usr/bin/env bash
set -euo pipefail

# Flexible deployment script for Xray Cloud Run
# All parameters are optional and can be customized

echo "=========================================="
echo "  XRAY Cloud Run - Custom Deployment"
echo "=========================================="

# Detect interactive mode
if [ -t 0 ] && [ -t 1 ]; then
  INTERACTIVE=true
else
  INTERACTIVE=false
fi

# -------- Preset Configurations --------
declare -A PRESETS=(
  [production]="memory=2048|cpu=1|instances=16|concurrency=1000|timeout=3600"
  [budget]="memory=2048|cpu=2|instances=8|concurrency=1000|timeout=3600"
)

apply_preset() {
  local preset=$1
  if [[ -v PRESETS[$preset] ]]; then
    local config="${PRESETS[$preset]}"
    IFS='|' read -ra settings <<< "$config"
    for setting in "${settings[@]}"; do
      IFS='=' read -r key value <<< "$setting"
      case "$key" in
        memory) MEMORY="$value" ;;
        cpu) CPU="$value" ;;
        instances) MAX_INSTANCES="$value" ;;
        concurrency) CONCURRENCY="$value" ;;
        timeout) TIMEOUT="$value" ;;
      esac
    done
  fi
}

# Show a short list of suggested regions (user will pick by index)
SUGGESTED_REGIONS=(
  us-central1
  us-east1
  us-west1
  europe-west1
  europe-west4
  asia-northeast1
  asia-southeast1
  asia-south1
  australia-southeast1
)

show_regions() {
  echo ""
  echo "🌍 Suggested Cloud Run Regions (pick one):"
  echo ""
  # If gcloud is available, fetch the account regions to mark availability
  AVAILABLE=""
  if command -v gcloud >/dev/null 2>&1; then
    AVAILABLE=$(gcloud run regions list --format="value(name)" 2>/dev/null || true)
  fi

  i=1
  for r in "${SUGGESTED_REGIONS[@]}"; do
    if [ -n "$AVAILABLE" ] && echo "$AVAILABLE" | grep -xq "$r"; then
      printf "%2d) %s (available)\n" "$i" "$r"
    else
      printf "%2d) %s\n" "$i" "$r"
    fi
    ((i++))
  done
}

# -------- Preset Selection --------
if [ "${INTERACTIVE}" = true ] && [ -z "${PRESET:-}" ]; then
  echo ""
  echo "⚡ Quick Start with Presets:"
  echo "1) production (2048MB, 1 CPU, 16 instances, 1000 concurrency)"
  echo "2) budget (2048MB, 2 CPU, 8 instances, 1000 concurrency)"
  echo "3) custom (enter all settings manually)"
  read -rp "Select preset [1-3] (default: 3): " PRESET_CHOICE
fi
PRESET_CHOICE="${PRESET_CHOICE:-3}"

case "$PRESET_CHOICE" in
  1)
    apply_preset "production"
    PRESET_MODE="production"
    ;;
  2)
    apply_preset "budget"
    PRESET_MODE="budget"
    ;;
  *)
    PRESET_MODE="custom"
    ;;
esac

# -------- Basic Settings --------
echo ""
echo "📝 Basic Configuration:"

if [ "${INTERACTIVE}" = true ] && [ -z "${PROTO:-}" ]; then
  read -rp "🔐 Protocol (vless/vmess/trojan) [vless]: " PROTO
fi
PROTO="${PROTO:-vless}"

if [ "${INTERACTIVE}" = true ] && [ -z "${WSPATH:-}" ]; then
  read -rp "📡 WebSocket path [/ws]: " WSPATH
fi
WSPATH="${WSPATH:-/ws}"

if [ "${INTERACTIVE}" = true ] && [ -z "${SERVICE:-}" ]; then
  read -rp "🪪 Service name [xray-service]: " SERVICE
fi
SERVICE="${SERVICE:-xray-service}"

if [ "${INTERACTIVE}" = true ] && [ -z "${REGION:-}" ]; then
  show_regions
  read -rp "Select region [1-${#SUGGESTED_REGIONS[@]}] (default: 1): " REGION_IDX
  REGION_IDX="${REGION_IDX:-1}"
  if [[ ! "$REGION_IDX" =~ ^[0-9]+$ ]] || [ "$REGION_IDX" -lt 1 ] || [ "$REGION_IDX" -gt ${#SUGGESTED_REGIONS[@]} ]; then
    echo "❌ Invalid region selection"
    exit 1
  fi
  REGION="${SUGGESTED_REGIONS[$((REGION_IDX-1))]}"
fi
REGION="${REGION:-us-central1}"

if [ -z "${UUID:-}" ]; then
  UUID=$(cat /proc/sys/kernel/random/uuid)
fi

# -------- Deployment Method --------
if [ "${INTERACTIVE}" = true ] && [ -z "${DEPLOY_METHOD:-}" ]; then
  echo ""
  echo "🚚 Deployment method:"
  echo "1) image (recommended: build and push Docker image, then deploy with --image)"
  echo "2) source (deploy with --source .)"
  read -rp "Select method [1-2] (default: 1): " DEPLOY_CHOICE
fi
DEPLOY_CHOICE="${DEPLOY_CHOICE:-1}"

if [ "$DEPLOY_CHOICE" = "1" ]; then
  DEPLOY_METHOD="image"
else
  DEPLOY_METHOD="source"
fi

if [ "$DEPLOY_METHOD" = "image" ]; then
  # Ask for image name or construct one
  if [ -z "${IMAGE:-}" ]; then
    if command -v gcloud >/dev/null 2>&1; then
      GCLOUD_PROJECT=$(gcloud config get-value project 2>/dev/null || true)
    else
      GCLOUD_PROJECT=""
    fi
    if [ -n "$GCLOUD_PROJECT" ]; then
      DEFAULT_IMAGE="gcr.io/${GCLOUD_PROJECT}/${SERVICE}:lab"
    else
      DEFAULT_IMAGE="gcr.io/<PROJECT>/${SERVICE}:lab"
    fi
    if [ "${INTERACTIVE}" = true ]; then
      read -rp "Docker image to push (default: ${DEFAULT_IMAGE}): " IMAGE
    fi
    IMAGE="${IMAGE:-$DEFAULT_IMAGE}"
  fi
fi

# -------- Performance Settings (All Optional) --------
echo ""
if [ "$PRESET_MODE" = "custom" ]; then
  echo "⚙️  Performance Settings (press Enter to skip):"
else
  echo "⚙️  Performance Settings (preset: $PRESET_MODE - press Enter to keep)"
fi

if [ "${INTERACTIVE}" = true ] && [ -z "${MEMORY:-}" ]; then
  read -rp "💾 Memory (MB) [e.g., 512, 1024, 2048]: " MEMORY
fi
MEMORY="${MEMORY:-}"

if [ "${INTERACTIVE}" = true ] && [ -z "${CPU:-}" ]; then
  read -rp "⚙️  CPU cores [e.g., 0.5, 1, 2, 4]: " CPU
fi
CPU="${CPU:-}"

if [ "${INTERACTIVE}" = true ] && [ -z "${TIMEOUT:-}" ]; then
  read -rp "⏱️  Timeout (seconds) [e.g., 300, 1800, 3600]: " TIMEOUT
fi
TIMEOUT="${TIMEOUT:-}"

if [ "${INTERACTIVE}" = true ] && [ -z "${MAX_INSTANCES:-}" ]; then
  read -rp "📊 Max instances [e.g., 5, 10, 20, 50, 100]: " MAX_INSTANCES
fi
MAX_INSTANCES="${MAX_INSTANCES:-}"

if [ "${INTERACTIVE}" = true ] && [ -z "${CONCURRENCY:-}" ]; then
  read -rp "🔗 Max concurrent requests/instance [e.g., 50, 100, 500, 1000]: " CONCURRENCY
fi
CONCURRENCY="${CONCURRENCY:-}"

# -------- Summary --------
echo ""
echo "📋 Configuration Summary:"
echo "  Protocol: $PROTO"
echo "  Path: $WSPATH"
echo "  Service: $SERVICE"
echo "  Region: $REGION"
echo "  UUID: $UUID"
[ "$PRESET_MODE" != "custom" ] && echo "  Preset: $PRESET_MODE" || echo "  Preset: custom"
[ -n "${MEMORY}" ] && echo "  Memory: ${MEMORY}MB" || echo "  Memory: (default)"
[ -n "${CPU}" ] && echo "  CPU: ${CPU}" || echo "  CPU: (default)"
[ -n "${TIMEOUT}" ] && echo "  Timeout: ${TIMEOUT}s" || echo "  Timeout: (default)"
[ -n "${MAX_INSTANCES}" ] && echo "  Max Instances: ${MAX_INSTANCES}" || echo "  Max Instances: (default)"
[ -n "${CONCURRENCY}" ] && echo "  Concurrency: ${CONCURRENCY}" || echo "  Concurrency: (default)"

# -------- Sanity checks --------
if ! command -v gcloud >/dev/null 2>&1; then
  echo "❌ gcloud CLI not found. Install and authenticate first."
  exit 1
fi

PROJECT=$(gcloud config get-value project 2>/dev/null || true)
if [ -z "${PROJECT:-}" ]; then
  echo "❌ No GCP project set. Run 'gcloud init' or 'gcloud config set project PROJECT_ID'."
  exit 1
fi

# -------- Enable APIs --------
echo ""
echo "⚙️  Enabling required APIs..."
gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet

# -------- Xray Config --------
if [ "$PROTO" = "trojan" ]; then
  CLIENT_CONFIG=$(cat <<EOF
"clients": [{
  "password": "$UUID"
}]
EOF
)
elif [ "$PROTO" = "vless" ]; then
  CLIENT_CONFIG=$(cat <<EOF
"clients": [{
  "id": "$UUID"
}],
"decryption": "none"
EOF
)
else # vmess
  CLIENT_CONFIG=$(cat <<EOF
"clients": [{
  "id": "$UUID"
}]
EOF
)
fi

# Ensure path begins with '/'
if [[ "${WSPATH}" != /* ]]; then
  WSPATH="/${WSPATH}"
fi

# -------- Generate Xray Config --------
cat > config.json <<'XRAY_CONFIG'
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [{
    "port": 8080,
    "listen": "0.0.0.0",
    "protocol": "__PROTO__",
    "settings": {
      __CLIENT_CONFIG__
    },
    "streamSettings": {
      "network": "ws",
      "security": "none",
      "wsSettings": {
        "path": "__WS_PATH__",
        "connectionReuse": true
      }
    },
    "sniffing": {
      "enabled": true,
      "destOverride": ["http", "tls"],
      "metadataOnly": false
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {
      "domainStrategy": "UseIPv4"
    }
  }]
}
XRAY_CONFIG

# Replace template variables
sed -i "s|__PROTO__|$PROTO|g" config.json
sed -i "s|__CLIENT_CONFIG__|$CLIENT_CONFIG|g" config.json
sed -i "s|__WS_PATH__|$WSPATH|g" config.json

echo "✅ Generated config.json"

# -------- Build Deploy Command --------
echo ""
echo "🚀 Deploying to Cloud Run..."

# Build deploy command with optional parameters
if [ "${DEPLOY_METHOD:-source}" = "image" ]; then
  # Build & push image using Cloud Build
  echo "🔨 Building and pushing image: ${IMAGE}"
  if ! command -v gcloud >/dev/null 2>&1; then
    echo "❌ gcloud CLI not found. Install and authenticate first."
    exit 1
  fi
  # Ensure project is set
  GCLOUD_PROJECT=$(gcloud config get-value project 2>/dev/null || true)
  if [ -z "$GCLOUD_PROJECT" ]; then
    echo "❌ No GCP project set. Run 'gcloud init' or 'gcloud config set project PROJECT_ID'."
    exit 1
  fi
  # If IMAGE uses <PROJECT> placeholder, replace it
  IMAGE="${IMAGE//<PROJECT>/$GCLOUD_PROJECT}"
  gcloud builds submit --tag "$IMAGE" .
  DEPLOY_ARGS=(
    "--image" "$IMAGE"
    "--region" "$REGION"
    "--platform" "managed"
    "--allow-unauthenticated"
  )
else
  DEPLOY_ARGS=(
    "--source" "."
    "--region" "$REGION"
    "--platform" "managed"
    "--allow-unauthenticated"
  )
fi

[ -n "${MEMORY}" ] && DEPLOY_ARGS+=("--memory" "${MEMORY}Mi")
[ -n "${CPU}" ] && DEPLOY_ARGS+=("--cpu" "${CPU}")
[ -n "${TIMEOUT}" ] && DEPLOY_ARGS+=("--timeout" "${TIMEOUT}")
[ -n "${MAX_INSTANCES}" ] && DEPLOY_ARGS+=("--max-instances" "${MAX_INSTANCES}")
[ -n "${CONCURRENCY}" ] && DEPLOY_ARGS+=("--concurrency" "${CONCURRENCY}")

DEPLOY_ARGS+=("--quiet")

# Execute deploy
gcloud run deploy "$SERVICE" "${DEPLOY_ARGS[@]}"

# -------- Get Service URL --------
PROJECT_NUMBER=$(gcloud projects describe $(gcloud config get-value project 2>/dev/null) --format="value(projectNumber)" 2>/dev/null)
HOST="${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"
echo "✅ Using primary domain: ${HOST}"

echo ""
echo "=========================================="
echo "✅ DEPLOYMENT SUCCESS"
echo "=========================================="
echo "Protocol : $PROTO"
echo "Address  : $HOST"
echo "Port     : 443 (Cloud Run HTTPS)"
echo "UUID/PWD : $UUID"
echo "Path     : $WSPATH"
echo "Network  : WebSocket + TLS"

if [ -n "${MEMORY}${CPU}${TIMEOUT}${MAX_INSTANCES}${CONCURRENCY}" ]; then
  echo ""
  echo "⚙️  Configuration Applied:"
  [ -n "${MEMORY}" ] && echo "Memory      : ${MEMORY}MB"
  [ -n "${CPU}" ] && echo "CPU         : ${CPU} cores"
  [ -n "${TIMEOUT}" ] && echo "Timeout     : ${TIMEOUT}s"
  [ -n "${MAX_INSTANCES}" ] && echo "Max Instances : ${MAX_INSTANCES}"
  [ -n "${CONCURRENCY}" ] && echo "Concurrency : ${CONCURRENCY} requests/instance"
fi
echo "=========================================="

# -------- Generate Share Links --------
if [ "$PROTO" = "vless" ]; then
  VLESS_LINK="vless://${UUID}@${HOST}:443?type=ws&security=tls&path=${WSPATH}#xray"
  echo ""
  echo "📎 VLESS LINK:"
  echo "$VLESS_LINK"
elif [ "$PROTO" = "vmess" ]; then
  VMESS_JSON=$(cat <<EOF
{
  "v": "2",
  "ps": "$SERVICE",
  "add": "$HOST",
  "port": "443",
  "id": "$UUID",
  "aid": "0",
  "net": "ws",
  "type": "none",
  "host": "$HOST",
  "path": "$WSPATH",
  "tls": "tls"
}
EOF
)
  VMESS_LINK="vmess://$(echo "$VMESS_JSON" | base64 -w 0)"
  echo ""
  echo "📎 VMESS LINK:"
  echo "$VMESS_LINK"
elif [ "$PROTO" = "trojan" ]; then
  TROJAN_LINK="trojan://${UUID}@${HOST}:443?type=ws&security=tls&path=${WSPATH}#xray"
  echo ""
  echo "📎 TROJAN LINK:"
  echo "$TROJAN_LINK"
fi

echo "=========================================="
