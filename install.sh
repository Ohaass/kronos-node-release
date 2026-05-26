#!/bin/bash
# ─────────────────────────────────────────────────────────────────────
# KRONOS Protocol Node — Installation Script v0.2.0
#
# Permissioned post-quantum L1 network.
# Two-phase install:
#   Phase 1 (bootstrap):  generates Dilithium3 keypair + cert-request JSON
#   Phase 2 (finalize):   installs your signed NodeCert and starts the service
#
# Usage:
#   sudo bash install.sh                          # phase 1: bootstrap
#   sudo bash install.sh --finalize <cert-path>   # phase 2: finalize
#   sudo bash install.sh --help                   # this message
#
# Repository: https://github.com/Ohaass/kronos-node-release
# Contact:    info@kroscripto.com
# ─────────────────────────────────────────────────────────────────────

set -euo pipefail

KRONOS_VERSION="0.2.0"
RELEASE_URL="https://github.com/Ohaass/kronos-node-release/releases/download/v${KRONOS_VERSION}"
TRUST_BUNDLE_URL="https://raw.githubusercontent.com/Ohaass/kronos-node-release/main/trust-bundle.bin"
TRUST_BUNDLE_SHA256="ef6a28a3fff77229839150ebbd968446e91777c9ba70b72b0e2cb991f19ef893"
CHAIN_ID="kros-mainnet"
P2P_PORT="9000"
METRICS_PORT="9100"
CONTACT_EMAIL="info@kroscripto.com"

INSTALL_DIR="/opt/kronos/v0.2.0"
CONFIG_DIR="/etc/kronos/v0.2.0"
DATA_DIR="/var/lib/kronos/v0.2.0"
SECURE_KEYGEN_OUT="/root/.kronos-keygen-output"   # only root-readable, mode 600

BOOTSTRAP_PEERS=(
  "46.225.210.40:9000"
  "204.168.244.93:9000"
  "62.238.3.59:9000"
  "62.238.1.207:9000"
)

# ─── colours ─────────────────────────────────────────────────────────
if [ -t 1 ]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; BLUE=$'\033[0;34m'; NC=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi
info()  { echo "${BLUE}[i]${NC} $*"; }
ok()    { echo "${GREEN}[✓]${NC} $*"; }
warn()  { echo "${YELLOW}[!]${NC} $*"; }
error() { echo "${RED}[✗]${NC} $*" >&2; exit 1; }

# ─── pre-flight checks ───────────────────────────────────────────────
require_root() {
  [ "$EUID" -eq 0 ] || error "Must run as root. Use:  sudo bash install.sh"
}

require_ubuntu() {
  if ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
    warn "Not running on Ubuntu. Ubuntu 22.04 or 24.04 LTS is recommended."
    read -r -p "Continue anyway? [y/N] " -n 1; echo
    [[ "$REPLY" =~ ^[Yy]$ ]] || exit 1
  fi
}

require_resources() {
  local mem_mb cores disk_gb
  mem_mb=$(free -m | awk '/^Mem:/{print $2}')
  cores=$(nproc)
  disk_gb=$(df -BG --output=avail / | tail -1 | tr -d 'G ')
  [ "$mem_mb"  -ge 3500 ] || error "Need ≥4 GB RAM (have ${mem_mb} MB)"
  [ "$cores"   -ge    2 ] || error "Need ≥2 CPU cores (have ${cores})"
  [ "$disk_gb" -ge   35 ] || error "Need ≥40 GB free disk (have ${disk_gb} GB)"
  ok "Resources OK — ${mem_mb} MB RAM, ${cores} cores, ${disk_gb} GB free"
}

# ─── download + verify helpers ───────────────────────────────────────
download_to() {
  local url="$1" dst="$2"
  curl -fsSL --retry 3 --retry-delay 2 "$url" -o "$dst" \
    || error "Failed to download: $url"
}

verify_sha256() {
  local file="$1" expected="$2"
  local actual
  actual=$(sha256sum "$file" | cut -d' ' -f1)
  [ "$actual" = "$expected" ] \
    || error "SHA256 mismatch on $file. Expected $expected, got $actual"
}

# ─── phase 1: bootstrap ──────────────────────────────────────────────
phase_bootstrap() {
  echo
  echo "─────────────────────────────────────────────────────────────"
  echo "  KRONOS Protocol Node v${KRONOS_VERSION} — Bootstrap"
  echo "─────────────────────────────────────────────────────────────"
  echo

  require_root
  require_ubuntu
  require_resources

  info "Installing system dependencies (curl, jq, ufw, ca-certificates)..."
  apt-get update -q
  apt-get install -y -q curl jq ufw ca-certificates >/dev/null
  ok "Dependencies installed"

  info "Creating directory structure..."
  mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$DATA_DIR"
  chmod 755 "$INSTALL_DIR"
  chmod 700 "$CONFIG_DIR" "$DATA_DIR"
  ok "Directories created"

  # ── Trust bundle ───
  info "Downloading trust bundle..."
  download_to "$TRUST_BUNDLE_URL" "$CONFIG_DIR/trust-bundle.bin"
  verify_sha256 "$CONFIG_DIR/trust-bundle.bin" "$TRUST_BUNDLE_SHA256"
  chmod 644 "$CONFIG_DIR/trust-bundle.bin"
  ok "Trust bundle verified (SHA256 OK)"

  # ── kros-ca verifier ───
  info "Downloading kros-ca verifier..."
  download_to "${RELEASE_URL}/kros-ca-linux-x86_64"     "$INSTALL_DIR/kros-ca"
  download_to "${RELEASE_URL}/kros-ca-linux-x86_64.sig" "$INSTALL_DIR/kros-ca.sig"
  chmod 755 "$INSTALL_DIR/kros-ca"
  
  info "Verifying kros-ca self-signature..."
  "$INSTALL_DIR/kros-ca" verify-file \
    --in-file "$INSTALL_DIR/kros-ca" \
    --sig     "$INSTALL_DIR/kros-ca.sig" \
    --bundle  "$CONFIG_DIR/trust-bundle.bin" \
    > /dev/null \
    || error "kros-ca signature verification FAILED. Aborting."
  ok "kros-ca verified (Dilithium3 + SHA3-256)"

  # ── kronos-node binary ───
  info "Downloading kronos-node v${KRONOS_VERSION} binary..."
  download_to "${RELEASE_URL}/kronos-node-linux-x86_64"     "$INSTALL_DIR/kronos-node"
  download_to "${RELEASE_URL}/kronos-node-linux-x86_64.sig" "$INSTALL_DIR/kronos-node.sig"
  chmod 755 "$INSTALL_DIR/kronos-node"

  info "Verifying kronos-node binary signature (Dilithium3 + SHA3-256)..."
  "$INSTALL_DIR/kros-ca" verify-file \
    --in-file "$INSTALL_DIR/kronos-node" \
    --sig     "$INSTALL_DIR/kronos-node.sig" \
    --bundle  "$CONFIG_DIR/trust-bundle.bin" \
    > /dev/null \
    || error "kronos-node signature verification FAILED. Aborting."
  ok "kronos-node verified (Dilithium3 + SHA3-256)"

  local reported_version
  reported_version=$("$INSTALL_DIR/kronos-node" --version 2>/dev/null | tr -d '\n')
  ok "Binary version: $reported_version"

  # ── Generate Dilithium3 keypair ───
  info "Generating Dilithium3 keypair (this is your node's identity)..."
  # Capture full output to a root-only file to avoid leaking SecretKey to terminal
  umask 077
  "$INSTALL_DIR/kronos-node" --keygen > "$SECURE_KEYGEN_OUT" 2>&1
  chmod 600 "$SECURE_KEYGEN_OUT"
  umask 022

  # Parse: lines look like "Address:    kros1...", "PublicKey:  <hex>", "SecretKey:  <hex>"
  local kros_address pubkey_hex privkey_hex
  kros_address=$(awk '/^Address:/{print $2; exit}' "$SECURE_KEYGEN_OUT")
  pubkey_hex=$(awk '/^PublicKey:/{print $2; exit}' "$SECURE_KEYGEN_OUT")
  privkey_hex=$(awk '/^SecretKey:/{print $2; exit}' "$SECURE_KEYGEN_OUT")

  [ -n "$kros_address" ] || error "Failed to parse Address from keygen output"
  [ -n "$pubkey_hex" ] || error "Failed to parse PublicKey from keygen output"
  [ -n "$privkey_hex" ] || error "Failed to parse SecretKey from keygen output"
  [ "${#privkey_hex}" -ge 8000 ] || error "SecretKey hex looks too short (got ${#privkey_hex} chars)"

  ok "Keypair generated (address: $kros_address)"

  # ── Store private key in PEM format expected by kronos-node v0.2.0 ───
  info "Storing private key in PEM format at $CONFIG_DIR/node.key..."
  {
    echo "-----BEGIN KRONOS NODE KEY-----"
    echo -n "$privkey_hex" | xxd -r -p | base64 -w 64
    echo "-----END KRONOS NODE KEY-----"
  } > "$CONFIG_DIR/node.key"
  chmod 600 "$CONFIG_DIR/node.key"
  ok "Private key stored (chmod 600)"

  # Shred the captured keygen output now that the key is in place
  shred -u "$SECURE_KEYGEN_OUT" 2>/dev/null || rm -f "$SECURE_KEYGEN_OUT"

  # ── Public IP detection ───
  local public_ip
  public_ip=$(curl -s -4 --max-time 5 https://api.ipify.org 2>/dev/null \
              || curl -s -4 --max-time 5 https://ifconfig.me 2>/dev/null \
              || echo "UNKNOWN")
  if [ "$public_ip" = "UNKNOWN" ]; then
    warn "Could not auto-detect public IP. Edit cert-request.json before sending."
  fi

  # ── node_id ───
  local node_id
  node_id="kronos-$(hostname -s | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')"

  # ── cert-request.json ───
  info "Generating cert-request JSON..."
  local cert_req="$CONFIG_DIR/cert-request.json"
  cat > "$cert_req" <<JSON
{
  "node_id": "$node_id",
  "node_pubkey_hex": "$pubkey_hex",
  "kros_address": "$kros_address",
  "capabilities": ["validator"],
  "operator_email": "REPLACE_WITH_YOUR_EMAIL",
  "public_ip": "$public_ip",
  "p2p_port": $P2P_PORT,
  "requested_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
  chmod 644 "$cert_req"
  ok "cert-request saved to $cert_req"

  # ── UFW ───
  info "Configuring firewall (UFW)..."
  ufw --force enable >/dev/null
  ufw allow 22/tcp >/dev/null
  for peer in "${BOOTSTRAP_PEERS[@]}"; do
    local peer_ip="${peer%%:*}"
    ufw allow from "$peer_ip" to any port "$P2P_PORT" proto tcp >/dev/null
  done
  ok "UFW: SSH open, port $P2P_PORT open only from KRONOS peers"

  # ── Summary + next steps ───
  echo
  echo "─────────────────────────────────────────────────────────────"
  ok "Phase 1 (bootstrap) complete."
  echo "─────────────────────────────────────────────────────────────"
  echo
  echo "  Node ID:       $node_id"
  echo "  KROS Address:  $kros_address"
  echo "  Public IP:     $public_ip"
  echo "  P2P Port:      $P2P_PORT"
  echo
  echo "─────────────────────────────────────────────────────────────"
  echo "  NEXT STEPS"
  echo "─────────────────────────────────────────────────────────────"
  echo
  echo "  1. Open $cert_req"
  echo "     Replace REPLACE_WITH_YOUR_EMAIL with your contact email."
  echo
  echo "  2. Email the file as attachment to: $CONTACT_EMAIL"
  echo "     Subject: 'NodeCert request: $node_id'"
  echo
  echo "  3. Wait for the signed NodeCert reply (typically 24-48h)."
  echo
  echo "  4. Save the .cert file to this server, then run:"
  echo
  echo "       sudo bash install.sh --finalize /path/to/your.cert"
  echo
  echo "  Your node WILL NOT start until phase 2 is complete."
  echo
  echo "  Docs:  https://github.com/Ohaass/kronos-node-release"
  echo
}

# ─── phase 2: finalize ───────────────────────────────────────────────
phase_finalize() {
  local cert_path="$1"
  echo
  echo "─────────────────────────────────────────────────────────────"
  echo "  KRONOS Protocol Node v${KRONOS_VERSION} — Finalize"
  echo "─────────────────────────────────────────────────────────────"
  echo

  require_root

  [ -f "$cert_path" ] || error "Cert file not found: $cert_path"
  [ -f "$CONFIG_DIR/node.key" ] || error "node.key not found — run phase 1 first"
  [ -f "$CONFIG_DIR/trust-bundle.bin" ] || error "trust-bundle.bin not found — run phase 1 first"
  [ -x "$INSTALL_DIR/kronos-node" ] || error "kronos-node binary not found — run phase 1 first"
  [ -x "$INSTALL_DIR/kros-ca" ] || error "kros-ca binary not found — run phase 1 first"
  [ -f "$CONFIG_DIR/cert-request.json" ] || error "cert-request.json not found — run phase 1 first"

  # ── Verify the cert against the trust bundle BEFORE installing ───
  info "Verifying NodeCert against trust bundle..."
  "$INSTALL_DIR/kros-ca" verify \
    --cert "$cert_path" \
    --bundle "$CONFIG_DIR/trust-bundle.bin" \
    --chain-id "$CHAIN_ID" \
    > /dev/null \
    || error "NodeCert verification FAILED. Refusing to install."
  ok "NodeCert is valid (signed by intermediate, chain matches)"

  # ── Install cert ───
  cp "$cert_path" "$CONFIG_DIR/node.cert"
  chmod 644 "$CONFIG_DIR/node.cert"
  ok "Cert installed at $CONFIG_DIR/node.cert"

  # ── Read node_id / public_ip from cert-request ───
  local node_id public_ip
  node_id=$(jq -r '.node_id' "$CONFIG_DIR/cert-request.json")
  public_ip=$(jq -r '.public_ip' "$CONFIG_DIR/cert-request.json")
  [ "$node_id" != "null" ] || error "node_id missing from cert-request.json"
  [ "$public_ip" != "null" ] || public_ip="0.0.0.0"

  # ── Generate node.toml ───
  info "Generating node.toml..."
  {
    echo "[node]"
    echo "node_id = \"$node_id\""
    echo "data_dir = \"$DATA_DIR\""
    echo "chain_id = \"$CHAIN_ID\""
    echo ""
    echo "[identity]"
    echo "cert_path = \"$CONFIG_DIR/node.cert\""
    echo "key_path = \"$CONFIG_DIR/node.key\""
    echo ""
    echo "[p2p]"
    echo "listen_addr = \"0.0.0.0:$P2P_PORT\""
    echo "public_addr = \"${public_ip}:${P2P_PORT}\""
    echo "bootstrap_peers = ["
    for peer in "${BOOTSTRAP_PEERS[@]}"; do
      echo "  \"$peer\","
    done
    echo "]"
    echo "revocation_url = \"https://www.kroscripto.com/revocation.bin\""
    echo ""
    echo "[metrics]"
    echo "listen_addr = \"127.0.0.1:${METRICS_PORT}\""
    echo ""
    echo "[trust]"
    echo "bundle_path = \"$CONFIG_DIR/trust-bundle.bin\""
  } > "$CONFIG_DIR/node.toml"
  chmod 600 "$CONFIG_DIR/node.toml"
  ok "node.toml generated"

  warn "OPTIONAL: To register your node with the public KRONOS dashboard, you"
  warn "          must add a [supabase] section to $CONFIG_DIR/node.toml using"
  warn "          credentials provided in the email reply (NOT public)."

  # ── systemd unit ───
  info "Creating systemd service..."
  cat > /etc/systemd/system/kronos-node.service <<SVC
[Unit]
Description=KRONOS Protocol Node v${KRONOS_VERSION}
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/kronos-node --config $CONFIG_DIR/node.toml
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=$DATA_DIR /var/log

[Install]
WantedBy=multi-user.target
SVC
  ok "systemd unit created"

  systemctl daemon-reload
  systemctl enable kronos-node.service >/dev/null 2>&1
  systemctl start kronos-node.service
  ok "kronos-node service started"

  sleep 5

  if systemctl is-active --quiet kronos-node.service; then
    ok "Service is active"
    echo
    echo "─────────────────────────────────────────────────────────────"
    ok "Phase 2 (finalize) complete. Your node is running."
    echo "─────────────────────────────────────────────────────────────"
    echo
    echo "  Status:     systemctl status kronos-node"
    echo "  Logs:       journalctl -u kronos-node -f"
    echo "  Metrics:    curl http://127.0.0.1:${METRICS_PORT}/metrics"
    echo
    echo "  Dashboard:  https://www.kroscripto.com/network"
    echo "             (your node should appear within ~1 minute)"
    echo
  else
    journalctl -u kronos-node -n 30 --no-pager >&2 || true
    error "Service failed to start. See logs above. Help: $CONTACT_EMAIL"
  fi
}

# ─── help ────────────────────────────────────────────────────────────
show_help() {
  cat <<HELP
KRONOS Protocol Node v${KRONOS_VERSION} — Installation Script

Usage:
  sudo bash install.sh                            Phase 1: bootstrap (generates keypair + cert-request)
  sudo bash install.sh --finalize <cert-path>     Phase 2: finalize (after receiving signed cert by email)
  sudo bash install.sh --help                     Show this help

Workflow:
  1. Run phase 1 — generates keypair, downloads + verifies binaries with Dilithium3.
  2. Email $CONFIG_DIR/cert-request.json to $CONTACT_EMAIL.
  3. Wait for signed NodeCert reply.
  4. Save the .cert file to your server.
  5. Run phase 2 with --finalize <cert-path>.

Repository: https://github.com/Ohaass/kronos-node-release
HELP
}

# ─── entry point ─────────────────────────────────────────────────────
case "${1:-}" in
  --finalize)
    [ -n "${2:-}" ] || error "Usage: sudo bash install.sh --finalize <cert-path>"
    phase_finalize "$2"
    ;;
  --help|-h)
    show_help
    ;;
  "")
    phase_bootstrap
    ;;
  *)
    error "Unknown option: $1. Run with --help for usage."
    ;;
esac
