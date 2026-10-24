#!/bin/sh
# lib/measure.sh - Medicao de memoria RAM e processos do webOS
# Le exclusivamente /proc/meminfo e /proc/[0-9]*/status sem alterar o sistema.

MEASURE_STATE_FILE="${MOCK_ROOT}/tmp/webos_clean_measure.tmp"

# Lista de binarios conhecidos de bloat/telemetria para rastreamento
BLOAT_PROCS='
uploadd
rdxd
contentminer
nudge
com.webos.service.camera2
com.webos.service.mycar
com.webos.app.browser
com.webos.app.lgchannels
com.webos.app.livemenu
'

# Retorna MemAvailable em KB (com fallback para MemFree + Buffers + Cached)
get_mem_available_kb() {
    meminfo_file="${MOCK_ROOT}/proc/meminfo"
    [ -f "$meminfo_file" ] || { echo "0"; return; }

    avail=$(awk '/^MemAvailable:/ {print $2}' "$meminfo_file" 2>/dev/null)
    if [ -n "$avail" ] && [ "$avail" -gt 0 ] 2>/dev/null; then
        echo "$avail"
        return
    fi

    # Fallback para kernels mais antigos sem MemAvailable
    awk '
        /^MemFree:/ {free=$2}
        /^Buffers:/ {buf=$2}
        /^Cached:/  {cache=$2}
        END {print (free + buf + cache)}
    ' "$meminfo_file" 2>/dev/null || echo "0"
}

# Retorna MemTotal em KB
get_mem_total_kb() {
    meminfo_file="${MOCK_ROOT}/proc/meminfo"
    [ -f "$meminfo_file" ] || { echo "0"; return; }
    awk '/^MemTotal:/ {print $2}' "$meminfo_file" 2>/dev/null || echo "0"
}

# Rastreia processos de bloat rodando e seus respectivos VmRSS (em KB)
# Formato de saida: <processo> <pid> <rss_kb>
scan_bloat_processes() {
    proc_dir="${MOCK_ROOT}/proc"
    [ -d "$proc_dir" ] || return

    for p in $BLOAT_PROCS; do
        for stat_file in "$proc_dir"/[0-9]*/stat; do
            [ -f "$stat_file" ] || continue
            cpid=$(basename "$(dirname "$stat_file")")
            cmdline="${proc_dir}/${cpid}/cmdline"
            status="${proc_dir}/${cpid}/status"
            comm="${proc_dir}/${cpid}/comm"

            matched=0
            if [ -f "$comm" ] && grep -Fq "$p" "$comm" 2>/dev/null; then
                matched=1
            elif [ -f "$cmdline" ] && grep -Fq "$p" "$cmdline" 2>/dev/null; then
                matched=1
            fi

            if [ "$matched" = "1" ] && [ -f "$status" ]; then
                rss=$(awk '/^VmRSS:/ {print $2}' "$status" 2>/dev/null)
                if [ -n "$rss" ] && [ "$rss" -gt 0 ] 2>/dev/null; then
                    echo "$p $cpid $rss"
                fi
            fi
        done
    done
}

# Captura snapshot inicial de RAM
measure_before() {
    avail_kb=$(get_mem_available_kb)
    total_kb=$(get_mem_total_kb)
    mkdir -p "$(dirname "$MEASURE_STATE_FILE")" 2>/dev/null || true

    # Salva cabecalho
    echo "MEM_BEFORE_KB=$avail_kb" > "$MEASURE_STATE_FILE"
    echo "MEM_TOTAL_KB=$total_kb" >> "$MEASURE_STATE_FILE"

    # Salva lista de processos rodando antes
    scan_bloat_processes >> "$MEASURE_STATE_FILE"
}

# Captura snapshot final e imprime relatorio
measure_after_and_report() {
    # Aguarda 1 segundo para a TV liberar paginas de memoria
    sleep 1

    avail_after=$(get_mem_available_kb)
    avail_before=0
    total_kb=0

    if [ -f "$MEASURE_STATE_FILE" ]; then
        avail_before=$(grep '^MEM_BEFORE_KB=' "$MEASURE_STATE_FILE" | cut -d= -f2)
        total_kb=$(grep '^MEM_TOTAL_KB=' "$MEASURE_STATE_FILE" | cut -d= -f2)
    fi

    [ -n "$avail_before" ] || avail_before=0
    [ -n "$avail_after" ] || avail_after=0
    [ -n "$total_kb" ] || total_kb=0

    # Conversao para MB formatado
    mb_before=$(awk -v k="$avail_before" 'BEGIN {printf "%.1f", k / 1024}')
    mb_after=$(awk -v k="$avail_after" 'BEGIN {printf "%.1f", k / 1024}')
    mb_total=$(awk -v k="$total_kb" 'BEGIN {printf "%.1f", k / 1024}')

    gain_kb=$((avail_after - avail_before))
    if [ "$gain_kb" -lt 0 ]; then
        gain_kb=0
    fi
    mb_gain=$(awk -v k="$gain_kb" 'BEGIN {printf "%.1f", k / 1024}')

    pct_gain="0.0"
    if [ "$avail_before" -gt 0 ]; then
        pct_gain=$(awk -v b="$avail_before" -v g="$gain_kb" 'BEGIN {printf "%.1f", (g / b) * 100}')
    fi

    printf "\n"
    printf "%b=========================================================%b\n" "$C_CYAN" "$C_RESET"
    printf "%b              RELATÓRIO DE IMPACTO DE MEMÓRIA RAM         %b\n" "$C_BOLD" "$C_RESET"
    printf "%b=========================================================%b\n" "$C_CYAN" "$C_RESET"
    printf " Total Físico da TV       : %7s MB\n" "$mb_total"
    printf " Disponível Inicial       : %7s MB\n" "$mb_before"
    printf " Disponível Pós-Limpeza   : %7s MB\n" "$mb_after"
    printf "%b Ganho Efetivo Liberado   : +%6s MB (+%s%%)%b\n" "$C_GREEN" "$mb_gain" "$pct_gain" "$C_RESET"
    printf "%b---------------------------------------------------------%b\n" "$C_CYAN" "$C_RESET"
    printf " Processos de Telemetria / Preload Encerrados:\n"

    # Processos que estavam no state file e agora nao estao rodando
    found_any=0
    if [ -f "$MEASURE_STATE_FILE" ]; then
        while read -r p cpid rss; do
            case "$p" in
                MEM_*) continue ;;
                *)
                    # Verifica se o processo ainda esta ativo
                    if [ ! -d "${MOCK_ROOT}/proc/$cpid" ] || ! grep -Fq "$p" "${MOCK_ROOT}/proc/$cpid/comm" 2>/dev/null; then
                        rss_mb=$(awk -v r="$rss" 'BEGIN {printf "%.1f", r / 1024}')
                        printf "   %b✓%b %-30s : ~%5s MB liberados\n" "$C_GREEN" "$C_RESET" "$p" "$rss_mb"
                        found_any=1
                    fi
                    ;;
            esac
        done < "$MEASURE_STATE_FILE"
    fi

    if [ "$found_any" = "0" ]; then
        printf "   (Nenhum processo pesado em cache estava rodando no momento)\n"
    fi
    printf "%b=========================================================%b\n" "$C_CYAN" "$C_RESET"

    rm -f "$MEASURE_STATE_FILE" 2>/dev/null || true
}
