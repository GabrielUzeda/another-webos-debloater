#!/bin/sh
# lib/homescreen.sh - Higienizacao da tela inicial (mostra apenas apps e inputs, ocultando bloat)
# webOS 10+ via overlayfs matematico sobre home.xml; webOS 9 via manifest XML

HOME_ID="com.webos.app.home"
CLEAN_HOME_STATE="${MOCK_ROOT}/var/lib/webos-clean/clean_home"

# Limpa checkpoints do CRIU para que a TV nao restaure o layout antigo da RAM
clear_criu_checkpoints() {
    log_info "Limpando checkpoints do CRIU..."
    rm -rf "${MOCK_ROOT}/tmp/checkpoint/$HOME_ID" \
           "${MOCK_ROOT}/tmp/checkpoint/hash_check_$HOME_ID" \
           "${MOCK_ROOT}/mnt/lg/cmn_data/checkpoint/$HOME_ID" \
           "${MOCK_ROOT}/mnt/lg/cmn_data/checkpoint/hash_check_$HOME_ID" 2>/dev/null || true
}

# Reinicia a tela inicial de forma limpa (mata processo do Flutter/QML e relança se estava em foco)
restart_home_app() {
    log_info "Reiniciando processo da tela inicial..."
    clear_criu_checkpoints

    if [ -z "$MOCK_ROOT" ]; then
        # Detecta se estava em foreground
        fg_check=$(luna_call "luna://com.webos.service.applicationmanager/getForegroundAppInfo" '{}' 2>/dev/null)
        was_home=0
        if printf '%s' "$fg_check" | grep -q '"appId":"com.webos.app.home"'; then
            was_home=1
        fi

        # Mata processo flutter-client do home
        pkill -f "flutter-client.*$HOME_ID" 2>/dev/null || pkill -f "$HOME_ID" 2>/dev/null || true
        sleep 1

        if [ "$was_home" = "1" ]; then
            luna_call "luna://com.webos.service.applicationmanager/launch" "{\"id\":\"$HOME_ID\"}" >/dev/null 2>&1 || true
        fi
    fi
}

# Construtor de layout webOS 10 (expande o container para manter a linha de apps alinhada ao rodape)
homescreen_build_layout_webos10() {
    src_xml="$1"
    awk '
    function getHeight(str,   m) {
        if (match(str, /itemHeight="[0-9]+/)) {
            return substr(str, RSTART + 12) + 0
        }
        return 0
    }
    { lines[NR] = $0 }
    END {
        freed = 0; outCount = 0; sideLine = ""
        for (i = 1; i <= NR; i++) {
            l = lines[i]
            # Oculta Quick Cards (qcardList) e sua margem
            if (index(l, "id=\"qcardList\"") > 0) {
                freed += getHeight(l)
                if (outCount > 0 && index(outLines[outCount], "id=\"margin\"") > 0) {
                    freed += getHeight(outLines[outCount])
                    outCount--
                }
                continue
            }
            # Oculta Recommended Shelf
            if (index(l, "id=\"recommendedShelf\"") > 0) {
                freed += getHeight(l)
                continue
            }
            # Encolhe botoes laterais para 0x0 e posiciona atras do banner
            if (index(l, "id=\"globalline\"") > 0) {
                sub(/itemWidth="[0-9]+"/, "itemWidth=\"0\"", l)
                sub(/itemHeight="[0-9]+"/, "itemHeight=\"0\"", l)
                sideLine = l
                continue
            }
            outLines[++outCount] = l
            if (sideLine != "" && index(l, "id=\"herobanner\"") > 0) {
                outLines[++outCount] = sideLine
                sideLine = ""
            }
        }
        # Expande container e herobanner pela altura liberada para appList nao flutuar no meio
        for (i = 1; i <= outCount; i++) {
            l = outLines[i]
            if (freed > 0 && (index(l, "id=\"container\"") > 0 || index(l, "id=\"herobanner\"") > 0)) {
                h = getHeight(l)
                if (h > 0) {
                    newH = h + freed
                    sub(/itemHeight="[0-9]+"/, "itemHeight=\"" newH "\"", l)
                }
            }
            print l
        }
    }' "$src_xml"
}

# Aplica layout limpo: somente apps na tela inicial
homescreen_apply() {
    backup_file="$1"
    is_permanent="${2:-1}"
    ver=$(detect_webos_version)

    # Caso webOS 10+ (Flutter Home via overlay)
    assets_dir="${MOCK_ROOT}/usr/palm/applications/com.webos.app.home/data/flutter_assets/assets"
    home_xml="$assets_dir/home.xml"

    if [ -f "$home_xml" ] || [ "$ver" -ge 10 ] 2>/dev/null; then
        [ -f "$home_xml" ] || { log_warn "home.xml nao encontrado, pulando layout do Home."; return 0; }

        log_info "Configurando tela inicial limpa (somente apps) para webOS 10+..."
        overlay_dir="${MOCK_ROOT}/tmp/webos_clean_home"

        # Backup do original
        if [ -n "$backup_file" ] && [ ! -f "$backup_file" ]; then
            mkdir -p "$(dirname "$backup_file")" 2>/dev/null || true
            cp -p "$home_xml" "$backup_file" 2>/dev/null || true
        fi

        mkdir -p "$overlay_dir/upper" "$overlay_dir/work" 2>/dev/null || true
        homescreen_build_layout_webos10 "$home_xml" > "$overlay_dir/upper/home.xml"

        if [ -z "$MOCK_ROOT" ] && command -v mount >/dev/null 2>&1; then
            umount "$assets_dir" 2>/dev/null || true
            if mount -t overlay overlay -o "lowerdir=$assets_dir,upperdir=$overlay_dir/upper,workdir=$overlay_dir/work" "$assets_dir" 2>/dev/null; then
                log_ok "OverlayFS montado sobre os assets da tela inicial."
            else
                log_warn "Falha ao montar overlayfs; tentando bind mount direto..."
                mount --bind "$overlay_dir/upper/home.xml" "$home_xml" 2>/dev/null || true
            fi
        fi

        if [ "$is_permanent" = "1" ]; then
            mkdir -p "$(dirname "$CLEAN_HOME_STATE")" 2>/dev/null || true
            touch "$CLEAN_HOME_STATE" 2>/dev/null || true
        fi

        restart_home_app
        log_ok "Tela inicial limpa ativada: exibindo apenas a linha de aplicativos e entradas."
        return 0
    fi

    # Caso webOS 9 (QML Home via manifest)
    if [ "$ver" -eq 9 ] 2>/dev/null; then
        manifest_dir="${MOCK_ROOT}/mnt/lg/cmn_data/manifest"
        log_info "Configurando tela inicial limpa (somente apps) para webOS 9..."
        mkdir -p "$manifest_dir" 2>/dev/null || true

        cat << 'EOF' > "$manifest_dir/home_layoutShelfView.xml"
<!-- webos-clean -->
<layout>
  <item type="AppList" autoFocus="true"/>
</layout>
EOF
        cp -p "$manifest_dir/home_layoutShelfView.xml" "$manifest_dir/home_layout.xml" 2>/dev/null || true

        mkdir -p "$(dirname "$CLEAN_HOME_STATE")" 2>/dev/null || true
        touch "$CLEAN_HOME_STATE" 2>/dev/null || true

        restart_home_app
        log_ok "Tela inicial limpa ativada (webOS 9 manifest)."
        return 0
    fi

    log_info "Versao do webOS ($ver) nao necessita de higienizacao de layout do Home."
}

# Restaura a tela inicial de fabrica
homescreen_restore() {
    backup_file="$1"
    assets_dir="${MOCK_ROOT}/usr/palm/applications/com.webos.app.home/data/flutter_assets/assets"
    manifest_dir="${MOCK_ROOT}/mnt/lg/cmn_data/manifest"

    # webOS 10 overlay
    if [ -z "$MOCK_ROOT" ] && command -v umount >/dev/null 2>&1; then
        umount "$assets_dir" 2>/dev/null || true
        umount "$assets_dir/home.xml" 2>/dev/null || true
    fi
    rm -rf "${MOCK_ROOT}/tmp/webos_clean_home" 2>/dev/null || true

    # webOS 9 manifest
    rm -f "$manifest_dir/home_layoutShelfView.xml" "$manifest_dir/home_layout.xml" 2>/dev/null || true

    rm -f "$CLEAN_HOME_STATE" 2>/dev/null || true

    restart_home_app
    log_ok "Tela inicial restaurada ao padrao de fabrica."
}
