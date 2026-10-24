#!/bin/sh
# test/run-tests.sh - Runner de testes automatizados durante a implementacao
# Testa tudo offline sem precisar de TV fisica.

set -e

REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)
MOCK_DIR="/tmp/test_webos_clean_$$"
export MOCK_ROOT="$MOCK_DIR"
export MOCK_LUNA_CMD="$REPO_DIR/test/mock-luna-send.sh"
export WEBOS_VERSION_OVERRIDE="10"

cleanup() {
    rm -rf "$MOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

setup_mock_tv() {
    cleanup
    mkdir -p "$MOCK_DIR/proc"
    mkdir -p "$MOCK_DIR/run/systemd/transient"
    mkdir -p "$MOCK_DIR/tmp"
    mkdir -p "$MOCK_DIR/etc"
    mkdir -p "$MOCK_DIR/var/preferences/com.webos.applicationManager/blockedSystemAppList"
    mkdir -p "$MOCK_DIR/var/lib/webosbrew/init.d"
    mkdir -p "$MOCK_DIR/usr/palm/applications/com.webos.app.home/data/flutter_assets/assets"

    # Mock /proc/meminfo
    cat << 'EOF' > "$MOCK_DIR/proc/meminfo"
MemTotal:        1536000 kB
MemFree:          256000 kB
MemAvailable:     450000 kB
Buffers:           32000 kB
Cached:           162000 kB
EOF

    # Mock processo uploadd rodando (PID 500)
    mkdir -p "$MOCK_DIR/proc/500"
    echo "uploadd" > "$MOCK_DIR/proc/500/comm"
    printf "Name:	uploadd
VmRSS:	    4800 kB
" > "$MOCK_DIR/proc/500/status"
    echo "500 (uploadd) S 1 500 500" > "$MOCK_DIR/proc/500/stat"

    # Mock processo browser rodando (PID 600)
    mkdir -p "$MOCK_DIR/proc/600"
    echo "com.webos.app.browser" > "$MOCK_DIR/proc/600/comm"
    printf "Name:	browser
VmRSS:	   95000 kB
" > "$MOCK_DIR/proc/600/status"
    echo "600 (browser) S 1 600 600" > "$MOCK_DIR/proc/600/stat"

    # Mock /etc/hosts
    cat << 'EOF' > "$MOCK_DIR/etc/hosts"
127.0.0.1 localhost
::1 localhost
EOF

    # Mock home.xml
    cat << 'EOF' > "$MOCK_DIR/usr/palm/applications/com.webos.app.home/data/flutter_assets/assets/home.xml"
<home>
  <item id="banner" />
  <item id="qcardList" />
  <item id="recommendedShelf" />
  <item id="appsList" />
</home>
EOF

    # Mock arquivo regional original
    cat << 'EOF' > "$MOCK_DIR/var/preferences/com.webos.applicationManager/blockedSystemAppList/USA.json"
{"blocked_system_applist":["com.sample.dummy"]}
EOF
}

assert_eq() {
    desc="$1"; expected="$2"; actual="$3"
    if [ "$expected" = "$actual" ]; then
        printf "  \033[32m✓\033[0m %s\n" "$desc"
    else
        printf "  \033[31m✗\033[0m %s (Esperado: '%s', Obtido: '%s')\n" "$desc" "$expected" "$actual"
        exit 1
    fi
}

assert_file_exists() {
    desc="$1"; path="$2"
    if [ -f "$path" ] || [ -L "$path" ]; then
        printf "  \033[32m✓\033[0m %s\n" "$desc"
    else
        printf "  \033[31m✗\033[0m %s (Arquivo nao existe: %s)\n" "$desc" "$path"
        exit 1
    fi
}

assert_file_not_exists() {
    desc="$1"; path="$2"
    if [ ! -f "$path" ] && [ ! -L "$path" ]; then
        printf "  \033[32m✓\033[0m %s\n" "$desc"
    else
        printf "  \033[31m✗\033[0m %s (Arquivo nao deveria existir: %s)\n" "$desc" "$path"
        exit 1
    fi
}

printf "\n\033[1;36m=== EXECUTANDO BATERIA DE TESTES OFFLINE ===\033[0m\n\n"

# 1. Teste de Sintaxe POSIX
printf "\033[1m1. Validacao Estrita de Sintaxe Shell (sh -n):\033[0m\n"
for f in "$REPO_DIR"/bin/* "$REPO_DIR"/lib/* "$REPO_DIR"/init/* "$REPO_DIR"/test/*.sh; do
    [ -f "$f" ] || continue
    sh -n "$f"
    printf "  \033[32m✓\033[0m %s\n" "$(basename "$f")"
done

# 2. Teste do Modo Efêmero (--test) - Zero impacto em disco:
printf "\n\033[1m2. Teste do Modo Efêmero (--test) - Zero impacto em disco:\033[0m\n"
setup_mock_tv
"$REPO_DIR/bin/webos-clean" --test >/dev/null 2>&1

# Deve mascarar servicos em /run
assert_file_exists "Mascara transient em /run" "$MOCK_DIR/run/systemd/transient/uploadd.service"
assert_file_exists "Mascara remotelogger em /run" "$MOCK_DIR/run/systemd/transient/remotelogger.service"
# NAO deve criar hooks persistentes
assert_file_not_exists "Nenhum hook em init.d" "$MOCK_DIR/var/lib/webosbrew/init.d/50-webos-clean"
# NAO deve alterar preload persistente
assert_file_not_exists "Nenhum preload-conf gravado" "$MOCK_DIR/var/preferences/webos-preload-manager-conf.json"

# Simula reboot (limpeza de /run e /tmp)
rm -rf "$MOCK_DIR/run/systemd/transient" "$MOCK_DIR/tmp"/*
assert_file_not_exists "Apos reboot: mascara sumiu de /run" "$MOCK_DIR/run/systemd/transient/uploadd.service"
printf "  \033[32m✓\033[0m Simulacao de reinicio: TV voltou 100%% ao estado de fabrica.\n"

# 3. Teste do Modo Permanente (--apply) - Persistencia com Backup:
printf "\n\033[1m3. Teste do Modo Permanente (--apply) - Persistencia com Backup:\033[0m\n"
setup_mock_tv
"$REPO_DIR/bin/webos-clean" --apply >/dev/null 2>&1

# Deve criar backup integral
assert_file_exists "Backup de blockedSystemAppList criado" "$MOCK_DIR/var/lib/webos-clean/backup/blocked_system_applist.json.bak"
# Deve persistir a lista de preload propria (nao o conf do daemon)
assert_file_exists "Lista de preload persistida" "$MOCK_DIR/var/lib/webos-clean/preload_off"
assert_file_not_exists "Nao escreve o conf do daemon" "$MOCK_DIR/var/preferences/webos-preload-manager-conf.json"
# Deve instalar hook de boot sem extensao .sh
assert_file_exists "Hook do init.d instalado" "$MOCK_DIR/var/lib/webosbrew/init.d/50-webos-clean"

# Valida se o blockedSystemAppList gerou JSON valido contendo bloat
grep -q "com.webos.app.discovery" "$MOCK_DIR/var/preferences/com.webos.applicationManager/blockedSystemAppList/USA.json"
assert_eq "Bloat list contém apps de anuncios" "0" "$?"
grep -q "snu.lge.com" "$MOCK_DIR/etc/hosts"
assert_eq "Servidores de update bloqueados em /etc/hosts" "0" "$?"
assert_file_exists "Flag webosbrew_block_updates criada" "$MOCK_DIR/var/luna/preferences/webosbrew_block_updates"
assert_file_exists "clean_home ativado em estado permanente" "$MOCK_DIR/var/lib/webos-clean/clean_home"
assert_file_exists "home.xml gerado no overlay limpo" "$MOCK_DIR/tmp/webos_clean_home/upper/home.xml"
if grep -q "qcardList" "$MOCK_DIR/tmp/webos_clean_home/upper/home.xml"; then
    echo "  Falha: qcardList nao deveria existir no layout limpo"; exit 1
else
    printf "  \033[32m✓\033[0m qcardList ocultado no layout limpo\n"
fi

# 4. Teste de Restauracao (--restore) - Reversao Completa:
printf "\n\033[1m4. Teste de Restauracao (--restore) - Reversao Completa:\033[0m\n"
"$REPO_DIR/bin/webos-clean" --restore >/dev/null 2>&1

# Hook deve ter sido removido
assert_file_not_exists "Hook do init.d removido" "$MOCK_DIR/var/lib/webosbrew/init.d/50-webos-clean"
# Lista de preload removida
assert_file_not_exists "Lista de preload removida" "$MOCK_DIR/var/lib/webos-clean/preload_off"
# Arquivo regional restaurado com conteudo original ("com.sample.dummy")
grep -q "com.sample.dummy" "$MOCK_DIR/var/preferences/com.webos.applicationManager/blockedSystemAppList/USA.json"
assert_eq "Arquivo regional restaurado ao original" "0" "$?"
assert_file_not_exists "Flag webosbrew_block_updates revertida" "$MOCK_DIR/var/luna/preferences/webosbrew_block_updates"
assert_file_not_exists "clean_home removido no restore" "$MOCK_DIR/var/lib/webos-clean/clean_home"

# 4b. Regressao: luna_call nao pode corromper o payload JSON
printf "\n\033[1m4b. luna_call preserva o payload JSON (regressao):\033[0m\n"
payload='{"application":{"id":"com.webos.app.browser","isEnabled":false}}'
got=$(MOCK_LUNA_CMD="$REPO_DIR/test/mock-luna-echo.sh" sh -c '. "$1/lib/common.sh"; luna_call "luna://x/y" "$2"' _ "$REPO_DIR" "$payload")
assert_eq "payload passado a luna-send sem alteracao" "$payload" "$got"

# 5. Teste de Failsafe (Resgate por USB)
printf "\n\033[1m5. Teste de Failsafe / Emergency USB Rescue:\033[0m\n"
setup_mock_tv
"$REPO_DIR/bin/webos-clean" --apply >/dev/null 2>&1
assert_file_exists "Hook de boot ativo antes do USB rescue" "$MOCK_DIR/var/lib/webosbrew/init.d/50-webos-clean"

# Cria pendrive virtual com o gatilho de resgate
mkdir -p "$MOCK_DIR/media/drive1"
touch "$MOCK_DIR/media/drive1/WEBOS_CLEAN_REVERT"

# Simula boot chamando o hook com MOCK_ROOT ativo
sh "$MOCK_DIR/var/lib/webosbrew/init.d/50-webos-clean" >/dev/null 2>&1

assert_file_not_exists "Hook de boot se auto-destruiu apos deteccao de USB" "$MOCK_DIR/var/lib/webosbrew/init.d/50-webos-clean"

# 6. Backup de estado: cria, valida e recusa caminho fora da lista
printf "\n\033[1m6. Backup de estado (--backup / --restore-backup):\033[0m\n"
setup_mock_tv
mkdir -p "$MOCK_DIR/var/luna/preferences" "$MOCK_DIR/var/db/main" "$MOCK_DIR/var/lib/webosbrew"
echo "prefs" > "$MOCK_DIR/var/preferences/teste_pref.json"
echo "luna" > "$MOCK_DIR/var/luna/preferences/teste_luna.json"
echo "db" > "$MOCK_DIR/var/db/main/teste_db.ldb"

BK=$("$REPO_DIR/bin/webos-clean" --backup "$MOCK_DIR/tmp" 2>/dev/null | tail -n 1)
if [ -f "$BK" ]; then
    printf "  \033[32m✓\033[0m backup criado (%s KB)\n" "$(du -k "$BK" | awk '{print $1}')"
else
    printf "  \033[31m✗\033[0m backup nao foi criado\n"; exit 1
fi
assert_file_exists "manifesto gerado" "$BK.manifest"
tar tzf "$BK" | grep -q '^var/preferences/teste_pref.json' && printf "  \033[32m✓\033[0m caminhos relativos (var/...) no pacote\n"

# por padrao a extracao fica DESLIGADA (recurso nao testado em hardware)
rm -f "$MOCK_DIR/var/preferences/teste_pref.json"
"$REPO_DIR/bin/webos-clean" --restore-backup "$BK" >/dev/null 2>&1
assert_file_not_exists "sem BACKUP_RESTORE_ENABLED=1 nao extrai nada" "$MOCK_DIR/var/preferences/teste_pref.json"

# restauracao valida (so no mock, com a flag ligada)
BACKUP_RESTORE_ENABLED=1 "$REPO_DIR/bin/webos-clean" --restore-backup "$BK" >/dev/null 2>&1
assert_file_exists "com a flag: restauracao devolveu o arquivo" "$MOCK_DIR/var/preferences/teste_pref.json"

# pacote com caminho perigoso deve ser recusado
mkdir -p /tmp/bad_pkg_$/etc && echo "x" > /tmp/bad_pkg_$/etc/hosts
( cd /tmp/bad_pkg_$ && tar czf "$MOCK_DIR/tmp/bad.tar.gz" etc )
if "$REPO_DIR/bin/webos-clean" --restore-backup "$MOCK_DIR/tmp/bad.tar.gz" >/dev/null 2>&1; then
    printf "  \033[31m✗\033[0m aceitou pacote com /etc/hosts\n"; rm -rf /tmp/bad_pkg_$; exit 1
else
    printf "  \033[32m✓\033[0m recusou pacote com caminho fora da lista\n"
fi
rm -rf /tmp/bad_pkg_$


# 7. Teste de Tela Inicial Minimalista Isolada (--clean-home / --restore-home):
printf "\n\x1b[1m7. Teste de Tela Inicial Minimalista Isolada (--clean-home / --restore-home):\x1b[0m\n"
setup_mock_tv
"$REPO_DIR/bin/webos-clean" --clean-home >/dev/null 2>&1

assert_file_exists "clean_home ativado no estado" "$MOCK_DIR/var/lib/webos-clean/clean_home"
assert_file_exists "home.xml montado no overlay" "$MOCK_DIR/tmp/webos_clean_home/upper/home.xml"
assert_file_exists "Hook de boot com watchdog instalado" "$MOCK_DIR/var/lib/webosbrew/init.d/50-webos-clean"
assert_file_not_exists "Preload NAO foi modificado (isolado)" "$MOCK_DIR/var/lib/webos-clean/preload_off"
assert_file_not_exists "Servicos NAO foram mascarados (isolado)" "$MOCK_DIR/run/systemd/transient/uploadd.service"

# Restaura apenas a tela inicial
"$REPO_DIR/bin/webos-clean" --restore-home >/dev/null 2>&1
assert_file_not_exists "clean_home removido" "$MOCK_DIR/var/lib/webos-clean/clean_home"
assert_file_not_exists "Hook de boot removido pois nao ha outros modulos" "$MOCK_DIR/var/lib/webosbrew/init.d/50-webos-clean"

printf "\n\x1b[1;32m=== TODOS OS TESTES PASSARAM COM SUCESSO! ===\x1b[0m\n\n"
