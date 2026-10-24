#!/bin/sh
# lib/backup.sh - Backup e restauracao do ESTADO do sistema (nao do firmware)
#
# O que entra: os diretorios gravaveis que guardam configuracao e dados.
# O que NAO entra, de proposito:
#   - firmware/rootfs (squashfs assinado + dm-verity): copiar nao recupera nada
#     e regravar particao a mao e o caminho mais curto para brickar a TV. A
#     volta de firmware quebrado e o modo de recuperacao da LG (USB), nao dd.
#   - /media/developer/apps (~1.5 GB): apps do Homebrew se reinstalam.
#
# Caminhos relativos: o tar e criado com -C "${MOCK_ROOT}/" e extraido com
# -C /, entao "var/preferences" vira /var/preferences na TV.
BACKUP_SUBDIRS='var/preferences var/luna/preferences var/db var/lib/webosbrew var/lib/webos-clean'

backup_path_allowed() {
    for p in $BACKUP_SUBDIRS; do
        case "$1" in
            "$p"|"$p"/*|"/$p"|"/$p"/*) return 0 ;;
        esac
    done
    return 1
}

# Cria o tarball do estado em OUTDIR (padrao /tmp) e imprime o caminho
backup_create() {
    outdir="${1:-/tmp}"
    stamp=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo manual)
    out="$outdir/webos-clean-state-$stamp.tar.gz"

    mkdir -p "$outdir" 2>/dev/null || die "nao consegui criar $outdir"

    log_info "Empacotando estado do sistema em $out ..."
    # Só os subdiretorios que existem de fato
    present=''
    for p in $BACKUP_SUBDIRS; do
        [ -e "${MOCK_ROOT}/$p" ] && present="$present $p"
    done
    [ -n "$present" ] || die "nenhum diretorio de estado encontrado"

    # shellcheck disable=SC2086
    tar czf "$out" -C "${MOCK_ROOT}/" $present 2>/dev/null
    [ -s "$out" ] || die "falhou ao criar $out (sem espaco?)"

    size_kb=$(du -k "$out" 2>/dev/null | awk '{print $1}')
    sum=$(sha256sum "$out" 2>/dev/null | awk '{print $1}')
    ver=$(detect_webos_version)

    cat > "${out}.manifest" <<EOF
date=$(date 2>/dev/null)
webos=$ver
kernel=$(uname -r 2>/dev/null)
host=$(hostname 2>/dev/null)
size_kb=$size_kb
sha256=$sum
paths=$present
note=snapshot de configuracao; nao inclui firmware nem apps do Homebrew
EOF

    log_ok "Backup criado: $out (${size_kb} KB)"
    printf '%s\n' "$out"
}

# Restaura um tarball criado por backup_create (recusa caminhos fora da lista).
#
# !!! NAO TESTADO EM HARDWARE !!!
# A extracao de verdade fica DESLIGADA por padrao. So roda com
# BACKUP_RESTORE_ENABLED=1 no ambiente, e nenhum modo do CLI define isso.
# Antes de ligar: testar em TV de bancada, porque sobrescrever /var/db e
# /var/preferences com um snapshot antigo pode deixar o settingsservice e o SAM
# inconsistentes. A validacao (lista de caminhos + sha256) roda sempre.
backup_restore() {
    file="$1"
    [ -n "$file" ] || die "informe o arquivo: --restore-backup <arquivo>"
    [ -f "$file" ] || die "arquivo nao encontrado: $file"

    log_info "Validando conteudo de $file ..."
    entries=$(tar tzf "$file" 2>/dev/null) || die "tarball ilegivel: $file"
    [ -n "$entries" ] || die "tarball vazio: $file"

    bad=0
    for entry in $entries; do
        case "$entry" in
            /*) log_err "caminho absoluto no pacote: $entry"; bad=1; continue ;;
        esac
        backup_path_allowed "$entry" || { log_err "fora da lista: $entry"; bad=1; }
    done
    [ "$bad" = "0" ] || die "backup recusado: contem caminhos que nao restauramos."

    if [ -f "${file}.manifest" ]; then
        log_info "Manifesto:"
        sed 's/^/  /' "${file}.manifest"
        want=$(sed -n 's/^sha256=//p' "${file}.manifest")
        got=$(sha256sum "$file" 2>/dev/null | awk '{print $1}')
        if [ -n "$want" ] && [ "$want" != "$got" ]; then
            die "sha256 nao confere (arquivo corrompido)"
        fi
        log_ok "sha256 confere."
    fi

    if [ "${BACKUP_RESTORE_ENABLED:-0}" != "1" ]; then
        log_warn "Pacote VALIDADO, mas a extracao esta DESATIVADA."
        log_warn "Recurso implementado e nao testado em hardware."
        log_warn "Para habilitar (por sua conta e risco): BACKUP_RESTORE_ENABLED=1 $0 --restore-backup <arquivo>"
        return 0
    fi

    # --- extracao: so chega aqui com BACKUP_RESTORE_ENABLED=1 ---
    log_info "Restaurando sobre / ..."
    tar xzf "$file" -C "${MOCK_ROOT}/" 2>/dev/null || die "falhou ao extrair"
    sync 2>/dev/null || true
    log_ok "Estado restaurado. Recomendado reiniciar a TV."
}
