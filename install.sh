#!/usr/bin/env bash
# cdn-ip-ban 一键安装脚本 / One-line installer
# 用法 / Usage:
#   curl -fsSL https://raw.githubusercontent.com/pursork/gcp-free/main/install.sh | sudo bash
#   curl -fsSL https://raw.githubusercontent.com/pursork/gcp-free/main/install.sh | sudo bash -s -- --provider=cloudflare

set -euo pipefail

readonly RAW_BASE="https://raw.githubusercontent.com/pursork/gcp-free/main"
readonly INSTALL_PATH="/usr/local/sbin/cdn_ip_ban.sh"
readonly LINK_PATH="/usr/local/bin/cdn-ip-ban"

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || error "请以 root 运行 / Run as root (sudo)"

# Collect any extra args to pass to cdn-ip-ban install
EXTRA_ARGS=("$@")

# ── Download cdn_ip_ban.sh ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"
LOCAL_SCRIPT="${SCRIPT_DIR}/cdn_ip_ban.sh"

if [[ -f "$LOCAL_SCRIPT" ]]; then
    info "使用本地文件 / Using local file: $LOCAL_SCRIPT"
    cp "$LOCAL_SCRIPT" "$INSTALL_PATH"
else
    info "从 GitHub 下载... / Downloading from GitHub..."
    if command -v curl &>/dev/null; then
        curl -fsSL --connect-timeout 30 --max-time 120 \
            "${RAW_BASE}/cdn_ip_ban.sh" -o "$INSTALL_PATH"
    elif command -v wget &>/dev/null; then
        wget -q --timeout=120 "${RAW_BASE}/cdn_ip_ban.sh" -O "$INSTALL_PATH"
    else
        error "curl 或 wget 未找到 / curl or wget not found"
    fi
fi

chmod 755 "$INSTALL_PATH"
ln -sf "$INSTALL_PATH" "$LINK_PATH"
success "已安装 / Installed: $INSTALL_PATH"
success "命令链接 / Command:   cdn-ip-ban"

# ── Apply blocking rules ──────────────────────────────────────────────────────
info "正在应用封锁规则... / Applying block rules..."
"$INSTALL_PATH" install "${EXTRA_ARGS[@]}"
