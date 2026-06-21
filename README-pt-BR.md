# 🔥 Seu Mac travando? O Claude entrega o culpado.

[English](README.md) · [한국어](README-ko.md) · [简体中文](README-zh-Hans.md) · [繁體中文](README-zh-Hant.md) · [日本語](README-ja.md) · [Español](README-es.md) · [Deutsch](README-de.md) · [Français](README-fr.md) · **Português** · [Русский](README-ru.md)

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-F05138?logo=swift&logoColor=white)
![Menu bar app](https://img.shields.io/badge/menu--bar-no%20Dock%20icon-success)

**Seu Mac engasga → o Claude aponta o processo exato que está sugando tudo → um clique o encerra. Nada acontece até você clicar — zero risco.**

A cada hora, a carga do seu Mac vai para o Claude. Ele ranqueia o que *de verdade* está devorando sua CPU/RAM, escreve a correção exata e a entrega na sua barra de menus — pior primeiro, com código de cores, a um clique de distância. E antes de qualquer coisa rodar, uma *segunda* passagem do Claude precisa liberar o comando como **SAFE**.

O **Mac Optimizing Looper** é um app de barra de menus do macOS (sem ícone no Dock) que roda um ciclo contínuo de **observar → perguntar ao modelo → aconselhar → (opcionalmente) agir** via a CLI do seu LLM local.

[**⬇ Instalar**](#instalação) · [**Veja funcionando ↓**](#como-funciona)

<p align="center"><img src="docs/menu.png" alt="Menu do Mac Optimizing Looper — correções ranqueadas e coloridas por severidade" width="540"></p>

> O Monitor de Atividade te mostra 200 linhas e zero respostas. Isto te mostra o **único comando** que resolve — e o porquê.

## Como funciona

Um ciclo, de cima a baixo:

```
⏱  timer fires (default: every 1h, slider 10m … 36h)
→  collect: CPU/MEM + mac-optimizer snapshot (+ optional sustained sample)
→  claude -p   (analysis pass, --effort max)
→  claude -p   (format pass → ranked JSON suggestions)
```

A barra de menus mostra a contagem. A lista suspensa vem ranqueada **do pior primeiro**: 🔴 crítico → 🟡 aviso → 🟢 higiene. Cada linha te dá: **Copiar** · **Mostrar no Terminal** · **Revisar com o Claude** · **Executar Comando Agora**.

## A trava de segurança — por que ele não vai detonar seu Mac

"Executar Comando Agora" é o **único** caminho que executa algo, e é blindado de ponta a ponta:

```
click ▸ Run Command Now   ($ kill 8123)
→  claude -p   classifies → RISK: SAFE
→  background run   (sudo → GUI password prompt, because there's no TTY)
→  ✅ notification → click → full stdout/stderr window
→  suggestion marked ✓ done
```

Qualquer coisa que não seja classificada como `SAFE` — **inclusive `unknown`** — abre uma caixa de confirmação cujo botão padrão é **Cancelar**. O conselho fica inerte; o modelo nunca consegue fazer o app rodar coisa alguma. Esse contrato é trancado a sete chaves pelos `GuardrailTests`.

## Mac Optimizing Looper vs. os suspeitos de sempre

| | Monitor de Atividade | Apps "limpadores" | **Mac Optimizing Looper** |
|---|---|---|---|
| Acha o culpado de verdade | você lê 200 linhas | chuta | 🟢 o Claude ranqueia do pior primeiro |
| Diz *por que* está lento | ✗ | ✗ | 🟢 motivo em português claro |
| Dá a correção exata | ✗ | "limpeza" genérica | 🟢 o comando `kill` / `unload` de verdade |
| Age por conta própria | — | 🔴 sim, num agendamento | 🟢 nunca — só no seu clique |
| Trava de segurança antes de rodar | — | ✗ | 🟢 segunda passagem do Claude libera como `SAFE` |
| Para onde vão seus dados | local | varia | só para a sua própria CLI do Claude |

## Instalação

Precisa da CLI `claude` no seu PATH. macOS 13+.

```bash
brew install --cask kargnas/tap/mac-optimizing-looper
```

> O cask + DMG entram no ar depois do primeiro release assinado. O pipeline já está montado e só aguarda os secrets de assinatura — veja [docs/release-setup.md](docs/release-setup.md). Até lá, compile a partir do código-fonte:

```bash
git clone https://github.com/kargnas/mac-optimizing-looper
cd mac-optimizing-looper
bash script/build_and_run.sh run     # builds the .app, codesigns ad-hoc, launches
```

Rode o **bundle**, não o binário cru — o `UNUserNotificationCenter` exige um bundle id de verdade (`as.kargn.MacOptimizingLooper`).

## Deixe do seu jeito

Escolha **Provedor / Modelo / Velocidade / Modo Rápido** em Configurações — modelos e níveis de raciocínio são lidos **ao vivo** de cada CLI. O backend padrão é a CLI `claude`; o `codex` também é suportado (uma passagem única restrita por schema, sem etapa de formatação separada). A interface fala **10 idiomas**, e o seletor de **Idioma** muda tanto a interface *quanto* o idioma de saída da análise.

<p align="center"><img src="docs/settings.png" alt="Configurações do Mac Optimizing Looper — provedor, modelo, idioma, intervalo" width="520"></p>

## Perguntas frequentes

**Ele chega a rodar algo sozinho?**
Não. O conselho fica inerte. O único jeito de executar algo é o botão "Executar Comando Agora", no seu clique — garantido pelos `GuardrailTests`.

**É seguro apertar "Executar"?**
Todo comando passa por uma segunda passagem do Claude. Qualquer coisa que não seja claramente `SAFE` (inclusive `unknown`) abre uma caixa de confirmação com **Cancelar** como padrão. O `sudo` passa pela solicitação de senha gráfica do macOS.

**Meus dados saem do meu Mac?**
Só as métricas ao vivo + a tabela de processos, e apenas para a Anthropic via a *sua própria* CLI `claude` (ou para a OpenAI via `codex`) — exatamente como se você mesmo usasse essa CLI. O app não adiciona nenhuma telemetria.

**Quanto custa?**
Nada além do uso que você já faz da CLI `claude` / `codex`. O app é gratuito e licenciado sob MIT.

**Sem a CLI `claude` instalada?**
Então sem conselho — ele mostra o erro em vez de chutar.

<details>
<summary><b>Por dentro</b> — system prompt, ciclo completo, fluxo de decisão, configuração, limites</summary>

### System prompt (sanitized excerpt)

```
You are a macOS performance analyst.
Given live metrics + a process table, identify the ACTUAL remediation
command (kill / killall / unload) for each real problem — never an
inspection command (no pgrep / ps / top).

MUST:     rank by severity; prefer graceful `kill <pid>` over `kill -9`.
MUST:     return a null command when no command-line action applies.
MUST NOT: claim anything was executed — the app never auto-runs.
```

### O que cada ciclo pode afetar

| Passo | Ferramenta | Efeito colateral |
|---|---|---|
| Coletar | `MetricsCollector`, `mac-optimizer.sh` | somente leitura |
| Analisar | `claude -p` (effort = max) | rede, somente leitura |
| Formatar | `claude -p` (effort = low) | JSON ranqueado |
| Verificar risco | `claude -p` | rede, somente leitura |
| Executar | `CommandExecutor` | **roda o comando** (só iniciado pelo usuário) |
| Revisar | terminal configurado + `claude` interativo | abre um terminal |

### Fluxo de decisão

```
timer → collect → claude analyze → rank suggestions
                                       │
                 user picks an action ─┼─ Copy / Show in Terminal → no execution
                                       ├─ Review with Claude       → interactive claude session
                                       └─ Run Command Now
                                              → claude risk-check
                                                   ├─ SAFE → run → notify → ✓
                                                   └─ else → confirm (default Cancel)
```

### Configuração

A configuração fica em `~/.config/mac-optimizing-looper/config.json` (copie de `config.example.json`): provedor, modelo, nível de raciocínio, segundos de monitoramento, intervalo, terminal, idioma. É lida uma única vez no início — reinicie depois de editar à mão.

### Limites / o que ele recusa

- **Nunca age por conta própria.** Só "Executar Comando Agora" executa, e somente no seu clique.
- **Risco desconhecido = tratado como perigoso.** À prova de falhas; você confirma.
- **`sudo` → solicitação de senha gráfica.** Uma execução em segundo plano não tem TTY, então comandos de root passam por `osascript … with administrator privileges`.
- **Sem a CLI `claude` = sem conselho.** Ele mostra o erro em vez de chutar.
- As notificações precisam do bundle do app; um binário cru abre a janela de resultado diretamente.

</details>

---

Licenciado sob MIT. Feito para quem prefere saber *por que* o Mac está lento do que reiniciar e torcer pra melhorar.
