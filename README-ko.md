# 🔥 느려터진 Mac, 범인은 Claude가 찾는다.

[English](README.md) · **한국어** · [简体中文](README-zh-Hans.md) · [繁體中文](README-zh-Hant.md) · [日本語](README-ja.md) · [Español](README-es.md) · [Deutsch](README-de.md) · [Français](README-fr.md) · [Português](README-pt-BR.md) · [Русский](README-ru.md)

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-F05138?logo=swift&logoColor=white)
![Menu bar app](https://img.shields.io/badge/menu--bar-Dock%20아이콘%20없음-success)

**Mac이 버벅대면 → Claude가 CPU/RAM을 잡아먹는 범인 프로세스를 콕 집어내고 → 클릭 한 번에 끝냄. 단, 앱이 스스로 손대는 일은 절대 없음.**

매시간 Mac의 부하가 Claude에게 전달됨. Claude는 *진짜로* CPU/RAM을 잡아먹는 놈을 심각도순으로 정렬하고, 정확한 해결 명령을 작성해서 메뉴바에 띄움 — 위험한 순서대로, 색깔로 구분해서, 클릭 한 번 거리에. 그리고 뭔가 실행되기 전에, *두 번째* Claude 패스가 그 명령을 반드시 **SAFE**로 판정해야 함.

**Mac Optimizing Looper**는 Dock 아이콘 없는 macOS 메뉴바 앱임. 로컬 LLM CLI 위에서 **관찰 → 모델에게 질의 → 제안 → (선택적) 실행** 루프를 끊임없이 돌림.

[**⬇ 설치하기**](#설치) · [**작동 모습 보기 ↓**](#작동-방식)

<p align="center"><img src="docs/menu-ko.png" alt="Mac Optimizing Looper 메뉴 — 심각도 색상별 정렬 제안" width="540"></p>

> 활성 상태 보기(Activity Monitor)는 200줄을 보여주고 답은 0개임. 이건 **그 한 줄짜리 명령**을 보여줌 — 게다가 이유까지.

## 작동 방식

한 사이클, 위에서 아래로:

```
⏱  타이머 발화 (기본 1시간, 슬라이더 10분 … 36시간)
→  수집: CPU/MEM + mac-optimizer 스냅샷 (+ 선택적 지속 샘플)
→  claude -p   (분석 패스, --effort max)
→  claude -p   (포맷 패스 → 정렬된 JSON 제안)
```

메뉴바에 개수가 뜸. 드롭다운은 **위험한 순서대로** 정렬됨: 🔴 위급 → 🟡 경고 → 🟢 위생. 각 행은 **Copy** · **Show in Terminal** · **Review with Claude** · **Run Command Now**로 펼쳐짐.

## 안전 게이트 — Mac을 날려먹지 않는 이유

"Run Command Now"는 뭔가를 실제로 실행하는 **유일한** 경로이고, 끝까지 게이트가 걸려 있음:

```
클릭 ▸ Run Command Now   ($ kill 8123)
→  claude -p   판정 → RISK: SAFE
→  백그라운드 실행   (sudo → TTY 없으므로 GUI 비밀번호 프롬프트)
→  ✅ 알림 → 클릭 → 전체 stdout/stderr 창
→  제안에 ✓ 완료 표시
```

`SAFE`로 판정되지 않은 모든 것 — **`unknown` 포함** — 은 기본 버튼이 **취소**인 확인 대화상자를 띄움. 제안 자체는 비활성 데이터일 뿐, 모델이 앱더러 뭔가를 실행하게 만들 수는 없음. 이 계약은 `GuardrailTests`로 못 박혀 있음.

## Mac Optimizing Looper vs 흔한 대안들

| | 활성 상태 보기 | "클리너" 앱 | **Mac Optimizing Looper** |
|---|---|---|---|
| 진짜 범인 찾기 | 200줄 직접 읽기 | 추측 | 🟢 Claude가 위험순 정렬 |
| *왜* 느린지 설명 | ✗ | ✗ | 🟢 쉬운 말로 이유 제시 |
| 정확한 해결책 제공 | ✗ | 두루뭉술 "청소" | 🟢 진짜 `kill` / `unload` 명령 |
| 스스로 실행 | — | 🔴 예약대로 실행함 | 🟢 절대 안 함 — 당신 클릭만 |
| 실행 전 안전 검사 | — | ✗ | 🟢 두 번째 Claude 패스가 `SAFE` 판정 |
| 데이터 행선지 | 로컬 | 제각각 | 당신 본인의 Claude CLI로만 |

## 설치

PATH 위에 `claude` CLI 필요. macOS 13+.

```bash
brew install --cask kargnas/tap/mac-optimizing-looper
```

> cask + DMG는 첫 서명 릴리스 후 활성화됨. 파이프라인은 연결돼 있고 서명 secret을 기다리는 중 — [docs/release-setup.md](docs/release-setup.md) 참고. 그 전까지는 소스에서 빌드:

```bash
git clone https://github.com/kargnas/mac-optimizing-looper
cd mac-optimizing-looper
bash script/build_and_run.sh run     # .app 빌드, ad-hoc 코드사인, 실행
```

bare 바이너리가 아니라 **번들**로 실행할 것 — `UNUserNotificationCenter`는 실제 bundle id(`as.kargn.MacOptimizingLooper`)가 필요함.

## 입맛대로 설정

설정에서 **프로바이더 / 모델 / 속도 / Fast Mode**를 고름 — 모델과 추론 강도는 각 CLI에서 **실시간**으로 읽어옴. 기본 백엔드는 `claude` CLI이며 `codex`도 지원함(스키마 기반 단일 패스, 별도 포맷 단계 없음). UI는 **10개 언어**로 완전히 현지화돼 있고, **Language** 피커가 UI 언어와 분석 출력 언어를 함께 정함.

<p align="center"><img src="docs/settings-ko.png" alt="Mac Optimizing Looper 설정 — 프로바이더·모델·언어·주기" width="520"></p>

## 자주 묻는 질문

**앱이 스스로 뭔가 실행하나요?**
아니요. 제안은 비활성 데이터임. 유일한 실행 경로는 "Run Command Now" 버튼이고, 당신의 클릭에서만 작동함 — `GuardrailTests`로 강제됨.

**"Run" 눌러도 안전한가요?**
모든 명령이 두 번째 Claude 패스를 거침. 명확히 `SAFE`가 아니면(`unknown` 포함) 기본값이 **취소**인 확인 창이 뜸. `sudo`는 macOS GUI 비밀번호 프롬프트로 라우팅됨.

**제 데이터가 Mac을 떠나나요?**
실시간 지표 + 프로세스 목록만, 그리고 *당신 본인의* `claude` CLI(또는 `codex`로 OpenAI)를 통해서만 전송됨 — 그 CLI를 직접 쓰는 것과 똑같음. 앱이 추가하는 텔레메트리는 0임.

**비용이 드나요?**
기존 `claude` / `codex` CLI 사용분 외엔 없음. 앱은 무료이고 MIT 라이선스임.

**`claude` CLI가 없으면요?**
제안 없음 — 추측하지 않고 오류를 드러냄.

<details>
<summary><b>내부 동작</b> — 시스템 프롬프트, 전체 사이클, 의사결정 흐름, 설정, 한계</summary>

### 시스템 프롬프트 (요약 발췌)

```
You are a macOS performance analyst.
Given live metrics + a process table, identify the ACTUAL remediation
command (kill / killall / unload) for each real problem — never an
inspection command (no pgrep / ps / top).

MUST:     rank by severity; prefer graceful `kill <pid>` over `kill -9`.
MUST:     return a null command when no command-line action applies.
MUST NOT: claim anything was executed — the app never auto-runs.
```

### 사이클이 건드릴 수 있는 것

| 단계 | 도구 | 부작용 |
|---|---|---|
| 수집 | `MetricsCollector`, `mac-optimizer.sh` | 읽기 전용 |
| 분석 | `claude -p` (effort = max) | 네트워크, 읽기 전용 |
| 포맷 | `claude -p` (effort = low) | 정렬된 JSON |
| 위험 검사 | `claude -p` | 네트워크, 읽기 전용 |
| 실행 | `CommandExecutor` | **명령 실행** (사용자 시작 시에만) |
| 검토 | 설정한 터미널 + 인터랙티브 `claude` | 터미널 염 |

### 의사결정 흐름

```
타이머 → 수집 → claude 분석 → 제안 정렬
                                   │
              사용자가 동작 선택 ──┼─ Copy / Show in Terminal → 실행 없음
                                   ├─ Review with Claude       → 인터랙티브 claude 세션
                                   └─ Run Command Now
                                          → claude 위험 검사
                                               ├─ SAFE → 실행 → 알림 → ✓
                                               └─ 그외 → 확인 (기본 취소)
```

### 설정

설정은 `~/.config/mac-optimizing-looper/config.json`에 있음(`config.example.json` 복사): provider, model, thinking level, monitor seconds, interval, terminal, language. 실행 시 한 번만 읽음 — 직접 수정한 뒤엔 앱을 재시작할 것.

### 한계 / 거부하는 것

- **스스로 행동하지 않음.** "Run Command Now"만 실행하며, 당신의 클릭에서만.
- **unknown 위험 = 위험으로 취급.** Fail-safe, 당신이 확인함.
- **`sudo` → GUI 비밀번호 프롬프트.** 백그라운드 실행은 TTY가 없으므로 root 명령은 `osascript … with administrator privileges`로 라우팅됨.
- **`claude` CLI 없음 = 제안 없음.** 추측하지 않고 오류를 드러냄.
- 알림은 앱 번들이 필요함. bare 바이너리는 결과 창을 직접 여는 것으로 폴백함.

</details>

---

MIT 라이선스. 재부팅하고 기도하느니 Mac이 *왜* 느린지 알고 싶은 사람들을 위해 만듦.
