#!/bin/sh
# lib/common.sh - Rotinas comuns, logging, deteccao de versao e transporte Luna
# Compativel com POSIX sh (Busybox / ash)

MOCK_ROOT="${MOCK_ROOT:-}"
LUNA_SEND_BIN="${LUNA_SEND_BIN:-/usr/bin/luna-send}"
SYSTEMCTL_BIN="${SYSTEMCTL_BIN:-/bin/systemctl}"

# Cores para terminal (exportadas para uso nos outros scripts)
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET='\033[0m'
    C_BOLD='\033[1m'
    C_RED='\033[31m'
    C_GREEN='\033[32m'
    C_YELLOW='\033[33m'
    C_CYAN='\033[36m'
else
    C_RESET=''
    C_BOLD=''
    C_RED=''
    C_GREEN=''
    C_YELLOW=''
    C_CYAN=''
fi
export C_RESET C_BOLD C_RED C_GREEN C_YELLOW C_CYAN

log_info()  { printf "%b[INFO]%b %s\n" "$C_CYAN" "$C_RESET" "$*"; }
log_ok()    { printf "%b[OK]%b %s\n" "$C_GREEN" "$C_RESET" "$*"; }
log_warn()  { printf "%b[AVISO]%b %s\n" "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_err()   { printf "%b[ERRO]%b %s\n" "$C_RED" "$C_RESET" "$*" >&2; }
die()       { log_err "$*"; exit 1; }

# Validacao de root
require_root() {
    if [ -n "$MOCK_ROOT" ]; then
        return 0
    fi
    if [ "$(id -u 2>/dev/null)" != "0" ]; then
        die "Este script precisa rodar como root na TV (via Homebrew Channel / SSH / Telnet)."
    fi
}

# Verificacao de espaco livre em /var (minimo 2MB para backups)
check_disk_space() {
    target_dir="${MOCK_ROOT}/var"
    [ -d "$target_dir" ] || target_dir="${MOCK_ROOT}/"
    avail_kb=$(df -k "$target_dir" 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -n "$avail_kb" ] && [ "$avail_kb" -lt 2048 ]; then
        die "Espaco livre insuficiente em /var (${avail_kb}KB disponiveis, minimo 2048KB)."
    fi
}

# Deteccao de versao do webOS (retorna numero inteiro maior, ex: 4, 5, 9, 10, 11)
detect_webos_version() {
    if [ -n "${WEBOS_VERSION_OVERRIDE:-}" ]; then
        echo "$WEBOS_VERSION_OVERRIDE"
        return 0
    fi

    # 1. Tenta ler /etc/os-release
    os_file="${MOCK_ROOT}/etc/os-release"
    if [ -f "$os_file" ]; then
        ver=$(awk -F= '/^VERSION_ID=/ {gsub(/"/, "", $2); print $2}' "$os_file" 2>/dev/null)
        if [ -n "$ver" ]; then
            echo "$ver" | awk -F. '{print $1}'
            return 0
        fi
    fi

    # 2. Tenta /etc/webos-release ou /etc/starfish-release
    for f in "${MOCK_ROOT}/etc/webos-release" "${MOCK_ROOT}/etc/starfish-release"; do
        if [ -f "$f" ]; then
            ver=$(sed -n 's/.*release \([0-9]*\)\..*/\1/p' "$f" 2>/dev/null | head -n 1)
            if [ -n "$ver" ]; then
                echo "$ver"
                return 0
            fi
        fi
    done

    # Fallback seguro padrao
    echo "10"
}

# Deteccao do arquivo de regiao para blockedSystemAppList
get_blocked_list_file() {
    apps_dir="${MOCK_ROOT}/var/preferences/com.webos.applicationManager/blockedSystemAppList"
    if [ -d "$apps_dir" ]; then
        for f in "$apps_dir"/*.json; do
            if [ -f "$f" ]; then
                echo "$f"
                return 0
            fi
        done
    fi
    region="${WEBOS_REGION:-BRA}"
    echo "$apps_dir/$region.json"
}

# luna-send only prints its response when stdout has a controlling
# terminal (isatty). Running it over a non-interactive SSH session (e.g.
# `ssh host 'webos-clean --apply'`, cron, or any automation) makes it exit
# with code 0 but print nothing, so luna_call() looks like it succeeded
# with an empty response. This silently breaks the privacy settings and
# can trigger a false positive in the --apply Smoke Test (SAM "not
# responding" -> unnecessary rollback).
# `script` (util-linux) creates a local pty and fixes this regardless of
# how the script itself was invoked (SSH with or without -tt, cron, etc).
# Tested and confirmed on real hardware (webOS 10.3.2 / "webOS25").
SCRIPT_BIN="${SCRIPT_BIN:-$(command -v script 2>/dev/null)}"

# Runs a command through a simulated pty when `script` is available,
# falling back to direct execution (best effort) otherwise.
_run_via_pty() {
    # $1 is already a ready-to-run command string (its own internal args
    # are already single-quoted by the caller); it just needs to be
    # passed as ONE argument here, without re-escaping.
    if [ -n "$SCRIPT_BIN" ] && [ -x "$SCRIPT_BIN" ]; then
        "$SCRIPT_BIN" -qc "$1" /dev/null 2>/dev/null
    else
        eval "$1" 2>/dev/null
    fi
}

# Chamada ao barramento Luna com suporte a SERVICE_MAP e timeout
luna_call() {
    uri="$1"
    payload="$2"
    [ -n "$payload" ] || payload='{}'

    # Trata mapeamento de legado (com.webos.service.settings -> com.webos.settingsservice)
    target_uri="$uri"
    case "$uri" in
        luna://com.webos.service.settings/*)
            legacy_uri=$(echo "$uri" | sed 's|com.webos.service.settings/|com.webos.settingsservice/|')
            ;;
        *)
            legacy_uri=""
            ;;
    esac

    # Executa comando Luna com -i -n 1 -w 3000 (sintaxe comprovada no hardware real)
    if [ -n "$MOCK_LUNA_CMD" ]; then
        out=$($MOCK_LUNA_CMD "$target_uri" "$payload" 2>/dev/null)
    elif [ -x "$LUNA_SEND_BIN" ]; then
        esc_uri=$(printf '%s' "$target_uri" | sed "s/'/'\\\\''/g")
        esc_payload=$(printf '%s' "$payload" | sed "s/'/'\\\\''/g")
        cmd="'$LUNA_SEND_BIN' -i -n 1 -w 3000 '$esc_uri' '$esc_payload'"
        out=$(_run_via_pty "$cmd")
        # Se retornou erro de servico inexistente e existe versao legada, tenta fallback
        if [ -n "$legacy_uri" ] && echo "$out" | grep -q "Service does not exist"; then
            esc_legacy=$(printf '%s' "$legacy_uri" | sed "s/'/'\\\\''/g")
            cmd="'$LUNA_SEND_BIN' -i -n 1 -w 3000 '$esc_legacy' '$esc_payload'"
            out=$(_run_via_pty "$cmd")
        fi
    else
        out='{"returnValue":false,"errorText":"luna-send not available"}'
    fi

    printf '%s\n' "$out"
}
