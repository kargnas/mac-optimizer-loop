# 🔥 Tu Mac va lento. Claude caza al culpable.

[English](README.md) · [한국어](README-ko.md) · [简体中文](README-zh-Hans.md) · [繁體中文](README-zh-Hant.md) · [日本語](README-ja.md) · **Español** · [Deutsch](README-de.md) · [Français](README-fr.md) · [Português](README-pt-BR.md) · [Русский](README-ru.md)

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-F05138?logo=swift&logoColor=white)
![Menu bar app](https://img.shields.io/badge/menu--bar-no%20Dock%20icon-success)

**Tu Mac se ahoga → Claude señala el proceso exacto que se lo está comiendo → un clic lo mata. Nunca actúa por su cuenta.**

Cada hora, la carga de tu Mac viaja a Claude. Clasifica lo que *de verdad* está devorando tu CPU/RAM, escribe la solución exacta y la suelta en tu barra de menús: lo peor primero, con código de color, a un clic de distancia. Y antes de ejecutar nada, una *segunda* pasada de Claude tiene que dar luz verde al comando como **SAFE**.

**Mac Optimizing Looper** es una app de barra de menús para macOS (sin icono en el Dock) que ejecuta un bucle continuo de **observar → preguntar al modelo → aconsejar → (opcionalmente) actuar** sobre tu CLI de LLM local.

[**⬇ Instalar**](#instalación) · [**Míralo en acción ↓**](#cómo-funciona)

<p align="center"><img src="docs/menu.png" alt="Menú de Mac Optimizing Looper — soluciones clasificadas y coloreadas por severidad" width="540"></p>

> El Monitor de Actividad te muestra 200 filas y cero respuestas. Esto te muestra el **único comando** que lo arregla — y por qué.

## Cómo funciona

Un ciclo, de arriba abajo:

```
⏱  timer fires (default: every 1h, slider 10m … 36h)
→  collect: CPU/MEM + mac-optimizer snapshot (+ optional sustained sample)
→  claude -p   (analysis pass, --effort max)
→  claude -p   (format pass → ranked JSON suggestions)
```

La barra de menús muestra el recuento. El desplegable va ordenado de **peor a mejor**: 🔴 crítico → 🟡 advertencia → 🟢 higiene. Cada fila se despliega en **Copy** · **Show in Terminal** · **Review with Claude** · **Run Command Now**.

## La barrera de seguridad — por qué no va a reventar tu Mac

"Run Command Now" es el **único** camino que ejecuta algo, y está blindado de principio a fin:

```
click ▸ Run Command Now   ($ kill 8123)
→  claude -p   classifies → RISK: SAFE
→  background run   (sudo → GUI password prompt, because there's no TTY)
→  ✅ notification → click → full stdout/stderr window
→  suggestion marked ✓ done
```

Cualquier cosa que no se clasifique como `SAFE` — **incluido `unknown`** — abre un diálogo de confirmación cuyo botón por defecto es **Cancelar**. El consejo en sí es dato inerte; el modelo jamás puede hacer que la app ejecute nada. Ese contrato lo dejan sellado los `GuardrailTests`.

## Mac Optimizing Looper frente a los sospechosos de siempre

| | Monitor de Actividad | Apps "limpiadoras" | **Mac Optimizing Looper** |
|---|---|---|---|
| Encuentra al culpable de verdad | te lees 200 filas | adivina | 🟢 Claude ordena lo peor primero |
| Te dice *por qué* va lento | ✗ | ✗ | 🟢 motivo en lenguaje claro |
| Te da la solución exacta | ✗ | un "limpiar" genérico | 🟢 el comando `kill` / `unload` real |
| Actúa por su cuenta | — | 🔴 sí, según un horario | 🟢 nunca — solo con tu clic |
| Con barrera de seguridad antes de ejecutar | — | ✗ | 🟢 una segunda pasada de Claude lo aprueba como `SAFE` |
| Adónde van tus datos | local | depende | solo a tu propia CLI de Claude |

## Instalación

Necesita la CLI `claude` en tu PATH. macOS 13+.

```bash
brew install --cask kargnas/tap/mac-optimizing-looper
```

> El cask + DMG estarán disponibles tras la primera versión firmada. La canalización está montada y solo espera por los secretos de firma — consulta [docs/release-setup.md](docs/release-setup.md). Hasta entonces, compila desde el código fuente:

```bash
git clone https://github.com/kargnas/mac-optimizing-looper
cd mac-optimizing-looper
bash script/build_and_run.sh run     # builds the .app, codesigns ad-hoc, launches
```

Ejecuta el **bundle**, no el binario suelto: `UNUserNotificationCenter` necesita un id de bundle real (`as.kargn.MacOptimizingLooper`).

## Hazlo tuyo

Elige **Provider / Model / Speed / Fast Mode** en Ajustes — los modelos y los niveles de razonamiento se leen **en vivo** desde cada CLI. El backend por defecto es la CLI `claude`; `codex` también es compatible (una única pasada restringida por esquema, sin paso de formato aparte). La interfaz está totalmente localizada en **10 idiomas**, y el selector **Language** controla tanto la interfaz *como* el idioma de salida del análisis.

<p align="center"><img src="docs/settings.png" alt="Ajustes de Mac Optimizing Looper — proveedor, modelo, idioma, intervalo" width="520"></p>

## Preguntas frecuentes

**¿Ejecuta algo alguna vez por su cuenta?**
No. El consejo es dato inerte. La única vía de ejecución es el botón "Run Command Now", con tu clic — garantizado por `GuardrailTests`.

**¿Es seguro pulsar "Run"?**
Todo comando pasa por una segunda pasada de Claude. Cualquier cosa que no sea claramente `SAFE` (incluido `unknown`) abre un diálogo de confirmación que por defecto está en **Cancelar**. `sudo` se enruta por la solicitud de contraseña de la GUI de macOS.

**¿Salen mis datos de mi Mac?**
Solo las métricas en vivo + la tabla de procesos, y solo a Anthropic vía *tu propia* CLI `claude` (o a OpenAI vía `codex`) — exactamente igual que si usaras esa CLI tú mismo. La app no añade telemetría alguna.

**¿Cuánto cuesta?**
Nada más allá de tu uso actual de las CLI `claude` / `codex`. La app es gratuita y con licencia MIT.

**¿No tienes la CLI `claude` instalada?**
Entonces no hay consejo — muestra el error en lugar de adivinar.

<details>
<summary><b>Por dentro</b> — system prompt, ciclo completo, flujo de decisiones, configuración, límites</summary>

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

### Qué puede tocar cada ciclo

| Paso | Herramienta | Efecto secundario |
|---|---|---|
| Recopilar | `MetricsCollector`, `mac-optimizer.sh` | solo lectura |
| Analizar | `claude -p` (effort = max) | red, solo lectura |
| Formatear | `claude -p` (effort = low) | JSON clasificado |
| Verificar riesgo | `claude -p` | red, solo lectura |
| Ejecutar | `CommandExecutor` | **ejecuta el comando** (solo iniciado por el usuario) |
| Revisar | terminal configurada + `claude` interactivo | abre una terminal |

### Flujo de decisiones

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

### Configuración

La configuración vive en `~/.config/mac-optimizing-looper/config.json` (copia `config.example.json`): proveedor, modelo, nivel de razonamiento, segundos de monitorización, intervalo, terminal, idioma. Se lee una sola vez al arrancar — reinicia tras editarla a mano.

### Límites / qué rechaza

- **Nunca actúa por su cuenta.** Solo "Run Command Now" ejecuta, y solo con tu clic.
- **Riesgo desconocido = tratado como peligroso.** A prueba de fallos; tú confirmas.
- **`sudo` → solicitud de contraseña en la GUI.** Una ejecución en segundo plano no tiene TTY, así que los comandos como root pasan por `osascript … with administrator privileges`.
- **Sin la CLI `claude` = sin consejo.** Muestra el error en lugar de adivinar.
- Las notificaciones necesitan el bundle de la app; un binario suelto recurre a abrir la ventana de resultados.

</details>

---

Con licencia MIT. Hecho para quienes prefieren saber *por qué* su Mac va lento antes que reiniciar y cruzar los dedos.
