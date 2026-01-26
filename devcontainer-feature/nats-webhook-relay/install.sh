#!/usr/bin/env bash
#-------------------------------------------------------------------------------------------------------------
# NATS Webhook Relay Devcontainer Feature
# https://github.com/wunderwerkio/nats-webhook-relay
#-------------------------------------------------------------------------------------------------------------
set -e

# Feature options (converted to uppercase by devcontainer spec)
VERSION="${VERSION:-"latest"}"
WEBHOOK_DESTINATION="${WEBHOOKDESTINATION:-"http://localhost:3000/api/cache/webhook"}"
NATS_ADDRESS="${NATSADDRESS:-""}"
NATS_USER="${NATSUSER:-""}"
NATS_PASS="${NATSPASS:-""}"
NATS_SUBJECT_PREFIX="${NATSSUBJECTPREFIX:-"cms.cache"}"
NATS_RELAYED_SUBJECT_PREFIX="${NATSRELAYEDSUBJECTPREFIX:-"relayed.cache"}"
LOG_LEVEL="${LOGLEVEL:-"info"}"
ENABLED="${ENABLED:-"true"}"

GITHUB_REPO="wunderwerkio/nats-webhook-relay"
INSTALL_PATH="/usr/local/bin/nats-webhook-relay"
INIT_SCRIPT_PATH="/usr/local/share/nats-webhook-relay-init.sh"

echo "Installing nats-webhook-relay..."

# Ensure curl is available
if ! command -v curl &> /dev/null; then
    echo "Installing curl..."
    apt-get update && apt-get install -y --no-install-recommends curl ca-certificates
fi

# Determine architecture
ARCH="$(uname -m)"
case "${ARCH}" in
    x86_64)
        TARGET="x86_64-unknown-linux-gnu"
        ;;
    aarch64|arm64)
        TARGET="aarch64-unknown-linux-gnu"
        ;;
    *)
        echo "(!) Unsupported architecture: ${ARCH}"
        exit 1
        ;;
esac

echo "Detected architecture: ${ARCH} -> ${TARGET}"

# Resolve version if 'latest'
if [ "${VERSION}" = "latest" ]; then
    echo "Fetching latest release version..."
    VERSION=$(curl -sL "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" | grep '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/')
    if [ -z "${VERSION}" ]; then
        echo "(!) Failed to fetch latest version from GitHub API"
        exit 1
    fi
fi

VERSION="${VERSION#v}"
echo "Installing version: ${VERSION}"

# Download binary
DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}/nats-webhook-relay-${TARGET}"
echo "Downloading from ${DOWNLOAD_URL}..."

if ! curl -fsSL "${DOWNLOAD_URL}" -o "${INSTALL_PATH}"; then
    echo "(!) Failed to download binary from ${DOWNLOAD_URL}"
    echo "(!) Make sure version ${VERSION} exists and has binaries for ${TARGET}"
    exit 1
fi

chmod +x "${INSTALL_PATH}"
echo "Binary installed to ${INSTALL_PATH}"

# Create init script that runs at container start
tee "${INIT_SCRIPT_PATH}" > /dev/null << 'INITEOF'
#!/usr/bin/env bash
set -e

# Configuration baked in at install time
RELAY_ENABLED="__ENABLED__"
WEBHOOK_DESTINATION="__WEBHOOK_DESTINATION__"
NATS_ADDRESS="__NATS_ADDRESS__"
NATS_USER="__NATS_USER__"
NATS_PASS="__NATS_PASS__"
NATS_SUBJECT_PREFIX="__NATS_SUBJECT_PREFIX__"
NATS_RELAYED_SUBJECT_PREFIX="__NATS_RELAYED_SUBJECT_PREFIX__"
RUST_LOG="__LOG_LEVEL__"

# Allow runtime overrides via environment variables
# This lets users override in devcontainer.json containerEnv or docker run -e
WEBHOOK_DESTINATION="${NATS_RELAY_WEBHOOK_DESTINATION:-$WEBHOOK_DESTINATION}"
NATS_ADDRESS="${NATS_RELAY_NATS_ADDRESS:-$NATS_ADDRESS}"
NATS_USER="${NATS_RELAY_NATS_USER:-$NATS_USER}"
NATS_PASS="${NATS_RELAY_NATS_PASS:-$NATS_PASS}"
NATS_SUBJECT_PREFIX="${NATS_RELAY_NATS_SUBJECT_PREFIX:-$NATS_SUBJECT_PREFIX}"
NATS_RELAYED_SUBJECT_PREFIX="${NATS_RELAY_NATS_RELAYED_SUBJECT_PREFIX:-$NATS_RELAYED_SUBJECT_PREFIX}"
RUST_LOG="${NATS_RELAY_RUST_LOG:-$RUST_LOG}"
RELAY_ENABLED="${NATS_RELAY_ENABLED:-$RELAY_ENABLED}"

LOG_FILE="/tmp/nats-webhook-relay.log"

if [ "${RELAY_ENABLED}" = "true" ]; then
    if [ -n "${NATS_ADDRESS}" ]; then
        echo "[nats-webhook-relay] Starting relay service..."
        echo "[nats-webhook-relay] NATS: ${NATS_ADDRESS}"
        echo "[nats-webhook-relay] Webhook: ${WEBHOOK_DESTINATION}"
        echo "[nats-webhook-relay] Subject: ${NATS_SUBJECT_PREFIX}.> -> ${NATS_RELAYED_SUBJECT_PREFIX}.>"
        
        # Export environment variables for the relay process
        export WEBHOOK_DESTINATION NATS_ADDRESS NATS_USER NATS_PASS
        export NATS_SUBJECT_PREFIX NATS_RELAYED_SUBJECT_PREFIX RUST_LOG
        
        # Start relay in background
        /usr/local/bin/nats-webhook-relay >> "${LOG_FILE}" 2>&1 &
        RELAY_PID=$!
        
        echo "[nats-webhook-relay] Started with PID ${RELAY_PID}"
        echo "[nats-webhook-relay] Logs: ${LOG_FILE}"
    else
        echo "[nats-webhook-relay] Skipped: NATS_ADDRESS not configured"
        echo "[nats-webhook-relay] Set natsAddress in feature options or NATS_RELAY_NATS_ADDRESS env var"
    fi
else
    echo "[nats-webhook-relay] Disabled (enabled=false)"
fi

# Pass control to the container's main process
exec "$@"
INITEOF

# Substitute configuration values into the init script
sed -i "s|__ENABLED__|${ENABLED}|g" "${INIT_SCRIPT_PATH}"
sed -i "s|__WEBHOOK_DESTINATION__|${WEBHOOK_DESTINATION}|g" "${INIT_SCRIPT_PATH}"
sed -i "s|__NATS_ADDRESS__|${NATS_ADDRESS}|g" "${INIT_SCRIPT_PATH}"
sed -i "s|__NATS_USER__|${NATS_USER}|g" "${INIT_SCRIPT_PATH}"
sed -i "s|__NATS_PASS__|${NATS_PASS}|g" "${INIT_SCRIPT_PATH}"
sed -i "s|__NATS_SUBJECT_PREFIX__|${NATS_SUBJECT_PREFIX}|g" "${INIT_SCRIPT_PATH}"
sed -i "s|__NATS_RELAYED_SUBJECT_PREFIX__|${NATS_RELAYED_SUBJECT_PREFIX}|g" "${INIT_SCRIPT_PATH}"
sed -i "s|__LOG_LEVEL__|${LOG_LEVEL}|g" "${INIT_SCRIPT_PATH}"

chmod +x "${INIT_SCRIPT_PATH}"

echo "nats-webhook-relay feature installed successfully!"
echo "  Binary: ${INSTALL_PATH}"
echo "  Init script: ${INIT_SCRIPT_PATH}"
