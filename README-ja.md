# 🔥 Mac が重い。犯人は Claude が突き止める。

[English](README.md) · [한국어](README-ko.md) · [简体中文](README-zh-Hans.md) · [繁體中文](README-zh-Hant.md) · **日本語** · [Español](README-es.md) · [Deutsch](README-de.md) · [Français](README-fr.md) · [Português](README-pt-BR.md) · [Русский](README-ru.md)

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-F05138?logo=swift&logoColor=white)
![Menu bar app](https://img.shields.io/badge/menu--bar-no%20Dock%20icon-success)

**Mac が固まる → Claude が食ってるプロセスを名指しする → ワンクリックで仕留める。勝手には絶対に動かない。**

1 時間ごとに、Mac の負荷が Claude に渡ります。*本当に* CPU/RAM を食っているものを順位付けし、効く修正をそのまま書き出して、メニューバーに並べます — 重い順、色分け、ワンクリック。しかも何かを走らせる前に、*もう一度* Claude のパスがそのコマンドを **SAFE** と認めなければなりません。

**Mac Optimizing Looper** は、ローカルの LLM CLI の上で **観測 → モデルに問い合わせ → 助言 → (任意で) 実行** のループを回し続ける macOS メニューバーアプリ (Dock アイコンなし) です。

[**⬇ インストール**](#インストール) · [**動きを見る ↓**](#仕組み)

<p align="center"><img src="docs/menu.png" alt="Mac Optimizing Looper のメニュー — 順位付けされ、深刻度ごとに色分けされた修正" width="540"></p>

> アクティビティモニタは 200 行を見せて、答えはゼロ。これが見せるのは、それを直す **1 つのコマンド** と、その理由です。

## 仕組み

1 サイクルを上から下まで:

```
⏱  timer fires (default: every 1h, slider 10m … 36h)
→  collect: CPU/MEM + mac-optimizer snapshot (+ optional sustained sample)
→  claude -p   (analysis pass, --effort max)
→  claude -p   (format pass → ranked JSON suggestions)
```

メニューバーには件数が出ます。ドロップダウンは **重い順**: 🔴 critical → 🟡 warning → 🟢 hygiene。各行を展開すると **Copy** · **Show in Terminal** · **Review with Claude** · **Run Command Now** が並びます。

## 安全ゲート — なぜ Mac を吹き飛ばさないのか

何かを実際に走らせる経路は「Run Command Now」**だけ**で、それは端から端までゲートで囲われています:

```
click ▸ Run Command Now   ($ kill 8123)
→  claude -p   classifies → RISK: SAFE
→  background run   (sudo → GUI password prompt, because there's no TTY)
→  ✅ notification → click → full stdout/stderr window
→  suggestion marked ✓ done
```

`SAFE` と分類されないものは — `unknown` も含めて — デフォルトボタンが **Cancel** の確認ダイアログを出します。助言そのものは不活性なデータで、モデルがアプリに何かを走らせることは決してできません。この取り決めは `GuardrailTests` でガチガチに固定されています。

## Mac Optimizing Looper と、よくある面々

| | アクティビティモニタ | 「クリーナー」系アプリ | **Mac Optimizing Looper** |
|---|---|---|---|
| 本当の犯人を見つける | あなたが 200 行を読む | 当て推量 | 🟢 Claude が重い順に並べる |
| *なぜ* 遅いか教える | ✗ | ✗ | 🟢 平易な言葉で理由を |
| 効く修正そのものを出す | ✗ | ざっくり「お掃除」 | 🟢 本物の `kill` / `unload` コマンド |
| 勝手に動く | — | 🔴 動く、スケジュールで | 🟢 決して動かない — あなたのクリックでだけ |
| 実行前に安全ゲート | — | ✗ | 🟢 2 回目の Claude が `SAFE` と認める |
| データの行き先 | ローカル | まちまち | あなた自身の Claude CLI だけ |

## インストール

`claude` CLI が PATH に通っている必要があります。macOS 13 以降。

```bash
brew install --cask kargnas/tap/mac-optimizing-looper
```

> cask と DMG は、最初の署名済みリリース後に公開されます。パイプラインは組み上がっていて、署名用シークレット待ちの状態です — [docs/release-setup.md](docs/release-setup.md) を参照。それまでは、ソースからビルドしてください:

```bash
git clone https://github.com/kargnas/mac-optimizing-looper
cd mac-optimizing-looper
bash script/build_and_run.sh run     # builds the .app, codesigns ad-hoc, launches
```

裸のバイナリではなく **バンドル** を実行してください — `UNUserNotificationCenter` には本物のバンドル id (`as.kargn.MacOptimizingLooper`) が要ります。

## 自分仕様にする

Settings で **Provider / Model / Speed / Fast Mode** を選べます — モデルと推論レベルは各 CLI から **リアルタイム** に読み込まれます。デフォルトのバックエンドは `claude` CLI で、`codex` もサポート (スキーマで制約された 1 パス、別のフォーマット工程なし)。UI は **10 言語** に完全ローカライズされ、**Language** ピッカーは UI *と* 分析出力の言語の両方を切り替えます。

<p align="center"><img src="docs/settings.png" alt="Mac Optimizing Looper の設定 — プロバイダー、モデル、言語、間隔" width="520"></p>

## FAQ

**自分から何かを走らせることはある?**
ありません。助言は不活性なデータです。実行経路はただ 1 つ、「Run Command Now」ボタンを押したときだけ — `GuardrailTests` で強制しています。

**「Run」を押して大丈夫?**
どのコマンドも 2 回目の Claude のパスを通ります。はっきり `SAFE` でないもの (`unknown` を含む) は、**Cancel** が初期選択の確認ダイアログを出します。`sudo` は macOS の GUI パスワードプロンプト経由です。

**自分のデータは Mac の外に出る?**
出るのはライブの計測値とプロセス一覧だけ、しかも *あなた自身の* `claude` CLI 経由で Anthropic へ (または `codex` 経由で OpenAI へ) — その CLI を自分で叩くのとまったく同じです。アプリが足すテレメトリはゼロ。

**いくらかかる?**
今使っている `claude` / `codex` CLI の利用料を超える出費はなし。アプリは無料で MIT ライセンスです。

**`claude` CLI を入れていない?**
なら助言はなし — 当て推量せず、エラーをそのまま見せます。

<details>
<summary><b>内部の仕組み</b> — システムプロンプト、全サイクル、判断フロー、設定、制限</summary>

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

### 各サイクルが触れる範囲

| ステップ | ツール | 副作用 |
|---|---|---|
| Collect | `MetricsCollector`、`mac-optimizer.sh` | 読み取り専用 |
| Analyze | `claude -p` (effort = max) | ネットワーク、読み取り専用 |
| Format | `claude -p` (effort = low) | 順位付けされた JSON |
| Risk-check | `claude -p` | ネットワーク、読み取り専用 |
| Run | `CommandExecutor` | **コマンドを実行する** (ユーザー操作起点のみ) |
| Review | 設定済みのターミナル + 対話型 `claude` | ターミナルを開く |

### 判断フロー

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

### 設定

設定は `~/.config/mac-optimizing-looper/config.json` にあります (`config.example.json` をコピー): プロバイダー、モデル、思考レベル、モニター秒数、間隔、ターミナル、言語。起動時に一度だけ読み込まれるので、手で書き換えたら再起動してください。

### 制限事項 / 拒否する動作

- **自分から動くことはありません。** 実行されるのは「Run Command Now」だけ、しかもあなたのクリックがあったときだけ。
- **不明なリスク = 危険として扱う。** フェイルセーフ。あなたが確認します。
- **`sudo` → GUI パスワードプロンプト。** バックグラウンド実行には TTY がないので、root 権限のコマンドは `osascript … with administrator privileges` を経由します。
- **`claude` CLI がない = 助言なし。** 当て推量せず、エラーを見せます。
- 通知にはアプリのバンドルが要ります。裸のバイナリは結果ウィンドウを開く動作にフォールバックします。

</details>

---

MIT ライセンス。再起動して祈るより、Mac が *なぜ* 遅いのかを知りたい人のために作りました。
