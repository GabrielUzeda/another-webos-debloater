#!/bin/sh
# lib/hide_apps.sh - Ocultacao de tiles de bloat via blockedSystemAppList + samrescan cirurgico
# NUNCA reinicia o SAM (systemctl restart sam) para evitar tela preta.

PROTECTED_IDS='
com.webos.app.home
com.webos.app.settings
com.webos.app.hdmi1
com.webos.app.hdmi2
com.webos.app.hdmi3
com.webos.app.hdmi4
com.webos.app.livetv
com.webos.app.inputcommon
org.webosbrew.hbchannel
'

BLOAT_HIDE_IDS='
com.webos.app.acrcomponent
com.webos.app.acrhdmi1
com.webos.app.acrhdmi2
com.webos.app.acrhdmi3
com.webos.app.acrhdmi4
com.webos.app.acroverlay
com.webos.app.adoverlay
com.webos.app.adoverlayex
com.webos.app.adhdmi1
com.webos.app.adhdmi2
com.webos.app.adhdmi3
com.webos.app.adhdmi4
com.webos.app.fooddelivery
com.webos.app.fooddeliveryex
com.webos.app.overlaymembership
com.webos.app.videoads
com.webos.app.cmp-client
com.webos.app.newandhot
com.webos.app.store-demo
com.webos.app.sync-demo
com.webos.app.factorywin
com.webos.app.svcdiagnostics
com.webos.app.quickrecovery
com.webos.app.renewupdate
com.webos.app.discovery
com.webos.app.channelplus
com.webos.app.sportsevent
com.webos.app.today
com.webos.app.recent
com.webos.app.accuweather
com.webos.app.tvplus
com.webos.app.manufacturer
'

# Le IDs ja presentes no blockedSystemAppList para mesclar sem perder bloqueios de fabrica
read_existing_blocked_ids() {
    list_file="$1"
    [ -f "$list_file" ] || return 0
    awk '
        { buf = buf $0 "\n" }
        END {
            i = index(buf, "\"blocked_system_applist\"")
            if (i > 0) {
                rest = substr(buf, i)
                j = index(rest, "[")
                if (j > 0) {
                    rest = substr(rest, j + 1)
                    k = index(rest, "]")
                    if (k > 0) {
                        arr = substr(rest, 1, k - 1)
                        n = split(arr, parts, ",")
                        for (p = 1; p <= n; p++) {
                            s = parts[p]
                            gsub(/[ \t\r\n]/, "", s)
                            gsub(/"/, "", s)
                            if (s != "") print s
                        }
                    }
                }
            }
        }
    ' "$list_file" 2>/dev/null || true
}

# Rescan cirurgico do SAM de acordo com a versao do webOS
trigger_sam_rescan() {
    ver=$(detect_webos_version)
    log_info "Acionando releitura de apps do SAM sem reiniciar (webOS $ver)..."

    if [ "$ver" -le 9 ] 2>/dev/null; then
        # webOS <= 9: Nudge via configd profile.blockedAppList
        nudge_id="com.webos_clean.nudge"
        luna_call "luna://com.webos.service.config/setConfigs" "{\"configs\":{\"profile.blockedAppList\":[\"$nudge_id\"]}}" >/dev/null 2>&1
        sleep 1
        luna_call "luna://com.webos.service.config/setConfigs" '{"configs":{"profile.blockedAppList":[]}}' >/dev/null 2>&1
    elif [ "$ver" -eq 10 ] 2>/dev/null; then
        # webOS 10: blockSystemApp + releaseBlockSystemApp em um id dummy/safe
        dummy="com.webos.app.discovery"
        luna_call "luna://com.webos.service.applicationmanager/blockSystemApp" "{\"id\":\"$dummy\"}" >/dev/null 2>&1
        luna_call "luna://com.webos.service.applicationmanager/releaseBlockSystemApp" "{\"id\":\"$dummy\"}" >/dev/null 2>&1
    else
        # webOS 11+: requer forceBlockSystemApp: false
        dummy="com.webos.app.discovery"
        luna_call "luna://com.webos.service.applicationmanager/blockSystemApp" "{\"id\":\"$dummy\",\"forceBlockSystemApp\":false}" >/dev/null 2>&1
        luna_call "luna://com.webos.service.applicationmanager/releaseBlockSystemApp" "{\"id\":\"$dummy\"}" >/dev/null 2>&1
    fi
    log_ok "SAM atualizado com sucesso."
}

# Aplica a lista de apps bloqueados mesclando com os existentes
hide_apps_apply() {
    list_file=$(get_blocked_list_file)
    backup_file="$1"
    mkdir -p "$(dirname "$list_file")" 2>/dev/null || true

    # Backup do arquivo original se ainda nao existir
    if [ -f "$list_file" ] && [ -n "$backup_file" ] && [ ! -f "$backup_file" ]; then
        cp -p "$list_file" "$backup_file" 2>/dev/null || true
    fi

    # Combina existentes + novos bloqueios
    existing_ids=$(read_existing_blocked_ids "$list_file")
    all_targets=$(printf "%s\n%s\n" "$existing_ids" "$BLOAT_HIDE_IDS" | sort -u)

    log_info "Gravando lista mesclada de aplicativos ocultos em $list_file..."
    tmp_json="${list_file}.tmp"

    printf '{"blocked_system_applist":[' > "$tmp_json"
    first=1
    for app in $all_targets; do
        [ -n "$app" ] || continue
        # Garante que nao esta na lista protegida
        if echo "$PROTECTED_IDS" | grep -Fwq "$app"; then
            continue
        fi

        if [ "$first" = "1" ]; then
            printf '"%s"' "$app" >> "$tmp_json"
            first=0
        else
            printf ',"%s"' "$app" >> "$tmp_json"
        fi
    done
    printf ']}' >> "$tmp_json"

    mv -f "$tmp_json" "$list_file"
    log_ok "Lista de bloqueio regional gravada com sucesso."

    # Dispara rescan para surtir efeito imediato
    trigger_sam_rescan
}

# Restaura a lista de apps ao estado original
hide_apps_restore() {
    list_file=$(get_blocked_list_file)
    backup_file="$1"

    log_info "Restaurando aplicativos do sistema..."
    if [ -f "$backup_file" ]; then
        cp -p "$backup_file" "$list_file" 2>/dev/null || true
    else
        rm -f "$list_file" 2>/dev/null || true
    fi

    trigger_sam_rescan
    log_ok "Aplicativos do sistema reexibidos."
}
