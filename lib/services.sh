#!/bin/sh
# lib/services.sh - Gerenciamento e mascaramento de servicos de telemetria
# Compativel com systemd (webOS >= 4) e initctl/upstart (webOS <= 3)

SERVICES_LIST='
uploadd.service
rdxd.service
com.webos.service.camera.service
com.webos.service.mycar.service
contentminer.service
nudge.service
remotelogger.service
'

UPSTART_LIST='
uploadd
rdxd
remotelogger
'

# Mascara os servicos em /run (100% volátil na RAM)
services_mask_transient() {
    transient_dir="${MOCK_ROOT}/run/systemd/transient"
    mkdir -p "$transient_dir" 2>/dev/null || true

    has_systemctl=0
    if [ -x "$SYSTEMCTL_BIN" ] || [ -n "$MOCK_ROOT" ]; then
        has_systemctl=1
    fi

    for unit in $SERVICES_LIST; do
        mask_file="$transient_dir/$unit"
        ln -sf /dev/null "$mask_file" 2>/dev/null || true
        log_info "Mascarando em RAM: $unit"

        if [ "$has_systemctl" = "1" ]; then
            if [ -z "$MOCK_ROOT" ]; then
                "$SYSTEMCTL_BIN" stop "$unit" 2>/dev/null || true
            fi
        fi
    done

    if [ "$has_systemctl" = "1" ] && [ -z "$MOCK_ROOT" ]; then
        "$SYSTEMCTL_BIN" daemon-reload 2>/dev/null || true
    fi

    # Fallback para Upstart em webOS 3
    if command -v initctl >/dev/null 2>&1; then
        for job in $UPSTART_LIST; do
            initctl stop "$job" 2>/dev/null || true
        done
    fi
    log_ok "Servicos de telemetria desativados em memoria com sucesso."
}

# Remove as mascaras e reativa os servicos
services_unmask() {
    transient_dir="${MOCK_ROOT}/run/systemd/transient"
    has_systemctl=0
    if [ -x "$SYSTEMCTL_BIN" ] || [ -n "$MOCK_ROOT" ]; then
        has_systemctl=1
    fi

    for unit in $SERVICES_LIST; do
        mask_file="$transient_dir/$unit"
        if [ -L "$mask_file" ] || [ -f "$mask_file" ]; then
            rm -f "$mask_file" 2>/dev/null || true
            log_info "Desfazendo mascara: $unit"
        fi
    done

    if [ "$has_systemctl" = "1" ] && [ -z "$MOCK_ROOT" ]; then
        "$SYSTEMCTL_BIN" daemon-reload 2>/dev/null || true
        # Inicia os servicos de volta se necessario
        for unit in $SERVICES_LIST; do
            "$SYSTEMCTL_BIN" start "$unit" 2>/dev/null || true
        done
    fi

    if command -v initctl >/dev/null 2>&1; then
        for job in $UPSTART_LIST; do
            initctl start "$job" 2>/dev/null || true
        done
    fi
    log_ok "Servicos de telemetria restaurados ao estado padrao."
}
