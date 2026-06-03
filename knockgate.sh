#!/usr/bin/env bash
set -euo pipefail

# KnockGate: sequential UDP port knocking + nftables timeout allowlist.
# Protective overlay mode: do not rewrite the existing firewall. KnockGate only
# pre-filters protected TCP ports; all other traffic is left to the existing
# firewall unchanged.

APP_NAME="KnockGate"
INSTALL_PATH="/usr/local/bin/knockgate"
CONFIG_DIR="/etc/knockgate"
CONFIG_FILE="${CONFIG_DIR}/knockgate.conf"
BACKUP_DIR="${CONFIG_DIR}/backups"
README_FILE="${CONFIG_DIR}/README"
KNOCKGATE_NFT_CONF="${CONFIG_DIR}/knockgate.nft"
KNOCKGATE_NFT_SERVICE="/etc/systemd/system/knockgate-nft.service"
KNOCKD_CONF="/etc/knockd.conf"
KNOCKD_DEFAULT="/etc/default/knockd"
KNOCKD_OVERRIDE_DIR="/etc/systemd/system/knockd.service.d"
KNOCKD_OVERRIDE_CONF="${KNOCKD_OVERRIDE_DIR}/override.conf"

NFT_TABLE_FAMILY="inet"
NFT_TABLE_NAME="knockgate"
NFT_SET_NAME="knock_allow_temp_v4"
MODE="protective_overlay"

DEFAULT_PROTECTED_PORTS="5432"
DEFAULT_KNOCK_PORTS="38127,19452,47219,26083"
DEFAULT_OPEN_TIMEOUT="12h"
DEFAULT_SEQ_TIMEOUT="10"
DEFAULT_SSH_PORT="22"

PROTECTED_PORTS="${DEFAULT_PROTECTED_PORTS}"
KNOCK_PORTS="${DEFAULT_KNOCK_PORTS}"
OPEN_TIMEOUT="${DEFAULT_OPEN_TIMEOUT}"
SEQ_TIMEOUT="${DEFAULT_SEQ_TIMEOUT}"
SSH_PORT="${DEFAULT_SSH_PORT}"
INTERFACE=""

OS_ID=""
OS_VERSION_ID=""
OS_ID_LIKE=""
PKG_FAMILY=""
NFT_BIN=""
KNOCKD_BIN=""
UI_LANG="${KNOCKGATE_LANG:-}"

COLOR_RESET=""
COLOR_BOLD=""
COLOR_DIM=""
COLOR_RED=""
COLOR_GREEN=""
COLOR_YELLOW=""
COLOR_BLUE=""
COLOR_CYAN=""
COLOR_MAGENTA=""

setup_colors() {
    if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
        COLOR_RESET=$'\033[0m'
        COLOR_BOLD=$'\033[1m'
        COLOR_DIM=$'\033[2m'
        COLOR_RED=$'\033[31m'
        COLOR_GREEN=$'\033[32m'
        COLOR_YELLOW=$'\033[33m'
        COLOR_BLUE=$'\033[34m'
        COLOR_CYAN=$'\033[36m'
        COLOR_MAGENTA=$'\033[35m'
    fi
}

tr_text() {
    local zh="$1"
    local en="$2"
    if [[ "${UI_LANG}" == "en" ]]; then
        printf '%s' "${en}"
    else
        printf '%s' "${zh}"
    fi
}

color_text() {
    local color="$1"
    shift
    printf '%s%s%s' "${color}" "$*" "${COLOR_RESET}"
}

info() {
    color_text "${COLOR_CYAN}" "$*"
    printf '\n'
}

success() {
    color_text "${COLOR_GREEN}" "$*"
    printf '\n'
}

warn() {
    color_text "${COLOR_YELLOW}" "$*"
    printf '\n'
}

danger() {
    color_text "${COLOR_RED}${COLOR_BOLD}" "$*"
    printf '\n'
}

heading() {
    color_text "${COLOR_BOLD}${COLOR_CYAN}" "$*"
    printf '\n'
}

choose_language() {
    setup_colors

    case "${UI_LANG}" in
        zh|en) return 0 ;;
        "") ;;
        *) UI_LANG="" ;;
    esac

    echo
    heading "KnockGate"
    echo "1. 中文"
    echo "2. English"
    local choice
    read -r -p "$(color_text "${COLOR_MAGENTA}" "请选择语言 / Select language [1]: ")" choice
    case "${choice:-1}" in
        2|en|EN|English|english) UI_LANG="en" ;;
        *) UI_LANG="zh" ;;
    esac
}

log() {
    success "[${APP_NAME}] $*"
}

die() {
    danger "[${APP_NAME}] $(tr_text "错误：" "ERROR:") $*" >&2
    exit 1
}

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        die "请使用 root 权限运行，例如：sudo $0"
    fi
}

timestamp() {
    date +"%Y%m%d-%H%M%S"
}

ensure_dirs() {
    mkdir -p "${CONFIG_DIR}" "${BACKUP_DIR}"
}

backup_file() {
    local file="$1"
    local base
    local dest

    ensure_dirs
    if [[ -e "${file}" ]]; then
        base="$(basename "${file}")"
        dest="${BACKUP_DIR}/${base}.$(timestamp).bak"
        cp -a "${file}" "${dest}"
        log "已备份 ${file} -> ${dest}"
    fi
}

prompt_default() {
    local prompt="$1"
    local default="$2"
    local value

    read -r -p "$(color_text "${COLOR_MAGENTA}" "${prompt} [${default}]: ")" value
    if [[ -z "${value}" ]]; then
        printf '%s\n' "${default}"
    else
        printf '%s\n' "${value}"
    fi
}

confirm_yes_no() {
    local prompt="$1"
    local default="${2:-no}"
    local suffix
    local answer

    case "${default}" in
        yes) suffix="[Y/n]" ;;
        no) suffix="[y/N]" ;;
        *) die "无效确认默认值： ${default}" ;;
    esac

    read -r -p "$(color_text "${COLOR_MAGENTA}" "${prompt} ${suffix}: ")" answer
    answer="${answer:-${default}}"
    case "${answer}" in
        y|Y|yes|YES) return 0 ;;
        n|N|no|NO) return 1 ;;
        *) return 1 ;;
    esac
}

require_upper_yes() {
    local prompt="$1"
    local answer

    read -r -p "$(color_text "${COLOR_RED}${COLOR_BOLD}" "${prompt} $(tr_text "输入 YES 继续：" "Type YES to continue: ")")" answer
    [[ "${answer}" == "YES" ]]
}

detect_os() {
    if [[ ! -r /etc/os-release ]]; then
        die "不支持的 Linux 发行版：未找到 /etc/os-release。"
    fi

    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-}"
    OS_VERSION_ID="${VERSION_ID:-}"
    OS_ID_LIKE="${ID_LIKE:-}"

    case "${OS_ID}" in
        debian|ubuntu)
            PKG_FAMILY="apt"
            ;;
        rocky|almalinux|centos|rhel|fedora)
            PKG_FAMILY="dnf"
            ;;
        arch)
            PKG_FAMILY="pacman"
            ;;
        *)
            if [[ " ${OS_ID_LIKE} " == *" debian "* ]]; then
                PKG_FAMILY="apt"
            elif [[ " ${OS_ID_LIKE} " == *" rhel "* || " ${OS_ID_LIKE} " == *" fedora "* ]]; then
                PKG_FAMILY="dnf"
            elif [[ " ${OS_ID_LIKE} " == *" arch "* ]]; then
                PKG_FAMILY="pacman"
            else
                die "不支持的 Linux 发行版：ID=${OS_ID}, ID_LIKE=${OS_ID_LIKE}。"
            fi
            ;;
    esac

    case "${OS_ID}" in
        debian)
            case "${OS_VERSION_ID%%.*}" in
                11|12|13) ;;
                *) die "不支持的 Debian 版本：${OS_VERSION_ID}。支持：11/12/13。" ;;
            esac
            ;;
        ubuntu)
            case "${OS_VERSION_ID}" in
                20.04|22.04|24.04) ;;
                *) die "不支持的 Ubuntu 版本：${OS_VERSION_ID}。支持：20.04/22.04/24.04。" ;;
            esac
            ;;
        rocky|almalinux)
            case "${OS_VERSION_ID%%.*}" in
                8|9) ;;
                *) die "不支持的 ${OS_ID} 版本：${OS_VERSION_ID}。支持：8/9。" ;;
            esac
            ;;
        centos)
            case "${OS_VERSION_ID%%.*}" in
                8|9) ;;
                *) die "不支持的 CentOS 版本：${OS_VERSION_ID}。支持：Stream 8/9。" ;;
            esac
            ;;
        rhel)
            case "${OS_VERSION_ID%%.*}" in
                8|9) ;;
                *) die "不支持的 RHEL-like 版本：${OS_VERSION_ID}。支持目标：8/9 克隆版或 Fedora 38+。" ;;
            esac
            ;;
        fedora)
            if [[ "${OS_VERSION_ID%%.*}" -lt 38 ]]; then
                die "不支持的 Fedora 版本：${OS_VERSION_ID}。支持：Fedora 38+。"
            fi
            ;;
        arch)
            ;;
    esac

    log "检测到系统： ${OS_ID} ${OS_VERSION_ID} (${PKG_FAMILY})"
}

install_packages() {
    if command -v nft >/dev/null 2>&1 && command -v knockd >/dev/null 2>&1 && command -v ip >/dev/null 2>&1 && command -v qrencode >/dev/null 2>&1; then
        log "依赖命令已存在，跳过包管理器安装。"
        refresh_binaries
        return 0
    fi

    detect_os

    if command -v nft >/dev/null 2>&1 && command -v knockd >/dev/null 2>&1 && command -v ip >/dev/null 2>&1 && ! command -v qrencode >/dev/null 2>&1; then
        log "核心依赖已存在，正在安装二维码工具 qrencode。"
        case "${PKG_FAMILY}" in
            apt)
                if ! DEBIAN_FRONTEND=noninteractive apt-get install -y qrencode; then
                    apt-get update
                    DEBIAN_FRONTEND=noninteractive apt-get install -y qrencode || warn "qrencode 安装失败，二维码菜单仍会输出协议 URL。"
                fi
                ;;
            dnf)
                dnf install -y qrencode || warn "qrencode 安装失败，二维码菜单仍会输出协议 URL。"
                ;;
            pacman)
                pacman -Sy --noconfirm qrencode || warn "qrencode 安装失败，二维码菜单仍会输出协议 URL。"
                ;;
        esac
        refresh_binaries
        return 0
    fi

    log "正在安装依赖：nftables、knockd/knock-server、iproute2/iproute、qrencode。"
    case "${PKG_FAMILY}" in
        apt)
            apt-get update
            DEBIAN_FRONTEND=noninteractive apt-get install -y nftables knockd iproute2 qrencode
            ;;
        dnf)
            dnf install -y nftables iproute qrencode || dnf install -y nftables iproute
            if ! dnf install -y knock-server; then
                log "Package knock-server not available, trying knockd."
                if ! dnf install -y knockd; then
                    die "无法安装 knockd 包。请启用对应软件源或手动安装 knockd 后重试。"
                fi
            fi
            ;;
        pacman)
            pacman -Sy --noconfirm nftables knockd iproute2 qrencode
            ;;
        *)
            die "不支持的包管理类型：${PKG_FAMILY}"
            ;;
    esac

    refresh_binaries
}

refresh_binaries() {
    NFT_BIN="$(command -v nft || true)"
    KNOCKD_BIN="$(command -v knockd || true)"

    if [[ -z "${NFT_BIN}" ]]; then
        die "未找到 nft 命令。请安装 nftables 后重试。"
    fi
    if [[ -z "${KNOCKD_BIN}" ]]; then
        die "未找到 knockd 命令。请安装 knockd/knock-server 后重试。"
    fi
}

detect_interface() {
    local detected

    if ! command -v ip >/dev/null 2>&1; then
        echo "未找到 ip 命令，请手动输入网卡名。"
        INTERFACE="$(prompt_default "请输入 knockd 要监听的网卡名" "${INTERFACE:-eth0}")"
        return 0
    fi

    detected="$(ip -4 route show default 0.0.0.0/0 2>/dev/null | awk '
        {
            for (i = 1; i <= NF; i++) {
                if ($i == "dev" && (i + 1) <= NF) {
                    print $(i + 1)
                    exit
                }
            }
        }
    ')"

    if [[ -n "${detected}" ]]; then
        INTERFACE="${detected}"
        log "检测到默认出口网卡： ${INTERFACE}"
    else
        echo "无法检测默认出口网卡。"
        INTERFACE="$(prompt_default "请输入 knockd 要监听的网卡名" "${INTERFACE:-eth0}")"
    fi
}

load_config() {
    if [[ -r "${CONFIG_FILE}" ]]; then
        # shellcheck disable=SC1090
        . "${CONFIG_FILE}"
    fi

    PROTECTED_PORTS="${PROTECTED_PORTS:-${DEFAULT_PROTECTED_PORTS}}"
    KNOCK_PORTS="${KNOCK_PORTS:-${DEFAULT_KNOCK_PORTS}}"
    OPEN_TIMEOUT="${OPEN_TIMEOUT:-${DEFAULT_OPEN_TIMEOUT}}"
    SEQ_TIMEOUT="${SEQ_TIMEOUT:-${DEFAULT_SEQ_TIMEOUT}}"
    SSH_PORT="${SSH_PORT:-${DEFAULT_SSH_PORT}}"
    INTERFACE="${INTERFACE:-}"
    MODE="protective_overlay"
}

save_config() {
    ensure_dirs
    backup_file "${CONFIG_FILE}"
cat > "${CONFIG_FILE}" <<EOF
PROTECTED_PORTS="${PROTECTED_PORTS}"
KNOCK_PORTS="${KNOCK_PORTS}"
OPEN_TIMEOUT="${OPEN_TIMEOUT}"
SEQ_TIMEOUT=${SEQ_TIMEOUT}
SSH_PORT=${SSH_PORT}
INTERFACE="${INTERFACE}"
MODE="protective_overlay"
EOF
    chmod 600 "${CONFIG_FILE}"
    log "已写入 ${CONFIG_FILE}"
}

is_uint() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

is_port() {
    local value="$1"
    is_uint "${value}" && (( value >= 1 && value <= 65535 ))
}

normalize_ports() {
    local input="$1"
    local mode="${2:-set}"
    local cleaned
    local token
    local -a parts=()
    local -a result=()
    local -A seen=()

    cleaned="$(printf '%s' "${input}" | tr ' ' ',' | tr -s ',')"
    cleaned="${cleaned#,}"
    cleaned="${cleaned%,}"

    if [[ -z "${cleaned}" ]]; then
        return 1
    fi

    IFS=',' read -r -a parts <<< "${cleaned}"
    for token in "${parts[@]}"; do
        token="${token//$'\t'/}"
        token="${token//$'\n'/}"
        [[ -z "${token}" ]] && continue
        if ! is_port "${token}"; then
            echo "无效端口： ${token}" >&2
            return 1
        fi
        if [[ -n "${seen[${token}]:-}" ]]; then
            if [[ "${mode}" == "sequence" ]]; then
                echo "敲门序列端口不允许重复： ${token}" >&2
                return 1
            fi
            continue
        fi
        seen["${token}"]=1
        result+=("${token}")
    done

    if [[ "${#result[@]}" -eq 0 ]]; then
        return 1
    fi

    local joined=""
    for token in "${result[@]}"; do
        if [[ -z "${joined}" ]]; then
            joined="${token}"
        else
            joined="${joined},${token}"
        fi
    done
    printf '%s\n' "${joined}"
}

list_contains_port() {
    local list="$1"
    local needle="$2"
    local item
    local -a items=()

    IFS=',' read -r -a items <<< "${list}"
    for item in "${items[@]}"; do
        if [[ "${item}" == "${needle}" ]]; then
            return 0
        fi
    done
    return 1
}

add_port_to_list() {
    local list="$1"
    local port="$2"

    if [[ -z "${list}" ]]; then
        printf '%s\n' "${port}"
        return 0
    fi

    if list_contains_port "${list}" "${port}"; then
        printf '%s\n' "${list}"
    else
        printf '%s,%s\n' "${list}" "${port}"
    fi
}

overlap_ports() {
    local left="$1"
    local right="$2"
    local item
    local overlaps=""
    local -a left_items=()

    IFS=',' read -r -a left_items <<< "${left}"
    for item in "${left_items[@]}"; do
        if list_contains_port "${right}" "${item}"; then
            if [[ -z "${overlaps}" ]]; then
                overlaps="${item}"
            else
                overlaps="${overlaps},${item}"
            fi
        fi
    done

    printf '%s\n' "${overlaps}"
}

join_port_lists() {
    local list
    local token
    local joined=""
    local -a join_items=()
    local -A seen=()

    for list in "$@"; do
        [[ -z "${list}" ]] && continue
        IFS=',' read -r -a join_items <<< "${list}"
        for token in "${join_items[@]}"; do
            [[ -z "${token}" ]] && continue
            is_port "${token}" || continue
            [[ -n "${seen[${token}]:-}" ]] && continue
            seen["${token}"]=1
            if [[ -z "${joined}" ]]; then
                joined="${token}"
            else
                joined="${joined},${token}"
            fi
        done
    done

    printf '%s\n' "${joined}"
}

extract_port_from_addr() {
    local addr="$1"

    addr="${addr%]}"
    printf '%s\n' "${addr##*:}"
}

detect_ssh_port() {
    local port=""
    local addr

    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        # SSH_CONNECTION: client_ip client_port server_ip server_port
        port="$(awk '{print $4}' <<< "${SSH_CONNECTION}")"
        if is_port "${port}"; then
            printf '%s\n' "${port}"
            return 0
        fi
    fi

    if [[ -n "${SSH_CLIENT:-}" ]]; then
        # SSH_CLIENT: client_ip client_port server_port
        port="$(awk '{print $3}' <<< "${SSH_CLIENT}")"
        if is_port "${port}"; then
            printf '%s\n' "${port}"
            return 0
        fi
    fi

    if command -v ss >/dev/null 2>&1; then
        while read -r addr; do
            port="$(extract_port_from_addr "${addr}")"
            if is_port "${port}"; then
                printf '%s\n' "${port}"
                return 0
            fi
        done < <(ss -H -ltnp 2>/dev/null | awk '/sshd/ {print $4}')
    fi

    printf '%s\n' "${SSH_PORT:-${DEFAULT_SSH_PORT}}"
}

detect_nft_accept_ports() {
    local proto="$1"

    command -v nft >/dev/null 2>&1 || return 0

    nft list ruleset 2>/dev/null | awk \
        -v proto="${proto}" \
        -v kg_family="${NFT_TABLE_FAMILY}" \
        -v kg_table="${NFT_TABLE_NAME}" '
        function brace_delta(s,    opens, closes) {
            opens = gsub(/{/, "{", s)
            closes = gsub(/}/, "}", s)
            return opens - closes
        }
        {
            line = $0
            if (line ~ "^[ \t]*table[ \t]+" kg_family "[ \t]+" kg_table "[ \t]*[{]") {
                in_knockgate = 1
                depth = brace_delta(line)
                next
            }
            if (in_knockgate) {
                depth += brace_delta(line)
                if (depth <= 0) {
                    in_knockgate = 0
                    depth = 0
                }
                next
            }
            if (line ~ /ip saddr @knock_allow_temp_v4/) next
            marker = proto " dport"
            pos = index(line, marker)
            if (pos == 0 || line !~ /accept/) next
            rest = substr(line, pos + length(marker))
            sub(/^[ \t]+/, "", rest)
            sub(/[ \t](counter|accept|jump|return|drop|reject).*$/, "", rest)
            gsub(/[{}]/, "", rest)
            gsub(/,/, " ", rest)
            n = split(rest, parts, /[ \t]+/)
            for (i = 1; i <= n; i++) {
                if (parts[i] ~ /^[0-9]+$/ && parts[i] >= 1 && parts[i] <= 65535) print parts[i]
            }
        }
    ' | sort -n -u | paste -sd, -
}

detect_listening_ports_all() {
    command -v ss >/dev/null 2>&1 || return 0

    ss -H -ltun 2>/dev/null | awk '
        {
            addr = $5
            if (addr == "") addr = $4
            gsub(/\\]$/, "", addr)
            n = split(addr, parts, ":")
            port = parts[n]
            if (port ~ /^[0-9]+$/ && port >= 1 && port <= 65535) print port
        }
    ' | sort -n -u | paste -sd, -
}

random_port() {
    local value

    if [[ -r /dev/urandom ]]; then
        value="$(od -An -N2 -tu2 /dev/urandom | tr -d ' ')"
    else
        value="${RANDOM}"
    fi
    echo $(( 20000 + (value % 45536) ))
}

roll_knock_ports() {
    local avoid="$1"
    local candidate
    local rolled=""
    local attempts=0
    local count=0

    while (( count < 6 )); do
        attempts=$((attempts + 1))
        if (( attempts > 1000 )); then
            die "无法生成 6 个可用敲门端口，请检查当前端口占用。"
        fi

        candidate="$(random_port)"
        if list_contains_port "${avoid}" "${candidate}" || list_contains_port "${rolled}" "${candidate}"; then
            continue
        fi

        rolled="$(join_port_lists "${rolled}" "${candidate}")"
        count=$((count + 1))
    done

    printf '%s\n' "${rolled}"
}

print_rolled_knock_summary() {
    local avoid="$1"

    echo
    heading "$(tr_text "已随机生成 6 个敲门端口：" "Rolled 6 random knock ports:")"
    echo "  ${KNOCK_PORTS}"
    echo
    info "$(tr_text "已避开：" "Avoided:")"
    echo "  - $(tr_text "当前防火墙 accept 端口" "current firewall accepted ports")"
    echo "  - $(tr_text "保护端口" "protected ports")"
    echo "  - $(tr_text "当前系统已监听 TCP/UDP 端口" "currently listening TCP/UDP ports")"
    echo
    warn "$(tr_text "你可以直接回车使用，也可以手动输入 6 个逗号分隔端口覆盖。" "Press Enter to use them, or enter 6 comma-separated ports to override.")"
}

validate_timeout() {
    [[ "$1" =~ ^[0-9]+(ms|s|m|h|d|w)?$ ]]
}

validate_positive_int() {
    is_uint "$1" && (( $1 > 0 ))
}

is_ipv4() {
    local ip="$1"
    local a b c d

    [[ "${ip}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS='.' read -r a b c d <<< "${ip}"
    for octet in "${a}" "${b}" "${c}" "${d}"; do
        is_uint "${octet}" || return 1
        (( octet >= 0 && octet <= 255 )) || return 1
    done
}

ports_to_nft_set() {
    local ports="$1"
    local spaced

    if [[ "${ports}" == *","* ]]; then
        spaced="$(printf '%s' "${ports}" | sed 's/,/, /g')"
        printf '{ %s }' "${spaced}"
    else
        printf '%s' "${ports}"
    fi
}

knock_ports_to_arrow() {
    printf '%s' "$1" | sed 's/,/ -> /g'
}

print_firewall_warning() {
    echo
    danger "========================================================================"
    danger "$(tr_text "警告：保护端口叠加模式" "WARNING: PROTECTIVE OVERLAY MODE")"
    danger "========================================================================"
    warn "$(tr_text "本脚本不会重写 /etc/nftables.conf，也不会 flush 现有防火墙规则。" "This script will not rewrite /etc/nftables.conf and will not flush existing firewall rules.")"
    warn "$(tr_text "KnockGate 只创建/替换自己的 table inet knockgate。" "KnockGate only creates/replaces its own table inet knockgate.")"
    warn "$(tr_text "只有你输入的保护端口会被 KnockGate 预先拦截；其他端口保持原防火墙行为不变。" "Only protected ports are pre-filtered by KnockGate; all other ports keep their existing firewall behavior.")"
    echo
    warn "$(tr_text "推荐：保护端口应在原防火墙/云安全组中本来可达，由 KnockGate 负责额外挡住未敲门来源。" "Recommended: protected ports should already be reachable in the existing firewall/cloud security group; KnockGate then blocks sources that have not knocked.")"
    warn "$(tr_text "如果原防火墙本来就丢弃保护端口，敲门后 KnockGate 也不会绕过原防火墙。" "If the existing firewall already drops a protected port, KnockGate will not bypass it after knocking.")"
    echo
    info "$(tr_text "继续前请确认：" "Before continuing, confirm:")"
    echo "  - $(tr_text "保护端口填写正确；" "protected ports are correct;")"
    echo "  - $(tr_text "原防火墙/云安全组没有继续阻断这些保护端口；" "the existing firewall/cloud security group does not still block those protected ports;")"
    echo "  - $(tr_text "如果这是远程服务器，云厂商控制台/救援方式可用。" "if this is remote, provider console/rescue access is available.")"
    danger "========================================================================"
}

print_config_summary() {
    echo
    heading "$(tr_text "配置摘要" "Configuration summary")"
    echo "$(tr_text "模式：仅保护端口叠加，不改原防火墙" "Mode: protective overlay, existing firewall unchanged")"
    echo "$(tr_text "需要敲门的保护端口：" "Protected ports requiring knock:") ${PROTECTED_PORTS}"
    echo "$(tr_text "UDP 敲门序列：" "UDP knock sequence:") $(knock_ports_to_arrow "${KNOCK_PORTS}")"
    echo "$(tr_text "开门时长：" "Open timeout:") ${OPEN_TIMEOUT}"
    echo "$(tr_text "序列超时：" "Sequence timeout:") ${SEQ_TIMEOUT}s"
    echo "$(tr_text "网卡：" "Interface:") ${INTERFACE}"
    echo
}

prompt_port_list() {
    local prompt="$1"
    local default="$2"
    local mode="${3:-set}"
    local raw
    local normalized

    while true; do
        raw="$(prompt_default "${prompt}" "${default}")"
        if normalized="$(normalize_ports "${raw}" "${mode}")"; then
            printf '%s\n' "${normalized}"
            return 0
        fi
        echo "请输入合法端口，例如：22,80,443"
    done
}

prompt_optional_port_list() {
    local prompt="$1"
    local default="$2"
    local raw
    local normalized

    while true; do
        raw="$(prompt_default "${prompt}" "${default}")"
        if [[ -z "${raw}" ]]; then
            printf '\n'
            return 0
        fi
        if normalized="$(normalize_ports "${raw}" "set")"; then
            printf '%s\n' "${normalized}"
            return 0
        fi
        echo "请输入合法端口，例如：53,51820，或留空。"
    done
}

prompt_firewall_config() {
    local used_ports
    local rolled_knock_ports
    local bad_knocks

    print_firewall_warning

    while true; do
        PROTECTED_PORTS="$(prompt_port_list "保护端口，敲门后开放" "${PROTECTED_PORTS:-${DEFAULT_PROTECTED_PORTS}}" "set")"

        used_ports="$(join_port_lists "$(detect_nft_accept_ports tcp || true)" "$(detect_nft_accept_ports udp || true)" "${PROTECTED_PORTS}" "$(detect_listening_ports_all || true)")"
        rolled_knock_ports="$(roll_knock_ports "${used_ports}")"
        KNOCK_PORTS="${rolled_knock_ports}"
        print_rolled_knock_summary "${used_ports}"

        while true; do
            KNOCK_PORTS="$(prompt_port_list "敲门序列端口" "${KNOCK_PORTS}" "sequence")"
            bad_knocks="$(overlap_ports "${KNOCK_PORTS}" "${used_ports}")"
            if [[ -n "${bad_knocks}" ]]; then
                echo "敲门端口不应和保护端口、已监听端口或现有防火墙 accept 端口重复。"
                echo "重复端口： ${bad_knocks}"
                echo "请重新输入敲门序列端口。"
                continue
            fi
            break
        done

        OPEN_TIMEOUT="$(prompt_default "开门时长" "${OPEN_TIMEOUT:-${DEFAULT_OPEN_TIMEOUT}}")"
        while ! validate_timeout "${OPEN_TIMEOUT}"; do
            echo "时间格式无效。请使用 30s、10m、12h、1d 这类格式。"
            OPEN_TIMEOUT="$(prompt_default "开门时长" "${DEFAULT_OPEN_TIMEOUT}")"
        done

        SEQ_TIMEOUT="$(prompt_default "敲门序列超时秒数" "${SEQ_TIMEOUT:-${DEFAULT_SEQ_TIMEOUT}}")"
        while ! validate_positive_int "${SEQ_TIMEOUT}"; do
            echo "序列超时无效，请输入正整数。"
            SEQ_TIMEOUT="$(prompt_default "敲门序列超时秒数" "${DEFAULT_SEQ_TIMEOUT}")"
        done

        detect_interface
        print_config_summary

        if require_upper_yes "应用此配置将只替换 KnockGate 自己的 nft table，不改原防火墙。"; then
            break
        fi

        echo "已取消，未应用任何防火墙变更。"
        return 1
    done
}

render_nft_overlay() {
    local output="$1"
    local protected_expr

    protected_expr="$(ports_to_nft_set "${PROTECTED_PORTS}")"

    cat > "${output}" <<EOF
#!${NFT_BIN} -f

# 由 KnockGate 管理。只包含 KnockGate 自己的保护表，不修改其他防火墙规则。

table ${NFT_TABLE_FAMILY} ${NFT_TABLE_NAME} {
    set ${NFT_SET_NAME} {
        type ipv4_addr
        flags timeout
    }

    chain input {
        type filter hook input priority -150; policy accept;

        # 保护端口：敲门成功来源放行；其他来源丢弃。
        ip saddr @${NFT_SET_NAME} tcp dport ${protected_expr} accept
        tcp dport ${protected_expr} drop

        # 其他流量不处理，交给原有防火墙。
    }
}
EOF
}

apply_nft() {
    local tmp
    local check_tmp

    refresh_binaries
    tmp="$(mktemp)"
    check_tmp="$(mktemp)"
    render_nft_overlay "${tmp}"

    log "正在检查生成的 KnockGate nftables 配置。"
    {
        if "${NFT_BIN}" list table "${NFT_TABLE_FAMILY}" "${NFT_TABLE_NAME}" >/dev/null 2>&1; then
            echo "delete table ${NFT_TABLE_FAMILY} ${NFT_TABLE_NAME}"
        fi
        cat "${tmp}"
    } > "${check_tmp}"
    "${NFT_BIN}" -c -f "${check_tmp}"
    rm -f "${check_tmp}"

    backup_file "${KNOCKGATE_NFT_CONF}"
    cp "${tmp}" "${KNOCKGATE_NFT_CONF}"
    chmod 600 "${KNOCKGATE_NFT_CONF}"

    log "正在替换 KnockGate 自己的 nft table；其他防火墙规则保持不变。"
    if "${NFT_BIN}" list table "${NFT_TABLE_FAMILY}" "${NFT_TABLE_NAME}" >/dev/null 2>&1; then
        "${NFT_BIN}" delete table "${NFT_TABLE_FAMILY}" "${NFT_TABLE_NAME}"
    fi
    "${NFT_BIN}" -f "${KNOCKGATE_NFT_CONF}"
    rm -f "${tmp}"

    log "KnockGate nftables 保护表已应用。"
}

render_knockd_conf() {
    refresh_binaries
    local sequence_expr

    sequence_expr="$(printf '%s' "${KNOCK_PORTS}" | awk -F, '{
        for (i = 1; i <= NF; i++) {
            printf "%s%s:udp", (i == 1 ? "" : ","), $i
        }
    }')"

    backup_file "${KNOCKD_CONF}"
    cat > "${KNOCKD_CONF}" <<EOF
[options]
    UseSyslog

[open-protected]
    sequence      = ${sequence_expr}
    seq_timeout   = ${SEQ_TIMEOUT}
EOF

    cat >> "${KNOCKD_CONF}" <<EOF
    command       = ${NFT_BIN} add element ${NFT_TABLE_FAMILY} ${NFT_TABLE_NAME} ${NFT_SET_NAME} { %IP% timeout ${OPEN_TIMEOUT} }
EOF
    chmod 600 "${KNOCKD_CONF}"
    log "已写入 ${KNOCKD_CONF}"
}

configure_knockd_service() {
    refresh_binaries

    if [[ -d "$(dirname "${KNOCKD_DEFAULT}")" ]]; then
        backup_file "${KNOCKD_DEFAULT}"
        cat > "${KNOCKD_DEFAULT}" <<EOF
# 由 KnockGate 管理。
START_KNOCKD=1
KNOCKD_OPTS="-i ${INTERFACE}"
EOF
        chmod 644 "${KNOCKD_DEFAULT}"
        log "已写入 ${KNOCKD_DEFAULT}"
    fi

    mkdir -p "${KNOCKD_OVERRIDE_DIR}"
    backup_file "${KNOCKD_OVERRIDE_CONF}"
    cat > "${KNOCKD_OVERRIDE_CONF}" <<EOF
[Unit]
Wants=knockgate-nft.service
After=knockgate-nft.service

[Service]
ExecStart=
ExecStart=${KNOCKD_BIN} -4 -i ${INTERFACE} -c ${KNOCKD_CONF}
EOF
    chmod 644 "${KNOCKD_OVERRIDE_CONF}"
    log "已写入 ${KNOCKD_OVERRIDE_CONF}"

    systemctl daemon-reload
}

configure_knockgate_nft_service() {
    refresh_binaries

    backup_file "${KNOCKGATE_NFT_SERVICE}"
    cat > "${KNOCKGATE_NFT_SERVICE}" <<EOF
[Unit]
Description=KnockGate nftables protective overlay
Documentation=https://github.com/leconio/knockport
Before=knockd.service

[Service]
Type=oneshot
ExecStartPre=-${NFT_BIN} delete table ${NFT_TABLE_FAMILY} ${NFT_TABLE_NAME}
ExecStart=${NFT_BIN} -f ${KNOCKGATE_NFT_CONF}
ExecStop=-${NFT_BIN} delete table ${NFT_TABLE_FAMILY} ${NFT_TABLE_NAME}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    chmod 644 "${KNOCKGATE_NFT_SERVICE}"
    systemctl daemon-reload
    systemctl enable knockgate-nft.service >/dev/null 2>&1 || true
    log "已写入并启用 ${KNOCKGATE_NFT_SERVICE}"
}

restart_services() {
    if ! systemctl cat knockd.service >/dev/null 2>&1; then
        die "安装后未找到 knockd.service，请检查该发行版的 knockd 包。"
    fi

    systemctl enable knockd >/dev/null 2>&1 || true
    systemctl restart knockd
    log "knockd 已重启。"
}

install_self() {
    local self

    self="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || printf '%s\n' "$0")"
    if [[ "${self}" != "${INSTALL_PATH}" ]]; then
        backup_file "${INSTALL_PATH}"
        cp "${self}" "${INSTALL_PATH}"
        chmod 755 "${INSTALL_PATH}"
        log "已安装管理命令： ${INSTALL_PATH}"
    fi
}

write_readme() {
    backup_file "${README_FILE}"
    cat > "${README_FILE}" <<EOF
KnockGate
=========

KnockGate 使用 knockd 和 nftables 实现顺序 UDP 端口敲门。

Paths:
  Manager command: ${INSTALL_PATH}
  Config file:     ${CONFIG_FILE}
  Backup dir:      ${BACKUP_DIR}
  KnockGate nft:   ${KNOCKGATE_NFT_CONF}
  knockd config:   ${KNOCKD_CONF}

常用命令：
  查看临时白名单：
    nft list set ${NFT_TABLE_FAMILY} ${NFT_TABLE_NAME} ${NFT_SET_NAME}

  查看规则：
    nft list table ${NFT_TABLE_FAMILY} ${NFT_TABLE_NAME}

  重新加载 KnockGate 保护表：
    systemctl restart knockgate-nft.service

安全提醒：
  传统端口敲门可能被路径上的观察者重放。
  它适合阻挡普通公网扫描，不是强认证机制。
EOF
    chmod 644 "${README_FILE}"
}

print_completion_info() {
    cat <<EOF

安装/修复完成。

当前保护端口： ${PROTECTED_PORTS}
当前 UDP 敲门序列： ${KNOCK_PORTS}
开门时长： ${OPEN_TIMEOUT}
网卡： ${INTERFACE}

客户端敲门命令：
  rfcjp-knock SERVER_IP $(printf '%s' "${KNOCK_PORTS}" | tr ',' ' ')

备用 nc 敲门命令：
EOF
    local port
    IFS=',' read -r -a ports <<< "${KNOCK_PORTS}"
    for port in "${ports[@]}"; do
        echo "  printf knockgate | nc -u -w1 SERVER_IP ${port}"
    done
    cat <<EOF

查看临时白名单：
  nft list set ${NFT_TABLE_FAMILY} ${NFT_TABLE_NAME} ${NFT_SET_NAME}

查看规则：
  nft list table ${NFT_TABLE_FAMILY} ${NFT_TABLE_NAME}

重新加载 KnockGate 保护表：
  systemctl restart knockgate-nft.service

安全提醒：
  传统端口敲门可能被路径上的观察者重放。
  它适合阻挡普通公网扫描，不是强认证机制。

首次部署检查：
  - 确认原防火墙/云安全组允许保护端口的合法流量通过。
  - 确认云厂商控制台/救援方式可用。

EOF
}

install_or_repair() {
    require_root
    load_config
    install_packages

    if ! prompt_firewall_config; then
        return 0
    fi

    save_config
    apply_nft
    configure_knockgate_nft_service
    render_knockd_conf
    configure_knockd_service
    restart_services
    install_self
    write_readme
    print_completion_info
}

update_config() {
    require_root
    load_config
    refresh_binaries

    if [[ ! -r "${CONFIG_FILE}" ]]; then
        echo "未找到现有配置，请先运行安装/修复。"
        return 0
    fi

    print_firewall_warning
    detect_interface
    print_config_summary
    if ! require_upper_yes "更新配置将只替换 KnockGate 保护表，并重启 knockd。"; then
        echo "已取消。"
        return 0
    fi

    save_config
    apply_nft
    configure_knockgate_nft_service
    render_knockd_conf
    configure_knockd_service
    restart_services
    install_self
    write_readme
}

reset_ports() {
    require_root
    load_config
    refresh_binaries

    if ! prompt_firewall_config; then
        return 0
    fi

    save_config
    apply_nft
    configure_knockgate_nft_service
    render_knockd_conf
    configure_knockd_service
    restart_services
    install_self
    write_readme
    print_completion_info
}

show_status() {
    require_root
    load_config
    refresh_binaries

    echo
    echo "== knockd 状态 =="
    systemctl --no-pager status knockd || true

    echo
    echo "== nftables 表 =="
    "${NFT_BIN}" list table "${NFT_TABLE_FAMILY}" "${NFT_TABLE_NAME}" || true

    echo
    echo "== 临时白名单 =="
    "${NFT_BIN}" list set "${NFT_TABLE_FAMILY}" "${NFT_TABLE_NAME}" "${NFT_SET_NAME}" || true

    echo
    echo "== 默认出口网卡 =="
    ip -4 route show default 0.0.0.0/0 || true
    echo "配置网卡： ${INTERFACE:-未设置}"

    echo
    echo "== 当前配置 =="
    if [[ -r "${CONFIG_FILE}" ]]; then
        sed 's/^/  /' "${CONFIG_FILE}"
    else
        echo "  ${CONFIG_FILE} not found."
    fi
}

show_logs() {
    require_root
    echo
    heading "$(tr_text "knockd 日志" "knockd logs")"
    echo "1. $(tr_text "查看最近 100 行 knockd 日志" "Show last 100 knockd log lines")"
    echo "2. $(tr_text "实时跟随 knockd 日志" "Follow knockd logs")"
    echo "3. $(tr_text "返回" "Back")"
    local choice
    read -r -p "$(color_text "${COLOR_MAGENTA}" "$(tr_text "请选择：" "Choose: ") ")" choice
    case "${choice}" in
        1) journalctl -u knockd -n 100 --no-pager || true ;;
        2) journalctl -u knockd -f || true ;;
        *) ;;
    esac
}

show_allowlist() {
    require_root
    load_config
    refresh_binaries

    local set_output
    set_output="$("${NFT_BIN}" list set "${NFT_TABLE_FAMILY}" "${NFT_TABLE_NAME}" "${NFT_SET_NAME}" 2>/dev/null || true)"

    echo
    heading "$(tr_text "临时放行摘要" "Temporary allowlist summary")"
    echo "$(tr_text "保护端口：" "Protected ports:") ${PROTECTED_PORTS:-$(tr_text "未设置" "not set")}"
    if ! grep -q "elements =" <<< "${set_output}"; then
        warn "$(tr_text "当前没有临时放行 IP。" "No IP is currently allowed.")"
    else
        echo "${set_output}" | awk \
            -v ports="${PROTECTED_PORTS:-$(tr_text "未设置" "not set")}" \
            -v ip_label="$(tr_text "IP:" "IP:")" \
            -v ports_label="$(tr_text "可访问保护端口:" "Protected ports:")" \
            -v remain_label="$(tr_text "剩余时间:" "Remaining:")" \
            -v permanent_label="$(tr_text "永久" "permanent")" '
            /elements =/ {
                line = $0
                sub(/^.*elements = [{][ \t]*/, "", line)
                sub(/[ \t]*[}].*$/, "", line)
                n = split(line, items, /,[ \t]*/)
                for (i = 1; i <= n; i++) {
                    item = items[i]
                    ip = item
                    sub(/[ \t]+timeout.*$/, "", ip)
                    remain = permanent_label
                    if (match(item, /expires[ \t]+[^ \t,}]+/)) {
                        remain = substr(item, RSTART + 8, RLENGTH - 8)
                    }
                    printf "%s %-15s  %s %-20s  %s %s\n", ip_label, ip, ports_label, ports, remain_label, remain
                }
            }
        '
    fi

    echo
    heading "$(tr_text "原始 nft set" "Raw nft set")"
    if [[ -n "${set_output}" ]]; then
        printf '%s\n' "${set_output}"
    else
        warn "$(tr_text "无法读取" "Could not read") ${NFT_TABLE_FAMILY} ${NFT_TABLE_NAME} ${NFT_SET_NAME}。"
    fi
}

add_ip_allowlist() {
    require_root
    load_config
    refresh_binaries

    local ip
    local allow_timeout
    local nft_element
    read -r -p "$(color_text "${COLOR_MAGENTA}" "$(tr_text "要临时放行的 IP：" "IP to allow:") ")" ip
    if ! is_ipv4 "${ip}"; then
        warn "$(tr_text "无效 IPv4 地址：" "Invalid IPv4 address:") ${ip}"
        return 0
    fi

    echo
    info "$(tr_text "请输入放行时长，例如 30m、12h、1d。" "Enter allow duration, for example 30m, 12h, 1d.")"
    warn "$(tr_text "输入 0 表示永久放行。永久放行不会自动过期，请谨慎使用。" "Enter 0 for permanent allow. It will not expire automatically; use carefully.")"
    allow_timeout="$(prompt_default "$(tr_text "放行时长" "Allow duration")" "${OPEN_TIMEOUT}")"
    while [[ "${allow_timeout}" != "0" ]] && ! validate_timeout "${allow_timeout}"; do
        warn "$(tr_text "时间格式无效。请使用 30s、10m、12h、1d，或输入 0 表示永久。" "Invalid duration. Use 30s, 10m, 12h, 1d, or 0 for permanent.")"
        allow_timeout="$(prompt_default "$(tr_text "放行时长" "Allow duration")" "${OPEN_TIMEOUT}")"
    done

    if [[ "${allow_timeout}" == "0" ]]; then
        echo
        danger "$(tr_text "警告：你将永久放行" "WARNING: you are permanently allowing") ${ip} $(tr_text "访问所有保护端口：" "to access all protected ports:") ${PROTECTED_PORTS}"
        warn "$(tr_text "永久放行不会自动从 nftables set 中过期，只能手动清空或删除。" "Permanent allow entries do not expire automatically; flush or delete them manually.")"
        if ! require_upper_yes "$(tr_text "确认永久放行此 IP。" "Confirm permanent allow for this IP.")"; then
            warn "$(tr_text "已取消。" "Cancelled.")"
            return 0
        fi
        nft_element="{ ${ip} }"
    else
        if ! confirm_yes_no "$(tr_text "添加" "Add") ${ip} $(tr_text "到临时白名单，时长" "to temporary allowlist for") ${allow_timeout}" "yes"; then
            warn "$(tr_text "已取消。" "Cancelled.")"
            return 0
        fi
        nft_element="{ ${ip} timeout ${allow_timeout} }"
    fi

    if [[ "${allow_timeout}" == "0" ]]; then
        log "正在永久放行 ${ip}。"
    fi

    if ! "${NFT_BIN}" add element "${NFT_TABLE_FAMILY}" "${NFT_TABLE_NAME}" "${NFT_SET_NAME}" "${nft_element}"; then
        warn "$(tr_text "添加失败。该 IP 可能已经存在；如需修改时长，请先清空白名单或手动删除该元素。" "Add failed. The IP may already exist; to change duration, flush the allowlist or delete the element manually.")"
        return 1
    fi

    if [[ "${allow_timeout}" == "0" ]]; then
        log "已永久放行 ${ip}。"
    else
        log "已添加 ${ip} 到临时白名单，时长 ${allow_timeout}。"
    fi
}

flush_allowlist() {
    require_root
    refresh_binaries

    if ! require_upper_yes "$(tr_text "这将清空所有临时放行 IP。" "This will flush all allowed IPs.")"; then
        warn "$(tr_text "已取消。" "Cancelled.")"
        return 0
    fi

    "${NFT_BIN}" flush set "${NFT_TABLE_FAMILY}" "${NFT_TABLE_NAME}" "${NFT_SET_NAME}"
    log "临时白名单已清空。"
}

list_backups_for() {
    local base="$1"
    local path

    shopt -s nullglob
    for path in "${BACKUP_DIR}/${base}".*.bak; do
        printf '%s\n' "${path}"
    done
    shopt -u nullglob
}

restore_selected_backup() {
    local target="$1"
    local base
    local -a backups=()
    local item
    local idx
    local selected

    base="$(basename "${target}")"
    while IFS= read -r item; do
        backups+=("${item}")
    done < <(list_backups_for "${base}" | sort)

    if [[ "${#backups[@]}" -eq 0 ]]; then
        echo "未找到备份： ${target}."
        return 1
    fi

    echo
    echo "可用备份： ${target}:"
    idx=1
    for item in "${backups[@]}"; do
        echo "  ${idx}. ${item}"
        idx=$((idx + 1))
    done
    echo "  0. Cancel"

    read -r -p "选择备份编号： " idx
    if ! is_uint "${idx}" || (( idx < 0 || idx > ${#backups[@]} )); then
        echo "无效选择。"
        return 1
    fi
    if (( idx == 0 )); then
        echo "已取消。"
        return 1
    fi

    selected="${backups[$((idx - 1))]}"
    echo "已选择： ${selected}"
    if ! require_upper_yes "恢复此备份到 ${target}."; then
        echo "已取消。"
        return 1
    fi

    backup_file "${target}"
    cp -a "${selected}" "${target}"
    log "已恢复 ${selected} -> ${target}"
}

reload_knockgate_rules() {
    require_root
    load_config
    refresh_binaries
    local check_tmp

    if [[ ! -r "${KNOCKGATE_NFT_CONF}" ]]; then
        warn "$(tr_text "未找到 KnockGate nft 配置，请先安装/修复。" "KnockGate nft config not found; run Install / Repair first.")"
        return 0
    fi

    if ! require_upper_yes "$(tr_text "这将只重载 KnockGate 自己的 nft 保护表，原防火墙不变。" "This will reload only KnockGate's nft protective table; existing firewall remains unchanged.")"; then
        warn "$(tr_text "已取消。" "Cancelled.")"
        return 0
    fi

    check_tmp="$(mktemp)"
    {
        if "${NFT_BIN}" list table "${NFT_TABLE_FAMILY}" "${NFT_TABLE_NAME}" >/dev/null 2>&1; then
            echo "delete table ${NFT_TABLE_FAMILY} ${NFT_TABLE_NAME}"
        fi
        cat "${KNOCKGATE_NFT_CONF}"
    } > "${check_tmp}"
    "${NFT_BIN}" -c -f "${check_tmp}"
    rm -f "${check_tmp}"
    if "${NFT_BIN}" list table "${NFT_TABLE_FAMILY}" "${NFT_TABLE_NAME}" >/dev/null 2>&1; then
        "${NFT_BIN}" delete table "${NFT_TABLE_FAMILY}" "${NFT_TABLE_NAME}"
    fi
    "${NFT_BIN}" -f "${KNOCKGATE_NFT_CONF}"
    systemctl restart knockgate-nft.service >/dev/null 2>&1 || true
    log "KnockGate 保护表已重载。"
}

url_encode() {
    local input="$1"
    local output=""
    local i char hex

    for ((i = 0; i < ${#input}; i++)); do
        char="${input:i:1}"
        case "${char}" in
            [a-zA-Z0-9.~_-]) output+="${char}" ;;
            *) printf -v hex '%%%02X' "'${char}"; output+="${hex}" ;;
        esac
    done

    printf '%s\n' "${output}"
}

detect_server_host() {
    local host=""

    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        host="$(awk '{print $3}' <<< "${SSH_CONNECTION}")"
    fi

    if [[ -z "${host}" ]] && command -v ip >/dev/null 2>&1; then
        host="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '
            {
                for (i = 1; i <= NF; i++) {
                    if ($i == "src" && (i + 1) <= NF) {
                        print $(i + 1)
                        exit
                    }
                }
            }
        ')"
    fi

    if [[ -z "${host}" ]] && command -v hostname >/dev/null 2>&1; then
        host="$(hostname -I 2>/dev/null | awk '{print $1}')"
    fi

    printf '%s\n' "${host:-SERVER_IP}"
}

build_client_import_url() {
    local host="$1"
    local label="${2:-KnockGate}"

    printf 'knockgate://import/v1?host=%s&scheme=%s&knock_ports=%s&protected_ports=%s&seq_timeout=%s&open_timeout=%s&label=%s\n' \
        "$(url_encode "${host}")" \
        "udp" \
        "$(url_encode "${KNOCK_PORTS}")" \
        "$(url_encode "${PROTECTED_PORTS}")" \
        "$(url_encode "${SEQ_TIMEOUT}")" \
        "$(url_encode "${OPEN_TIMEOUT}")" \
        "$(url_encode "${label}")"
}

show_client_import_qr() {
    require_root
    load_config

    local default_host
    local host
    local label
    local url

    default_host="$(detect_server_host)"
    echo
    heading "$(tr_text "客户端一键导入" "Client one-tap import")"
    info "$(tr_text "二维码内容是 KnockGate 专用协议 URL，用于未来客户端一键导入 UDP 敲门顺序。" "The QR code contains a KnockGate custom protocol URL for future one-tap UDP sequence import.")"
    warn "$(tr_text "请只把此二维码发给可信客户端；拿到它的人可以获得敲门顺序。" "Share this QR code only with trusted clients; it contains the knock sequence.")"
    echo

    host="$(prompt_default "$(tr_text "客户端连接服务器地址/IP" "Server host/IP for clients")" "${default_host}")"
    label="$(prompt_default "$(tr_text "配置名称" "Profile name")" "KnockGate")"
    url="$(build_client_import_url "${host}" "${label}")"

    echo
    if command -v qrencode >/dev/null 2>&1; then
        qrencode -t ANSIUTF8 "${url}"
    else
        warn "$(tr_text "未找到 qrencode，无法在终端生成二维码。" "qrencode is not installed; cannot render a terminal QR code.")"
        echo "$(tr_text "安装提示：" "Install hint:")"
        echo "  Debian/Ubuntu: apt-get install -y qrencode"
        echo "  RHEL/Fedora:   dnf install -y qrencode"
        echo "  Arch:          pacman -Sy --noconfirm qrencode"
    fi

    echo
    heading "$(tr_text "协议 URL" "Protocol URL")"
    printf '%s\n' "${url}"
    echo
    info "$(tr_text "字段：" "Fields:")"
    echo "  host=${host}"
    echo "  scheme=udp"
    echo "  knock_ports=${KNOCK_PORTS}"
    echo "  protected_ports=${PROTECTED_PORTS}"
    echo "  seq_timeout=${SEQ_TIMEOUT}"
    echo "  open_timeout=${OPEN_TIMEOUT}"
}

uninstall() {
    require_root
    load_config
    refresh_binaries

    print_firewall_warning
    if ! require_upper_yes "卸载将停止 knockd，并可能修改防火墙文件。"; then
        echo "已取消。"
        return 0
    fi

    systemctl stop knockd >/dev/null 2>&1 || true
    systemctl disable knockd >/dev/null 2>&1 || true
    log "knockd stopped and disabled if present."

    systemctl stop knockgate-nft.service >/dev/null 2>&1 || true
    systemctl disable knockgate-nft.service >/dev/null 2>&1 || true
    if confirm_yes_no "删除 KnockGate live nft 表 ${NFT_TABLE_FAMILY} ${NFT_TABLE_NAME}" "yes"; then
        "${NFT_BIN}" delete table "${NFT_TABLE_FAMILY}" "${NFT_TABLE_NAME}" || true
        log "已删除 live nft 表 ${NFT_TABLE_FAMILY} ${NFT_TABLE_NAME}（如果存在）。"
    fi

    if [[ -e "${KNOCKGATE_NFT_SERVICE}" ]] && confirm_yes_no "删除 ${KNOCKGATE_NFT_SERVICE}" "yes"; then
        backup_file "${KNOCKGATE_NFT_SERVICE}"
        rm -f "${KNOCKGATE_NFT_SERVICE}"
        systemctl daemon-reload
        log "已删除 ${KNOCKGATE_NFT_SERVICE}。"
    fi

    if [[ -e "${KNOCKGATE_NFT_CONF}" ]] && confirm_yes_no "删除 ${KNOCKGATE_NFT_CONF}" "yes"; then
        backup_file "${KNOCKGATE_NFT_CONF}"
        rm -f "${KNOCKGATE_NFT_CONF}"
        log "已删除 ${KNOCKGATE_NFT_CONF}。"
    fi

    if confirm_yes_no "恢复 knockd.conf 备份" "no"; then
        restore_selected_backup "${KNOCKD_CONF}" || true
    fi

    if [[ -e "${KNOCKD_OVERRIDE_CONF}" ]] && confirm_yes_no "删除 KnockGate 的 knockd systemd override" "yes"; then
        backup_file "${KNOCKD_OVERRIDE_CONF}"
        rm -f "${KNOCKD_OVERRIDE_CONF}"
        rmdir "${KNOCKD_OVERRIDE_DIR}" 2>/dev/null || true
        systemctl daemon-reload
        log "已删除 knockd systemd override。"
    fi

    if [[ -e "${KNOCKD_DEFAULT}" ]] && grep -q "Managed by KnockGate" "${KNOCKD_DEFAULT}" 2>/dev/null; then
        if confirm_yes_no "删除 ${KNOCKD_DEFAULT}" "no"; then
            backup_file "${KNOCKD_DEFAULT}"
            rm -f "${KNOCKD_DEFAULT}"
            log "已删除 ${KNOCKD_DEFAULT}。"
        fi
    fi

    if [[ -e "${INSTALL_PATH}" ]] && confirm_yes_no "删除 ${INSTALL_PATH}" "no"; then
        backup_file "${INSTALL_PATH}"
        rm -f "${INSTALL_PATH}"
        log "已删除 ${INSTALL_PATH}。"
    fi

    if [[ -d "${CONFIG_DIR}" ]]; then
        if require_upper_yes "删除 ${CONFIG_DIR}，包括备份。"; then
            rm -rf "${CONFIG_DIR}"
            log "已删除 ${CONFIG_DIR}。"
        else
            echo "已保留 ${CONFIG_DIR}."
        fi
    fi

    log "卸载流程完成。"
}

main_menu() {
    choose_language
    require_root
    load_config

    while true; do
        echo
        heading "$(tr_text "KnockGate 管理器" "KnockGate Manager")"
        echo "$(color_text "${COLOR_BLUE}" "1.") $(tr_text "安装 / 修复" "Install / Repair")"
        echo "$(color_text "${COLOR_BLUE}" "2.") $(tr_text "更新配置" "Update config")"
        echo "$(color_text "${COLOR_BLUE}" "3.") $(tr_text "重置端口和时间" "Reset ports and timings")"
        echo "$(color_text "${COLOR_BLUE}" "4.") $(tr_text "查看状态" "Show status")"
        echo "$(color_text "${COLOR_BLUE}" "5.") $(tr_text "查看 knockd 日志" "Show knockd logs")"
        echo "$(color_text "${COLOR_BLUE}" "6.") $(tr_text "查看临时白名单" "Show temporary allowlist")"
        echo "$(color_text "${COLOR_BLUE}" "7.") $(tr_text "添加 IP 到临时白名单" "Add IP to allowlist")"
        echo "$(color_text "${COLOR_BLUE}" "8.") $(tr_text "清空临时白名单" "Flush allowlist")"
        echo "$(color_text "${COLOR_BLUE}" "9.") $(tr_text "重载 KnockGate 保护表" "Reload KnockGate rules")"
        echo "$(color_text "${COLOR_BLUE}" "10.") $(tr_text "卸载" "Uninstall")"
        echo "$(color_text "${COLOR_BLUE}" "11.") $(tr_text "生成客户端导入二维码" "Generate client import QR")"
        echo "$(color_text "${COLOR_BLUE}" "12.") $(tr_text "退出" "Exit")"
        echo
        local choice
        read -r -p "$(color_text "${COLOR_MAGENTA}" "$(tr_text "请选择：" "Choose: ") ")" choice
        case "${choice}" in
            1) install_or_repair ;;
            2) update_config ;;
            3) reset_ports ;;
            4) show_status ;;
            5) show_logs ;;
            6) show_allowlist ;;
            7) add_ip_allowlist ;;
            8) flush_allowlist ;;
            9) reload_knockgate_rules ;;
            10) uninstall ;;
            11) show_client_import_qr ;;
            12) exit 0 ;;
            *) warn "$(tr_text "无效选择。" "Invalid choice.")" ;;
        esac
    done
}

main_menu "$@"
