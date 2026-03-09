#!/bin/bash
################################################################################
# cdn_ip_ban.sh — Block CDN IP addresses with ipset + iptables
# 使用 ipset + iptables 封锁主流 CDN 的 IP 地址
#
# Author: pursuer [nodeseek.com]
# Repo:   https://github.com/pursork/gcp-free
#
# Usage / 用法:
#   cdn-ip-ban install   [--provider=PROVIDER] [--ipv6]
#   cdn-ip-ban uninstall [--provider=PROVIDER]
#   cdn-ip-ban update    [--provider=PROVIDER] [--ipv6]
#   cdn-ip-ban status
#
# Supported providers / 支持的 CDN 提供商: cloudflare  fastly  akamai  all
################################################################################

set -euo pipefail

# ── Constants / 常量 ──────────────────────────────────────────────────────────
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="/var/log/cdn_ip_ban.log"
readonly LOCK_FILE="/var/run/cdn_ip_ban.lock"
readonly IP_LIST_DIR="/etc/cdn_blocked_ips"

# Provider IP list URLs
readonly CLOUDFLARE_V4_URL="${CLOUDFLARE_IP_LIST_V4_URL:-https://www.cloudflare.com/ips-v4}"
readonly CLOUDFLARE_V6_URL="${CLOUDFLARE_IP_LIST_V6_URL:-https://www.cloudflare.com/ips-v6}"
readonly FASTLY_URL="${FASTLY_IP_LIST_URL:-https://api.fastly.com/public-ip-list}"
readonly AKAMAI_URL="${AKAMAI_IP_LIST_URL:-https://raw.githubusercontent.com/platformbuilds/Akamai-ASN-and-IPs-List/master/akamai_ip_list.lst}"

# Colours / 颜色
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# ── CLI defaults / 命令行默认值 ───────────────────────────────────────────────
SELECTED_PROVIDERS="all"
ENABLE_IPV6=false

# ── Logging / 日志 ────────────────────────────────────────────────────────────
log() {
    local level="$1"; shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" >> "$LOG_FILE" 2>/dev/null || true
}

print_info()    { echo -e "${BLUE}[INFO]${NC} $*";    log "INFO"    "$*"; }
print_success() { echo -e "${GREEN}[OK]${NC}   $*";   log "OK"      "$*"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $*";  log "WARN"    "$*"; }
print_error()   { echo -e "${RED}[ERR]${NC}  $*" >&2; log "ERROR"   "$*"; }

check_root() {
    [[ $EUID -eq 0 ]] && return 0
    print_error "需要 root 权限 / Root privileges required"
    exit 1
}

acquire_lock() {
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        print_error "另一个实例正在运行 / Another instance is already running"
        exit 1
    fi
}

# ── Dependencies / 依赖检查 ───────────────────────────────────────────────────
check_dependencies() {
    local missing=()
    command -v iptables &>/dev/null            || missing+=("iptables")
    command -v ipset    &>/dev/null            || missing+=("ipset")
    command -v curl     &>/dev/null            || missing+=("curl")
    command -v jq       &>/dev/null            || missing+=("jq")
    command -v flock    &>/dev/null            || missing+=("util-linux")
    dpkg -l iptables-persistent &>/dev/null 2>&1 || missing+=("iptables-persistent")
    dpkg -l ipset-persistent    &>/dev/null 2>&1 || missing+=("ipset-persistent")

    if [[ ${#missing[@]} -gt 0 ]]; then
        print_info "安装依赖... / Installing dependencies: ${missing[*]}"
        DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}" -qq
    fi
}

# ── Provider helpers / Provider 辅助函数 ─────────────────────────────────────
get_provider_list() {
    if [[ "$SELECTED_PROVIDERS" == "all" ]]; then
        echo "cloudflare fastly akamai"
    else
        echo "$SELECTED_PROVIDERS"
    fi
}

validate_provider() {
    case "$1" in
        cloudflare|fastly|akamai) return 0 ;;
        *) print_error "无效 provider / Invalid provider: $1 (cloudflare|fastly|akamai|all)"; exit 1 ;;
    esac
}

# ── IP download functions / IP 下载函数 ───────────────────────────────────────

# Download a plain-text IP list, one IP/CIDR per line
download_text() {
    local url="$1" dest="$2"
    local tmp; tmp=$(mktemp)
    if ! curl -fsSL --connect-timeout 30 --max-time 120 "$url" -o "$tmp" 2>/dev/null; then
        rm -f "$tmp"; return 1
    fi
    grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]+)?$|^[0-9a-fA-F:]+(/[0-9]+)?$' "$tmp" \
        | sort -u > "$dest"
    rm -f "$tmp"
}

# Download Fastly JSON: {"addresses":["1.2.3.0/24",...]}
download_fastly_json() {
    local dest="$1"
    local tmp; tmp=$(mktemp)
    if ! curl -fsSL --connect-timeout 30 --max-time 120 "$FASTLY_URL" -o "$tmp" 2>/dev/null; then
        rm -f "$tmp"; return 1
    fi
    { jq -r '.addresses[]?'          "$tmp" 2>/dev/null; \
      jq -r '.ipv6_addresses[]?'     "$tmp" 2>/dev/null; } \
        | grep -E '^[0-9]|^[0-9a-fA-F:]' | sort -u > "$dest"
    rm -f "$tmp"
}

# Download and merge provider IP list; set PROVIDER_V4_FILE / PROVIDER_V6_FILE
download_provider_ips() {
    local provider="$1"
    local v4_file="${IP_LIST_DIR}/${provider}_v4.txt"
    local v6_file="${IP_LIST_DIR}/${provider}_v6.txt"
    mkdir -p "$IP_LIST_DIR"

    case "$provider" in
        cloudflare)
            print_info "下载 Cloudflare IPs... / Downloading Cloudflare IPs..."
            download_text "$CLOUDFLARE_V4_URL" "$v4_file" \
                || { print_warning "Cloudflare IPv4 下载失败 / download failed"; return 1; }
            if [[ "$ENABLE_IPV6" == true ]]; then
                download_text "$CLOUDFLARE_V6_URL" "$v6_file" \
                    || print_warning "Cloudflare IPv6 下载失败 / download failed"
            fi
            ;;
        fastly)
            print_info "下载 Fastly IPs... / Downloading Fastly IPs..."
            local tmp_all; tmp_all=$(mktemp)
            download_fastly_json "$tmp_all" \
                || { print_warning "Fastly 下载失败 / download failed"; rm -f "$tmp_all"; return 1; }
            grep -E '^[0-9]' "$tmp_all" | sort -u > "$v4_file" || true
            if [[ "$ENABLE_IPV6" == true ]]; then
                grep -E '^[0-9a-fA-F:]' "$tmp_all" | sort -u > "$v6_file" || true
            fi
            rm -f "$tmp_all"
            ;;
        akamai)
            print_info "下载 Akamai IPs... / Downloading Akamai IPs..."
            local tmp_all; tmp_all=$(mktemp)
            download_text "$AKAMAI_URL" "$tmp_all" \
                || { print_warning "Akamai 下载失败 / download failed"; rm -f "$tmp_all"; return 1; }
            grep -E '^[0-9]' "$tmp_all" | sort -u > "$v4_file" || true
            if [[ "$ENABLE_IPV6" == true ]]; then
                grep -E '^[0-9a-fA-F:]' "$tmp_all" | sort -u > "$v6_file" || true
            fi
            rm -f "$tmp_all"
            ;;
    esac

    local v4_count=0 v6_count=0
    [[ -f "$v4_file" ]] && v4_count=$(wc -l < "$v4_file")
    [[ -f "$v6_file" ]] && v6_count=$(wc -l < "$v6_file")
    print_success "${provider}: IPv4 ${v4_count} 条 / entries, IPv6 ${v6_count} 条 / entries"
}

# ── ipset / iptables helpers / 规则管理 ───────────────────────────────────────

ipset_name_v4() { echo "${1^^}_BLOCK_V4"; }
ipset_name_v6() { echo "${1^^}_BLOCK_V6"; }
chain_name()    { echo "${1^^}_BLOCK"; }

ensure_drop_rules() {
    local chain="$1" ipset="$2" family="$3"
    local ipt="iptables"; [[ "$family" == "inet6" ]] && ipt="ip6tables"

    # Create chain if needed
    if ! $ipt -L "$chain" &>/dev/null 2>&1; then
        $ipt -N "$chain"
    fi
    # Add DROP rule inside chain (idempotent)
    if ! $ipt -C "$chain" -m set --match-set "$ipset" dst -j DROP 2>/dev/null; then
        $ipt -A "$chain" -m set --match-set "$ipset" dst -j DROP
    fi
    if ! $ipt -C "$chain" -m set --match-set "$ipset" src -j DROP 2>/dev/null; then
        $ipt -A "$chain" -m set --match-set "$ipset" src -j DROP
    fi
    # Hook chain into INPUT and OUTPUT
    for hook in INPUT OUTPUT; do
        if ! $ipt -C "$hook" -j "$chain" 2>/dev/null; then
            $ipt -I "$hook" 1 -j "$chain"
        fi
    done
}

load_ipset_from_file() {
    local setname="$1" file="$2" family="$3"
    [[ -f "$file" && -s "$file" ]] || return 0

    local type="hash:net"
    ipset create "$setname" "$type" family "$family" -exist
    ipset flush  "$setname"

    while IFS= read -r ip; do
        [[ -z "$ip" ]] && continue
        ipset add "$setname" "$ip" -exist 2>/dev/null || true
    done < "$file"
}

apply_provider_rules() {
    local provider="$1"
    local v4_file="${IP_LIST_DIR}/${provider}_v4.txt"
    local v6_file="${IP_LIST_DIR}/${provider}_v6.txt"
    local ipset_v4; ipset_v4=$(ipset_name_v4 "$provider")
    local ipset_v6; ipset_v6=$(ipset_name_v6 "$provider")
    local chain;    chain=$(chain_name "$provider")

    if [[ -f "$v4_file" && -s "$v4_file" ]]; then
        load_ipset_from_file "$ipset_v4" "$v4_file" "inet"
        ensure_drop_rules "$chain" "$ipset_v4" "inet"
    fi

    if [[ "$ENABLE_IPV6" == true && -f "$v6_file" && -s "$v6_file" ]]; then
        load_ipset_from_file "$ipset_v6" "$v6_file" "inet6"
        ensure_drop_rules "$chain" "$ipset_v6" "inet6"
    fi

    print_success "${provider} 封锁规则已应用 / block rules applied"
}

remove_provider_rules() {
    local provider="$1"
    local ipset_v4; ipset_v4=$(ipset_name_v4 "$provider")
    local ipset_v6; ipset_v6=$(ipset_name_v6 "$provider")
    local chain;    chain=$(chain_name "$provider")

    for hook in INPUT OUTPUT; do
        iptables  -D "$hook" -j "$chain" 2>/dev/null || true
        ip6tables -D "$hook" -j "$chain" 2>/dev/null || true
    done
    iptables  -F "$chain" 2>/dev/null || true
    iptables  -X "$chain" 2>/dev/null || true
    ip6tables -F "$chain" 2>/dev/null || true
    ip6tables -X "$chain" 2>/dev/null || true

    ipset destroy "$ipset_v4" 2>/dev/null || true
    ipset destroy "$ipset_v6" 2>/dev/null || true

    rm -f "${IP_LIST_DIR}/${provider}_v4.txt" "${IP_LIST_DIR}/${provider}_v6.txt"
    print_success "${provider} 规则已移除 / rules removed"
}

save_rules() {
    mkdir -p /etc/iptables
    iptables-save  > /etc/iptables/rules.v4 2>/dev/null || true
    ip6tables-save > /etc/iptables/rules.v6 2>/dev/null || true
    ipset save     > /etc/iptables/ipset.rules 2>/dev/null || true
}

# ── Status / 状态显示 ─────────────────────────────────────────────────────────
show_provider_status() {
    local provider="$1"
    local ipset_v4; ipset_v4=$(ipset_name_v4 "$provider")
    local chain;    chain=$(chain_name "$provider")

    local count=0
    if ipset list -n 2>/dev/null | grep -Fxq "$ipset_v4"; then
        count=$(ipset list "$ipset_v4" 2>/dev/null \
            | awk -F': ' '/Number of entries:/ {print $2}')
    fi

    local hooked="否/No"
    iptables -C INPUT -j "$chain" 2>/dev/null && hooked="是/Yes"

    printf "  %-12s  IPv4 %6s 条/entries  已挂载/Hooked: %s\n" \
        "$provider" "${count:-0}" "$hooked"
}

show_status() {
    echo ""
    echo "══════════════════════════════════════════"
    echo "  CDN IP 封锁状态 / CDN Block Status"
    echo "══════════════════════════════════════════"
    for p in cloudflare fastly akamai; do
        show_provider_status "$p"
    done
    echo ""
}

# ── Main commands / 主命令 ────────────────────────────────────────────────────
install_blocking() {
    print_info "安装 CDN IP 封锁规则... / Installing CDN IP blocking..."
    check_dependencies
    mkdir -p "$IP_LIST_DIR"

    local providers; providers=$(get_provider_list)
    local applied=0 failed=0

    for p in $providers; do
        if download_provider_ips "$p" && apply_provider_rules "$p"; then
            applied=$((applied + 1))
        else
            failed=$((failed + 1))
        fi
    done

    save_rules
    echo ""
    print_success "安装完成 / Done: ${applied} 个成功 / succeeded, ${failed} 个失败 / failed"
    print_info "查看状态 / Check status: sudo cdn-ip-ban status"
}

uninstall_blocking() {
    print_info "卸载 CDN IP 封锁规则... / Uninstalling CDN IP blocking..."

    local providers; providers=$(get_provider_list)
    for p in $providers; do
        remove_provider_rules "$p"
    done

    # Clean up IP list dir if empty
    if [[ -d "$IP_LIST_DIR" ]] && [[ -z "$(ls -A "$IP_LIST_DIR" 2>/dev/null)" ]]; then
        rmdir "$IP_LIST_DIR"
    fi

    save_rules
    print_success "卸载完成 / Uninstall complete"
}

update_blocking() {
    print_info "更新 CDN IP 列表... / Updating CDN IP lists..."
    local providers; providers=$(get_provider_list)
    for p in $providers; do
        download_provider_ips "$p" && apply_provider_rules "$p" || true
    done
    save_rules
    print_success "更新完成 / Update complete"
}

# ── CLI / 命令行解析 ──────────────────────────────────────────────────────────
show_usage() {
    cat << EOF

用法 / Usage:
  sudo cdn-ip-ban <command> [options]

命令 / Commands:
  install    下载 IP 列表并应用 iptables 封锁规则
             Download IP lists and apply iptables block rules
  uninstall  移除所有封锁规则和 ipset
             Remove all block rules and ipsets
  update     重新下载 IP 列表并刷新规则
             Re-download IP lists and refresh rules
  status     显示当前封锁状态
             Show current block status

选项 / Options:
  --provider=PROVIDER   cloudflare | fastly | akamai | all  (默认/default: all)
  --ipv6                同时封锁 IPv6 / Also block IPv6

示例 / Examples:
  sudo cdn-ip-ban install
  sudo cdn-ip-ban install --provider=cloudflare --ipv6
  sudo cdn-ip-ban uninstall --provider=fastly
  sudo cdn-ip-ban status

EOF
}

parse_arguments() {
    local cmd="${1:-help}"
    shift || true

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --provider=*)
                SELECTED_PROVIDERS="${1#*=}"
                if [[ "$SELECTED_PROVIDERS" != "all" ]]; then
                    validate_provider "$SELECTED_PROVIDERS"
                fi
                ;;
            --ipv6)
                ENABLE_IPV6=true
                ;;
            --help|-h)
                show_usage; exit 0
                ;;
            *)
                print_error "未知参数 / Unknown option: $1"
                show_usage; exit 1
                ;;
        esac
        shift
    done

    case "$cmd" in
        install)   check_root; acquire_lock; install_blocking   ;;
        uninstall) check_root; acquire_lock; uninstall_blocking ;;
        update)    check_root; acquire_lock; update_blocking    ;;
        status)    show_status                                  ;;
        help|--help|-h) show_usage                             ;;
        *)
            print_error "未知命令 / Unknown command: $cmd"
            show_usage; exit 1
            ;;
    esac
}

parse_arguments "$@"
