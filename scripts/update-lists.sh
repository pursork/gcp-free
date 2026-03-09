#!/usr/bin/env bash
# update-lists.sh — Fetch upstream CDN IP lists and update lists/ directory
# Called by GitHub Actions daily. Can also be run locally.
#
# Usage:
#   bash scripts/update-lists.sh [provider_name]
#   # With no argument, processes all providers/*.conf

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROVIDERS_DIR="${REPO_ROOT}/providers"
LISTS_DIR="${REPO_ROOT}/lists"

mkdir -p "$LISTS_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()     { echo -e "${RED}[ERR]${NC}   $*" >&2; }

fetch_url() {
    local url="$1" dest="$2"
    curl -fsSL --connect-timeout 20 --max-time 60 "$url" -o "$dest" 2>/dev/null
}

filter_ipv4() { grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]+)?$' | sort -u; }
filter_ipv6() { grep -E '^[0-9a-fA-F:]+(/[0-9]+)?$' | grep ':' | sort -u; }

update_if_changed() {
    local new="$1" dest="$2" label="$3"
    local new_count; new_count=$(wc -l < "$new")
    if [[ "$new_count" -eq 0 ]]; then
        warn "${label}: empty result, skipping update"
        rm -f "$new"; return 1
    fi
    if [[ -f "$dest" ]] && diff -q "$new" "$dest" &>/dev/null; then
        ok "${label}: no change (${new_count} entries)"
        rm -f "$new"; return 0
    fi
    mv "$new" "$dest"
    ok "${label}: updated → ${new_count} entries"
    return 0
}

process_provider() {
    local conf="$1"
    # Reset variables before sourcing
    PROVIDER_NAME="" PROVIDER_FORMAT="" \
    PROVIDER_IPV4_URL="" PROVIDER_IPV6_URL="" \
    PROVIDER_IPV4_JQ="" PROVIDER_IPV6_JQ=""

    # shellcheck source=/dev/null
    source "$conf"

    local slug; slug=$(basename "$conf" .conf)
    info "Processing ${PROVIDER_NAME} (${slug})..."

    local tmp_v4; tmp_v4=$(mktemp)
    local tmp_v6; tmp_v6=$(mktemp)
    local raw;    raw=$(mktemp)

    case "$PROVIDER_FORMAT" in
        text)
            # IPv4
            if [[ -n "${PROVIDER_IPV4_URL:-}" ]]; then
                if fetch_url "$PROVIDER_IPV4_URL" "$raw"; then
                    filter_ipv4 < "$raw" > "$tmp_v4" || true
                    update_if_changed "$tmp_v4" "${LISTS_DIR}/${slug}_v4.txt" "${PROVIDER_NAME} IPv4" || true
                else
                    warn "${PROVIDER_NAME}: IPv4 fetch failed"; rm -f "$tmp_v4"
                fi
            fi
            # IPv6
            if [[ -n "${PROVIDER_IPV6_URL:-}" ]]; then
                if fetch_url "$PROVIDER_IPV6_URL" "$raw"; then
                    filter_ipv6 < "$raw" > "$tmp_v6" || true
                    update_if_changed "$tmp_v6" "${LISTS_DIR}/${slug}_v6.txt" "${PROVIDER_NAME} IPv6" || true
                else
                    warn "${PROVIDER_NAME}: IPv6 fetch failed"; rm -f "$tmp_v6"
                fi
            fi
            ;;

        fastly_json)
            local jq_v4="${PROVIDER_IPV4_JQ:-.addresses[]}"
            local jq_v6="${PROVIDER_IPV6_JQ:-.ipv6_addresses[]}"
            if fetch_url "${PROVIDER_IPV4_URL}" "$raw"; then
                jq -r "$jq_v4" "$raw" 2>/dev/null | filter_ipv4 > "$tmp_v4" || true
                update_if_changed "$tmp_v4" "${LISTS_DIR}/${slug}_v4.txt" "${PROVIDER_NAME} IPv4" || true
                jq -r "$jq_v6" "$raw" 2>/dev/null | filter_ipv6 > "$tmp_v6" || true
                update_if_changed "$tmp_v6" "${LISTS_DIR}/${slug}_v6.txt" "${PROVIDER_NAME} IPv6" || true
            else
                warn "${PROVIDER_NAME}: fetch failed"; rm -f "$tmp_v4" "$tmp_v6"
            fi
            ;;

        *)
            err "${slug}: unknown FORMAT '${PROVIDER_FORMAT}', skipping"
            ;;
    esac

    rm -f "$raw" "$tmp_v4" "$tmp_v6" 2>/dev/null || true
}

# ── Main ──────────────────────────────────────────────────────────────────────
if [[ ! -d "$PROVIDERS_DIR" ]]; then
    err "providers/ directory not found: $PROVIDERS_DIR"
    exit 1
fi

TARGET="${1:-}"

for conf in "${PROVIDERS_DIR}"/*.conf; do
    [[ -f "$conf" ]] || continue
    slug=$(basename "$conf" .conf)
    if [[ -n "$TARGET" && "$slug" != "$TARGET" ]]; then
        continue
    fi
    process_provider "$conf"
done

echo ""
info "lists/ directory contents:"
ls -lh "${LISTS_DIR}"/*.txt 2>/dev/null || echo "  (no list files yet)"
