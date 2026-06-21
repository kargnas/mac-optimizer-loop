# 🔥 Dein Mac lahmt. Claude überführt den Übeltäter.

[English](README.md) · [한국어](README-ko.md) · [简体中文](README-zh-Hans.md) · [繁體中文](README-zh-Hant.md) · [日本語](README-ja.md) · [Español](README-es.md) · **Deutsch** · [Français](README-fr.md) · [Português](README-pt-BR.md) · [Русский](README-ru.md)

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-F05138?logo=swift&logoColor=white)
![Menu bar app](https://img.shields.io/badge/menu--bar-no%20Dock%20icon-success)

**Dein Mac würgt → Claude nennt exakt den Prozess, der ihn auffrisst → ein Klick beendet ihn. Von allein rührt es nie etwas an.**

Jede Stunde wandert die Auslastung deines Macs zu Claude. Es sortiert, was *wirklich* deine CPU/RAM verschlingt, schreibt den exakten Fix und legt ihn in deine Menüleiste – das Schlimmste zuerst, farbcodiert, einen Klick entfernt. Und bevor irgendetwas läuft, muss ein *zweiter* Claude-Durchlauf den Befehl als **SAFE** freigeben.

**Mac Optimizing Looper** ist eine macOS-Menüleisten-App (ohne Dock-Symbol), die auf deiner lokalen LLM-CLI eine fortlaufende Schleife aus **beobachten → das Modell fragen → beraten → (optional) handeln** ausführt.

[**⬇ Installieren**](#installation) · [**In Aktion sehen ↓**](#so-funktionierts)

<p align="center"><img src="docs/menu.png" alt="Mac Optimizing Looper Menü — nach Schweregrad sortierte, farbcodierte Fixes" width="540"></p>

> Die Aktivitätsanzeige zeigt dir 200 Zeilen und null Antworten. Das hier zeigt dir den **einen Befehl**, der es behebt – und warum.

## So funktioniert's

Ein Zyklus, von oben nach unten:

```
⏱  timer fires (default: every 1h, slider 10m … 36h)
→  collect: CPU/MEM + mac-optimizer snapshot (+ optional sustained sample)
→  claude -p   (analysis pass, --effort max)
→  claude -p   (format pass → ranked JSON suggestions)
```

Die Menüleiste zeigt die Anzahl. Das Dropdown ist nach Schweregrad sortiert, **das Schlimmste zuerst**: 🔴 critical → 🟡 warning → 🟢 hygiene. Jede Zeile klappt auf zu **Copy** · **Show in Terminal** · **Review with Claude** · **Run Command Now**.

## Die Sicherheitssperre – warum es deinen Mac nicht plattmacht

„Run Command Now" ist der **einzige** Weg, der überhaupt etwas ausführt, und er ist von Anfang bis Ende abgesichert:

```
click ▸ Run Command Now   ($ kill 8123)
→  claude -p   classifies → RISK: SAFE
→  background run   (sudo → GUI password prompt, because there's no TTY)
→  ✅ notification → click → full stdout/stderr window
→  suggestion marked ✓ done
```

Alles, was nicht als `SAFE` eingestuft ist – **einschließlich `unknown`** –, öffnet einen Bestätigungsdialog, dessen Standardschaltfläche **Cancel** ist. Der Rat selbst ist untätige Datei; das Modell kann die App niemals dazu bringen, etwas auszuführen. Diese Zusage ist durch `GuardrailTests` festgenagelt.

## Mac Optimizing Looper gegen die üblichen Verdächtigen

| | Aktivitätsanzeige | „Cleaner"-Apps | **Mac Optimizing Looper** |
|---|---|---|---|
| Findet den echten Übeltäter | du liest 200 Zeilen | rät | 🟢 Claude sortiert das Schlimmste zuerst |
| Sagt dir, *warum* es lahmt | ✗ | ✗ | 🟢 Begründung in Klartext |
| Liefert den exakten Fix | ✗ | generisches „aufräumen" | 🟢 der echte `kill`- / `unload`-Befehl |
| Handelt von allein | — | 🔴 ja, nach Zeitplan | 🟢 nie – nur auf deinen Klick |
| Vor dem Ausführen abgesichert | — | ✗ | 🟢 zweiter Claude-Durchlauf gibt ihn `SAFE` frei |
| Wohin deine Daten gehen | lokal | unterschiedlich | nur an deine eigene Claude-CLI |

## Installation

Benötigt die `claude`-CLI in deinem PATH. macOS 13+.

```bash
brew install --cask kargnas/tap/mac-optimizing-looper
```

> Cask und DMG gehen nach dem ersten signierten Release live. Die Pipeline ist verkabelt und wartet nur noch auf die Signierungs-Secrets – siehe [docs/release-setup.md](docs/release-setup.md). Bis dahin baust du es aus dem Quellcode:

```bash
git clone https://github.com/kargnas/mac-optimizing-looper
cd mac-optimizing-looper
bash script/build_and_run.sh run     # builds the .app, codesigns ad-hoc, launches
```

Führe das **Bundle** aus, nicht die nackte Binärdatei – `UNUserNotificationCenter` braucht eine echte Bundle-ID (`as.kargn.MacOptimizingLooper`).

## Mach es zu deinem

Wähle **Provider / Model / Speed / Fast Mode** in den Einstellungen – Modelle und Reasoning-Stufen werden **live** aus jeder CLI ausgelesen. Standard-Backend ist die `claude`-CLI; `codex` wird ebenfalls unterstützt (ein schema-gebundener Durchlauf, kein separater Formatierungsschritt). Die Oberfläche ist vollständig in **10 Sprachen** lokalisiert, und die Auswahl **Language** steuert sowohl die Oberfläche *als auch* die Sprache der Analyseausgabe.

<p align="center"><img src="docs/settings.png" alt="Mac Optimizing Looper Einstellungen — Provider, Modell, Sprache, Intervall" width="520"></p>

## FAQ

**Führt es jemals etwas von allein aus?**
Nein. Ratschläge sind untätige Datei. Der einzige Ausführungspfad ist die Schaltfläche „Run Command Now", auf deinen Klick – erzwungen durch `GuardrailTests`.

**Ist es sicher, auf „Run" zu drücken?**
Jeder Befehl läuft durch einen zweiten Claude-Durchlauf. Alles, was nicht eindeutig `SAFE` ist (einschließlich `unknown`), öffnet einen Bestätigungsdialog mit Standard auf **Cancel**. `sudo` läuft über die macOS-GUI-Passwortabfrage.

**Verlassen meine Daten meinen Mac?**
Nur die Live-Metriken + die Prozesstabelle, und nur an Anthropic über *deine eigene* `claude`-CLI (oder an OpenAI über `codex`) – genau so, als würdest du die CLI selbst benutzen. Die App fügt null Telemetrie hinzu.

**Was kostet es?**
Nichts über deine bestehende `claude`- / `codex`-CLI-Nutzung hinaus. Die App ist kostenlos und MIT-lizenziert.

**Keine `claude`-CLI installiert?**
Dann kein Rat – es zeigt den Fehler an, statt zu raten.

<details>
<summary><b>Unter der Haube</b> — System-Prompt, voller Zyklus, Entscheidungsablauf, Konfiguration, Grenzen</summary>

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

### Was jeder Zyklus berühren kann

| Schritt | Werkzeug | Nebenwirkung |
|---|---|---|
| Collect | `MetricsCollector`, `mac-optimizer.sh` | nur Lesezugriff |
| Analyze | `claude -p` (effort = max) | Netzwerk, nur Lesezugriff |
| Format | `claude -p` (effort = low) | sortiertes JSON |
| Risk-check | `claude -p` | Netzwerk, nur Lesezugriff |
| Run | `CommandExecutor` | **führt den Befehl aus** (nur vom Nutzer ausgelöst) |
| Review | konfiguriertes Terminal + interaktives `claude` | öffnet ein Terminal |

### Entscheidungsablauf

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

### Konfiguration

Die Konfiguration liegt unter `~/.config/mac-optimizing-looper/config.json` (kopiere `config.example.json`): Provider, Modell, Thinking-Stufe, Monitor-Sekunden, Intervall, Terminal, Sprache. Sie wird einmal beim Start gelesen – nach manuellem Bearbeiten neu starten.

### Grenzen / was es verweigert

- **Handelt nie von allein.** Nur „Run Command Now" führt etwas aus, und das nur auf deinen Klick.
- **Unbekanntes Risiko = als gefährlich behandelt.** Fail-safe; du bestätigst.
- **`sudo` → GUI-Passwortabfrage.** Ein Hintergrundlauf hat kein TTY, daher laufen Root-Befehle über `osascript … with administrator privileges`.
- **Keine `claude`-CLI = kein Rat.** Es zeigt den Fehler an, statt zu raten.
- Benachrichtigungen brauchen das App-Bundle; eine nackte Binärdatei weicht darauf aus, das Ergebnisfenster zu öffnen.

</details>

---

MIT-lizenziert. Gebaut für Leute, die lieber *wissen*, warum ihr Mac lahmt, als neu zu starten und zu hoffen.
