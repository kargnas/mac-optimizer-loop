# 🔥 Mac тормозит? Claude найдёт виновника.

[English](README.md) · [한국어](README-ko.md) · [简体中文](README-zh-Hans.md) · [繁體中文](README-zh-Hant.md) · [日本語](README-ja.md) · [Español](README-es.md) · [Deutsch](README-de.md) · [Français](README-fr.md) · [Português](README-pt-BR.md) · **Русский**

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-F05138?logo=swift&logoColor=white)
![Menu bar app](https://img.shields.io/badge/menu--bar-no%20Dock%20icon-success)

**Mac захлёбывается → Claude называет точный процесс, который его жрёт → один клик его убивает. Сам по себе он не делает ничего.**

Каждый час нагрузка вашего Mac уходит в Claude. Он ранжирует, что *на самом деле* объедает ваш CPU/RAM, пишет точную команду исправления и кладёт её прямо в строку меню — худшее сверху, с цветовой маркировкой, в одном клике. И прежде чем что-либо запустится, *второй* проход Claude обязан одобрить команду как **SAFE**.

**Mac Optimizing Looper** — это приложение для строки меню macOS (без значка в Dock), которое крутит непрерывный цикл **наблюдай → спроси модель → посоветуй → (при желании) действуй** поверх вашего локального LLM CLI.

[**⬇ Установить**](#установка) · [**Смотреть в деле ↓**](#как-это-работает)

<p align="center"><img src="docs/menu.png" alt="Меню Mac Optimizing Looper — ранжированные исправления с цветами по серьёзности" width="540"></p>

> Мониторинг системы покажет вам 200 строк и ноль ответов. Здесь вы видите **одну команду**, которая всё чинит, — и почему.

## Как это работает

Один цикл, сверху вниз:

```
⏱  timer fires (default: every 1h, slider 10m … 36h)
→  collect: CPU/MEM + mac-optimizer snapshot (+ optional sustained sample)
→  claude -p   (analysis pass, --effort max)
→  claude -p   (format pass → ranked JSON suggestions)
```

Строка меню показывает счётчик. Выпадающий список отсортирован **худшим вперёд**: 🔴 critical → 🟡 warning → 🟢 hygiene. Каждая строка разворачивается в **Copy** · **Show in Terminal** · **Review with Claude** · **Run Command Now**.

## Защитный шлюз — почему он не разнесёт ваш Mac

«Run Command Now» — **единственный** путь, который вообще что-то выполняет, и он под контролем от начала до конца:

```
click ▸ Run Command Now   ($ kill 8123)
→  claude -p   classifies → RISK: SAFE
→  background run   (sudo → GUI password prompt, because there's no TTY)
→  ✅ notification → click → full stdout/stderr window
→  suggestion marked ✓ done
```

Всё, что не классифицировано как `SAFE` — **включая `unknown`** — открывает диалог подтверждения, в котором кнопка по умолчанию — **Cancel**. Сам совет — это инертные данные; модель никогда не заставит приложение что-либо запустить. Этот контракт жёстко зафиксирован тестами `GuardrailTests`.

## Mac Optimizing Looper против обычных подозреваемых

| | Мониторинг системы | Приложения-«чистильщики» | **Mac Optimizing Looper** |
|---|---|---|---|
| Находит настоящего виновника | вы читаете 200 строк | гадает | 🟢 Claude ставит худшее вперёд |
| Объясняет, *почему* тормозит | ✗ | ✗ | 🟢 причина простым языком |
| Даёт точное исправление | ✗ | общая «очистка» | 🟢 реальная команда `kill` / `unload` |
| Действует сам по себе | — | 🔴 да, по расписанию | 🟢 никогда — только по вашему клику |
| Проверка безопасности перед запуском | — | ✗ | 🟢 второй проход Claude одобряет `SAFE` |
| Куда уходят ваши данные | локально | как повезёт | только в ваш собственный Claude CLI |

## Установка

Нужен CLI `claude` в вашем PATH. macOS 13+.

```bash
brew install --cask kargnas/tap/mac-optimizing-looper
```

> Cask + DMG станут доступны после первого подписанного релиза. Конвейер настроен и ждёт только секреты для подписи — см. [docs/release-setup.md](docs/release-setup.md). А пока соберите из исходников:

```bash
git clone https://github.com/kargnas/mac-optimizing-looper
cd mac-optimizing-looper
bash script/build_and_run.sh run     # builds the .app, codesigns ad-hoc, launches
```

Запускайте **бандл**, а не голый бинарник — `UNUserNotificationCenter` требует настоящий bundle id (`as.kargn.MacOptimizingLooper`).

## Настройте под себя

Выберите **Provider / Model / Speed / Fast Mode** в настройках — модели и уровни рассуждения читаются **вживую** из каждого CLI. Бэкенд по умолчанию — CLI `claude`; также поддерживается `codex` (один проход с ограничением по схеме, без отдельного шага форматирования). Интерфейс полностью локализован на **10 языков**, а селектор **Language** задаёт язык *и* интерфейса, *и* вывода анализа.

<p align="center"><img src="docs/settings.png" alt="Настройки Mac Optimizing Looper — провайдер, модель, язык, интервал" width="520"></p>

## Частые вопросы

**Запускает ли он что-нибудь сам?**
Нет. Совет — это инертные данные. Единственный путь выполнения — кнопка «Run Command Now», по вашему клику; это гарантируют `GuardrailTests`.

**Безопасно ли жать «Run»?**
Каждая команда проходит второй проход Claude. Всё, что не помечено явно как `SAFE` (включая `unknown`), открывает диалог подтверждения с кнопкой по умолчанию **Cancel**. `sudo` идёт через GUI-запрос пароля macOS.

**Уходят ли мои данные с Mac?**
Только живые метрики и таблица процессов, и только в Anthropic через *ваш собственный* CLI `claude` (или в OpenAI через `codex`) — ровно как если бы вы запускали этот CLI сами. Приложение не добавляет никакой телеметрии.

**Сколько это стоит?**
Ничего сверх вашего уже имеющегося использования CLI `claude` / `codex`. Приложение бесплатное и под лицензией MIT.

**CLI `claude` не установлен?**
Тогда советов не будет — приложение покажет ошибку, а не станет гадать.

<details>
<summary><b>Под капотом</b> — системный промпт, полный цикл, поток решений, конфиг, ограничения</summary>

### Системный промпт (очищенный фрагмент)

```
You are a macOS performance analyst.
Given live metrics + a process table, identify the ACTUAL remediation
command (kill / killall / unload) for each real problem — never an
inspection command (no pgrep / ps / top).

MUST:     rank by severity; prefer graceful `kill <pid>` over `kill -9`.
MUST:     return a null command when no command-line action applies.
MUST NOT: claim anything was executed — the app never auto-runs.
```

### Чего может коснуться каждый цикл

| Шаг | Инструмент | Побочный эффект |
|---|---|---|
| Collect | `MetricsCollector`, `mac-optimizer.sh` | только чтение |
| Analyze | `claude -p` (effort = max) | сеть, только чтение |
| Format | `claude -p` (effort = low) | ранжированный JSON |
| Risk-check | `claude -p` | сеть, только чтение |
| Run | `CommandExecutor` | **выполняет команду** (только по инициативе пользователя) |
| Review | настроенный терминал + интерактивный `claude` | открывает терминал |

### Поток принятия решений

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

### Конфигурация

Конфиг лежит в `~/.config/mac-optimizing-looper/config.json` (скопируйте `config.example.json`): провайдер, модель, уровень мышления, секунды мониторинга, интервал, терминал, язык. Он читается один раз при запуске — перезапустите приложение после ручной правки.

### Ограничения / от чего приложение отказывается

- **Никогда не действует само по себе.** Выполняет что-либо только «Run Command Now», и только по вашему клику.
- **Неизвестный риск = считается опасным.** Принцип отказоустойчивости; решение за вами.
- **`sudo` → GUI-запрос пароля.** У фонового запуска нет TTY, поэтому root-команды проходят через `osascript … with administrator privileges`.
- **Нет CLI `claude` = нет советов.** Приложение показывает ошибку, а не строит догадки.
- Уведомлениям нужен бандл приложения; голый бинарник переходит к открытию окна с результатом.

</details>

---

Лицензия MIT. Сделано для тех, кто предпочтёт узнать, *почему* их Mac тормозит, чем перезагрузиться и надеяться на лучшее.
