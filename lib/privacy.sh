#!/bin/sh
# lib/privacy.sh - Desativacao de telemetria, ACR (LivePlus), bloqueio de updates e DNS (/etc/hosts)
#
# Sobre /etc/hosts no webOS: nao ha como escrever no arquivo do rootfs (a raiz /etc
# e overlay somente-leitura). O sistema monta um tmpfs por cima de /etc/hosts, e o
# startup do Homebrew Channel reescreve esse arquivo a cada boot. Entao:
#   - escrever direto no /etc/hosts funciona e e 100% volatil (vive na RAM);
#   - o original e salvo antes, para restauracao exata;
#   - se por algum motivo o arquivo estiver somente-leitura, caimos para bind mount.

SETTINGS_TARGETS='
general:homePromotion:off
general:sportsAlarm:off
general:lmt:on
option:livePromotion:off
option:webOSPromotionVideo:off
option:promotionStreamer:off
option:livePlus:off
other:contentRecommendation:off
'

# Dominios de telemetria, rastreamento e ACR (Alphonso)
TELEMETRY_DOMAINS='
ad.lgsmartad.com
ibis.lgappstv.com
ibs.lgappstv.com
lgsmartad.com
rdx.lgtvcommon.com
aic.lgtvcommon.com
smartad.lge.com
smartclip.com
smartclip-services.com
yumenetworks.com
alphonso.tv
prov-lg.alphonso.tv
prov.alphonso.tv
eulacheck.alphonso.tv
bl-server.alphonso.tv
clockskew.alphonso.tv
acrdb.alphonso.tv
ads.alphonso.tv
api.alphonso.tv
tvads.alphonso.tv
sync.alphonso.tv
tr.alphonso.tv
tn.alphonso.tv
insights.alphonso.tv
bwlkup.alphonso.tv
'

# Servidores oficiais de atualizacao de firmware OTA da LG (bloqueio de seguranca padrao Homebrew Channel)
UPDATE_DOMAINS='
snu.lge.com
su-dev.lge.com
su.lge.com
su-ssl.lge.com
'

HOSTS_MARKER='# webOS Clean Telemetry Block'
REAL_HOSTS="${MOCK_ROOT}/etc/hosts"
TMP_HOSTS="${MOCK_ROOT}/tmp/webos_clean_hosts"
HOSTS_BIND_FLAG="${MOCK_ROOT}/tmp/webos_clean_hosts_bind"

# Escreve o hosts bloqueado no /etc/hosts (tmpfs => volátil) ou via bind mount
privacy_hosts_apply() {
    backup_file="$1"
    mkdir -p "$(dirname "$TMP_HOSTS")" 2>/dev/null || true

    # 1. Backup exato do hosts original (uma unica vez, nunca sobrescreve)
    if [ -n "$backup_file" ] && [ ! -f "$backup_file" ] && [ -f "$REAL_HOSTS" ]; then
        mkdir -p "$(dirname "$backup_file")" 2>/dev/null || true
        cp -p "$REAL_HOSTS" "$backup_file" 2>/dev/null || true
    fi

    # 2. Monta o novo conteudo preservando o que ja existe (exceto blocos antigos)
    {
        if [ -f "$REAL_HOSTS" ]; then
            grep -v "$HOSTS_MARKER" "$REAL_HOSTS" 2>/dev/null | \
                grep -v "alphonso.tv" | grep -v "lgsmartad.com" | \
                grep -v "snu.lge.com" | grep -v "su-dev.lge.com" | \
                grep -v "su.lge.com" | grep -v "su-ssl.lge.com"
        else
            printf '127.0.0.1 localhost\n::1 localhost\n'
        fi
        printf '\n%s\n' "$HOSTS_MARKER"
        for domain in $TELEMETRY_DOMAINS $UPDATE_DOMAINS; do
            printf '0.0.0.0 %s\n' "$domain"
        done
    } > "$TMP_HOSTS" 2>/dev/null || return 1

    # 3. Escreve direto (tmpfs) ou cai para bind mount se o arquivo for read-only
    if cat "$TMP_HOSTS" > "$REAL_HOSTS" 2>/dev/null; then
        log_ok "Telemetria e servidores de update bloqueados em /etc/hosts (tmpfs/RAM, volátil)."
        return 0
    fi

    log_warn "/etc/hosts nao aceita escrita direta; usando bind mount."
    if [ -z "$MOCK_ROOT" ] && command -v mount >/dev/null 2>&1; then
        if mount --bind "$TMP_HOSTS" "$REAL_HOSTS" 2>/dev/null; then
            touch "$HOSTS_BIND_FLAG" 2>/dev/null || true
            log_ok "Telemetria e updates bloqueados em /etc/hosts via bind mount."
            return 0
        fi
    fi
    log_warn "Nao foi possivel aplicar o bloqueio de hosts; seguindo em frente."
    return 1
}

# Restaura o /etc/hosts original
privacy_hosts_restore() {
    backup_file="$1"

    if [ -f "$HOSTS_BIND_FLAG" ]; then
        [ -z "$MOCK_ROOT" ] && umount "$REAL_HOSTS" 2>/dev/null || true
        rm -f "$HOSTS_BIND_FLAG" 2>/dev/null || true
    fi

    if [ -n "$backup_file" ] && [ -f "$backup_file" ]; then
        cat "$backup_file" > "$REAL_HOSTS" 2>/dev/null || true
        log_ok "/etc/hosts restaurado a partir do backup."
    else
        # Sem backup: apenas remove as linhas do debloat
        if [ -f "$REAL_HOSTS" ]; then
            grep -v "$HOSTS_MARKER" "$REAL_HOSTS" 2>/dev/null | grep -v '^0.0.0.0 ' > "$TMP_HOSTS" 2>/dev/null || true
            cat "$TMP_HOSTS" > "$REAL_HOSTS" 2>/dev/null || true
        fi
        log_ok "Linhas de bloqueio removidas de /etc/hosts."
    fi
    rm -f "$TMP_HOSTS" 2>/dev/null || true
}

# Bloqueio persistente de updates compativel com Homebrew Channel
privacy_update_block_apply() {
    backup_file="$1"
    flag_file="${MOCK_ROOT}/var/luna/preferences/webosbrew_block_updates"

    if [ -n "$backup_file" ] && [ ! -f "$backup_file" ]; then
        mkdir -p "$(dirname "$backup_file")" 2>/dev/null || true
        if [ -f "$flag_file" ]; then
            echo "existed" > "$backup_file"
        else
            echo "created" > "$backup_file"
        fi
    fi

    mkdir -p "$(dirname "$flag_file")" 2>/dev/null || true
    touch "$flag_file" 2>/dev/null || true
    log_ok "Bloqueio de updates OTA ativo (/var/luna/preferences/webosbrew_block_updates)."
}

# Restaura o flag de bloqueio de updates do Homebrew Channel
privacy_update_block_restore() {
    backup_file="$1"
    flag_file="${MOCK_ROOT}/var/luna/preferences/webosbrew_block_updates"

    if [ -f "$backup_file" ]; then
        if grep -q "^created$" "$backup_file"; then
            rm -f "$flag_file" 2>/dev/null || true
            log_ok "Flag de bloqueio de updates removida (revertida ao padrao anterior)."
        else
            log_info "Flag de bloqueio de updates ja existia originalmente; mantida."
        fi
    fi
}

# Desativa promocoes, ACR e ativa Limit Ad Tracking via settingsservice
privacy_settings_apply() {
    backup_file="$1"
    log_info "Desativando telemetria, ACR e ativando Limit Ad Tracking..."

    for triple in $SETTINGS_TARGETS; do
        cat_name=$(echo "$triple" | cut -d: -f1)
        key_name=$(echo "$triple" | cut -d: -f2)
        target_val=$(echo "$triple" | cut -d: -f3)
        [ -n "$target_val" ] || target_val="off"

        # Backup do valor atual antes de mexer
        if [ -n "$backup_file" ]; then
            get_payload="{\"category\":\"$cat_name\",\"keys\":[\"$key_name\"]}"
            res=$(luna_call "luna://com.webos.service.settings/getSystemSettings" "$get_payload")
            current=$(printf '%s' "$res" | sed -n 's/.*"'"$key_name"'":"\([a-z]*\)".*/\1/p')
            [ -n "$current" ] || current="unknown"
            printf '%s:%s:%s\n' "$cat_name" "$key_name" "$current" >> "$backup_file"
        fi

        set_payload="{\"category\":\"$cat_name\",\"settings\":{\"$key_name\":\"$target_val\"}}"
        out=$(luna_call "luna://com.webos.service.settings/setSystemSettings" "$set_payload")
        if printf '%s' "$out" | grep -q '"returnValue":true'; then
            log_ok "  $key_name -> $target_val"
        else
            log_warn "  $key_name: firmware nao aceitou (chave inexistente?), seguindo."
        fi
    done

    # Inativa cookies de publicidade
    luna_call "luna://com.webos.service.admanager/inactivateCookies" "{}" >/dev/null 2>&1 || true

    # Desativa termos de rastreamento no eulaStatus (ACR, Custom Ads, Diagnostico)
    eula_payload='{"settings":{"eulaStatus":{"acrAllowed":false,"acrAdAllowed":false,"customAdAllowed":false,"remoteDiagAllowed":false,"additionalDataAllowed":false,"marketingOnAllowed":false,"shoppingOnAllowed":false,"acrOnAllowed":false}}}'
    luna_call "luna://com.webos.settingsservice/setSystemSettings" "$eula_payload" >/dev/null 2>&1 || true
    log_ok "Termos de rastreamento revogados (eulaStatus) e cookies de publicidade inativados."
}

# Restaura as configuracoes originais
privacy_settings_restore() {
    backup_file="$1"
    [ -f "$backup_file" ] || { log_info "Sem backup de settings; nada a restaurar."; return 0; }
    log_info "Restaurando configuracoes do settingsservice..."

    while IFS=: read -r cat_name key_name val; do
        [ -n "$cat_name" ] && [ -n "$key_name" ] || continue
        case "$val" in
            on|off) ;;
            *) continue ;;
        esac
        set_payload="{\"category\":\"$cat_name\",\"settings\":{\"$key_name\":\"$val\"}}"
        luna_call "luna://com.webos.service.settings/setSystemSettings" "$set_payload" >/dev/null 2>&1
        log_ok "  $key_name -> $val"
    done < "$backup_file"
}
