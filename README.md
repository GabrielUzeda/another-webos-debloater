# webOS Clean

Projeto unificado de **limpeza e otimização** para TVs LG webOS com root
(Homebrew Channel). Reúne, em um só lugar, as técnicas de debloat/otimização
encontradas em quatro referências open source, descartando tudo que não seja
limpeza — sem dashboards, sem integração de casa inteligente, sem features.

## Propósito

Extrair o máximo de otimização possível de uma TV webOS:

- **RAM**: parar o preload de apps que a TV mantém residentes sem uso.
- **CPU / processos**: desativar serviços de background e overlays de anúncio.
- **Tela inicial**: remover tiles, prateleiras ("recommended shelf"), qcards e
  vídeos promocionais do LG Home.
- **Telemetria**: desligar ACR/Live Plus, IDs de anúncio, acordos de dados e
  endpoints de diagnóstico.
- **Armazenamento**: remover apps de demonstração/fábrica.

## Regras do projeto

1. **Só limpeza e otimização.** Nenhuma feature nova, nenhum dashboard, nenhum
   app de produtividade.
2. **Nada é apagado.** O rootfs é somente leitura e assinado; toda mudança é
   bind mount, arquivo em `/var` ou ajuste via serviço da própria LG.
3. **Tudo reversível.** Cada técnica tem caminho de volta.
4. **Instalar app só se for para substituir algo mais pesado da webOS**
   (ex.: trocar o LG Home por um launcher mais leve). Fora disso, só desligar e
   esconder.
5. Sobreviver a update de firmware e reboot.

## Referências

Clonadas em `referencias/` (não versionadas).

| Pasta | Origem | O que aproveitamos | Licença |
|---|---|---|---|
| `referencias/gist-lucataco` | [gist 7c303b4](https://gist.github.com/lucataco/7c303b443934008a9031a55cfca552ec) | `webos-debloat.sh`: lista de bloqueio de apps da LG (`blockedSystemAppList`), política de preload, settings de promoção/ACR, hook de boot, listas curadas de bloat e `PROTECTED_IDS` | MIT |
| `referencias/glasshouse` | [rorygallagher2024/glasshouse](https://github.com/rorygallagher2024/glasshouse) | `server/lib/preload.js`, `services.js` (mask de systemd), `privacy.js` (ACR/acordos), `apps.js` (sumir tile via bind mount de `appinfo.json`), `homescreen-webos9.js` / `homescreen-webos10.js` (limpeza do LG Home) | MIT |
| `referencias/webos10-homescreen-customization` | [mareklarek/webos10-homescreen-customization](https://github.com/mareklarek/webos10-homescreen-customization) | Como o Home do webOS 10 é um app Flutter com `home.xml` + i18n, e o overlay por bind mount em `/tmp` para reescrever layout, remover shelfs e trocar textos | ver `LICENSE` |
| `referencias/free-my-tv` | [simbasjungles/free-my-tv](https://github.com/simbasjungles/free-my-tv) | Referência de **substituição** do launcher: empacotamento `.ipk` sem as ferramentas da LG (`webos/build.py`, `install.py`) e o padrão lista-`DEBLOAT` + lista-`PROTECTED` | ver `LICENSE` |

Todas as referências são projetos independentes, não afiliados à LG.

## Estrutura

```
.
├── README.md          # este arquivo
├── .gitignore
├── relatorio.md       # levantamento bruto (código copiado), NÃO versionado
└── referencias/       # clones upstream, NÃO versionados
```

## Status

Levantamento em andamento. `relatorio.md` consolida o código relevante das
quatro fontes, separado por técnica. O script unificado ainda não foi escrito.

## Risco

Root em TV webOS pode brickar o aparelho e anula a garantia. Toda técnica aqui
foi escrita por terceiros e testada em modelos específicos — não em todos.
Sempre `--plan`/`--dry-run` primeiro, e SSH com chave em vez do telnet do
Homebrew Channel (que é shell root sem autenticação aberto na rede).
