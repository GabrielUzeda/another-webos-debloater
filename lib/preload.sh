#!/bin/sh
# lib/preload.sh - Preload Manager: o que realmente libera RAM
#
# Alvos: apps que a TV mantem residentes na RAM sem uso.
# NUNCA tocamos em home, livetv, livemenu, hdmi1..4, miracast, voice, airplay:
# sao eles que mantem o botao Home e a troca de entradas rapidos (e mexer
# neles quebra o caminho do HDMI).
#
# Camadas (verificado no hardware, webOS 10.3.1):
#   1. setPreloadPolicy por app: vale na hora; perdido se o daemon reiniciar.
#   2. Lista propria em /var/lib/webos-clean/preload_off: o hook de boot
#      reenvia (1) a cada inicializacao. E o que o webOS 10.3 exige: o daemon
#      reabilita tudo ao ligar, mesmo com configd dizendo isEnabled=false.
# NAO escrevemos /var/preferences/webos-preload-manager-conf.json: o daemon
# reescreve esse arquivo ~3s depois que o app vem para a frente.
# Fechar app residente (closeByAppId) e acao separada e explicita: ha relato
# de HDMI parar de abrir depois de fechar app por fora em webOS 4.4 (B8).

PRELOAD_DEFAULT='com.webos.app.browser com.webos.app.lgchannels com.webos.app.livemenu'
PRELOAD_STATE_FILE="${PRELOAD_STATE_FILE:-${MOCK_ROOT}/var/lib/webos-clean/preload_off}"

# Lista de alvos: arquivo de estado ou o padrao
preload_targets() {
    if [ -f "$PRELOAD_STATE_FILE" ]; then
        tr ' ' '\n' < "$PRELOAD_STATE_FILE" | grep -v '^$' | tr '\n' ' '
    else
        printf '%s' "$PRELOAD_DEFAULT"
    fi
}

# 1. Politica em tempo real (volatil) - uma chamada por app
preload_set_policy() {
    state="$1"
    ok=0
    fail=0
    for app in $(preload_targets); do
        out=$(luna_call "luna://com.webos.service.preloadmanager/setPreloadPolicy" \
              "{\"application\":{\"id\":\"$app\",\"isEnabled\":$state}}")
        if printf '%s' "$out" | grep -q '"returnValue":true'; then
            ok=$((ok + 1))
        else
            fail=$((fail + 1))
            log_warn "  $app: $out"
        fi
    done
    if [ "$ok" -gt 0 ]; then
        log_ok "Preload policy aplicada (isEnabled=$state): $ok app(s) ok, $fail falha(s)."
        return 0
    fi
    return 1
}

# 2. Fecha apps residentes (acao explicita e separada)
preload_close_resident() {
    for app in $(preload_targets); do
        out=$(luna_call "luna://com.webos.service.applicationmanager/closeByAppId" "{\"id\":\"$app\"}")
        if printf '%s' "$out" | grep -q '"returnValue":true'; then
            log_ok "  fechado: $app"
        else
            log_info "  nao fechou (talvez nao estivesse aberto): $app"
        fi
    done
}

# Persistencia: grava a lista de alvos que o hook reaplica no boot
preload_apply() {
    backup_dir="$1"
    log_info "Persistindo desativacao do Preload Manager..."

    mkdir -p "$(dirname "$PRELOAD_STATE_FILE")" 2>/dev/null || true
    if [ -n "$backup_dir" ]; then
        mkdir -p "$backup_dir" 2>/dev/null || true
        # Snapshot da politica atual, so para auditoria/referencia
        if [ ! -f "$backup_dir/preload_policy_before.json" ]; then
            luna_call "luna://com.webos.service.preloadmanager/getPreloadPolicy" '{}' \
                > "$backup_dir/preload_policy_before.json" 2>/dev/null || true
        fi
    fi

    printf '%s\n' "$PRELOAD_DEFAULT" > "$PRELOAD_STATE_FILE" 2>/dev/null \
        && log_ok "Lista persistida em $PRELOAD_STATE_FILE" \
        || log_warn "Nao foi possivel gravar $PRELOAD_STATE_FILE"

    preload_set_policy false
}

# Restauracao
preload_restore() {
    log_info "Restaurando Preload Manager de fabrica..."
    rm -f "$PRELOAD_STATE_FILE" 2>/dev/null || true
    preload_set_policy true
}
