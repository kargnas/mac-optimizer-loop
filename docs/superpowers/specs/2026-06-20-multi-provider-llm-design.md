# Multi-provider LLM backend (Claude + Codex, extensible)

Status: approved 2026-06-20. Lets the app drive its LLM analysis through either the
`claude` or the `codex` CLI, with model/effort/fast-mode discovered dynamically from
each CLI, and a provider abstraction built so a third provider is a small addition.

## Goals

- Add `codex` as an alternative backend to `claude -p` for every in-app LLM call.
- Discover models and reasoning levels ("speed") dynamically from each CLI, not hardcoded.
- Settings expose **Provider / Model / Effort / Fast Mode** with cascading dependence.
- Keep `claude` the default; existing configs keep working untouched.
- Generalize the abstraction so future providers (e.g. gemini CLI) drop in cleanly.

## Provider capabilities (documented contract)

Each provider declares capabilities; new providers set these explicitly:

| Capability | Claude | Codex |
|---|---|---|
| `supportsStructuredOutput` | **false** — produces free-form text, formatted to JSON by a 2nd pass (`format-json.sh`) | **true** — `codex exec --output-schema` returns the final JSON directly, 2nd pass skipped |
| `supportsFastMode` (per model) | **false** — the `claude` CLI exposes no service-tier/fast flag | per `models_cache.json` (`service_tiers` priority / `additional_speed_tiers` "fast") |
| system prompt | `--system-prompt` flag | none — system+user are concatenated into the prompt |
| effort flag | `--effort <low|medium|high|xhigh|max>` | `-c model_reasoning_effort=<low|medium|high|xhigh>` |
| model flag | `--model` | `-m` |

**Rule for future providers:** if a provider can emit a schema-constrained final
message natively, set `supportsStructuredOutput=true` and the advice pipeline asks it
for JSON directly. Otherwise it stays on the claude-style two-pass (free-form → formatter).

## Dynamic catalog

`ProviderCatalog = [ProviderModel]`, `ProviderModel { slug, displayName, efforts:[{level,description}], defaultEffort, supportsFastMode }`.

- **Codex**: parse `~/.codex/models_cache.json` → `models[]` (filter `visibility == "list"`),
  mapping `slug`/`display_name`/`supported_reasoning_levels`/`default_reasoning_level`;
  `supportsFastMode` = `service_tiers` contains a priority tier OR `additional_speed_tiers` contains "fast".
- **Claude**: no CLI list command exists, so a curated alias set (`opus`, `sonnet`,
  `haiku`, `fable`) with efforts `low/medium/high/xhigh/max`, default `max`, `supportsFastMode=false`.
- Both: a `Custom…` free-text escape. Discovery failure (missing cache) → empty list + Custom only (non-fatal).

## Invocation — codex

```
codex exec -m <model> -c model_reasoning_effort=<effort> [-c service_tier=priority] \
  --skip-git-repo-check -s read-only [--output-schema <schemaFile> -o <outFile>] <prompt> </dev/null
```

- `</dev/null` is required or codex blocks reading stdin.
- Structured path: write the `LLMAdviceResponse` JSON Schema to a temp file, read the
  `-o` output (already JSON), skip `ShellResponseFormatterProvider`.
- `temperature` and `maxTokens` are not honored by `codex exec` (model-governed); documented, not passed.

## Config

- New `provider: String` (default `"claude"`) and `fastMode: Bool` (default `false`).
- `model` and `thinkingLevel` (effort) become provider-relative; effort clamped to the
  selected model's supported set, else kept as custom.
- Backward compatible: a config without `provider` resolves to claude; existing
  `thinkingLevel` still applies.

## Pipeline (`LLMAdviceProvider`)

- Build the provider client from config via `ProviderRegistry`.
- If the provider `supportsStructuredOutput`: pass the advice JSON Schema in the
  `ChatRequest`, decode the returned JSON, skip the formatter.
- Else (claude): existing two-pass (analysis text → `format-json.sh` → JSON).

## All touchpoints (this phase)

- **Main analysis** and **`CommandRiskAssessor`**: routed through the selected provider
  (codex uses a verdict JSON Schema).
- **Terminal "Review"**: label becomes provider-aware; codex builds a `codex exec` review
  command instead of `claude`.
- **Formatter shell scripts**: stay claude-only. The codex path bypasses them via native
  structured output, so no codex shell scripts are added.

## Settings UI

Provider ▾ → Model ▾ (catalog) → Effort ▾ (model's efforts) → ☑ Fast Mode (enabled only
when the model supports it). Changing provider repopulates models; changing model
repopulates efforts and fast-mode availability. Model's `Custom…` reveals a text field.

## Errors

- Missing CLI → `LLMError.missingProviderCLI(String)` (generalizes `missingClaudeCLI`);
  settings shows which CLI is absent.
- Codex exec failure → `processFailed` with stderr. Catalog discovery failure is non-fatal.

## Tests

Codex catalog parsing (fixture `models_cache.json`), codex client argument construction
(model/effort/fast/schema flags), config round-trip (provider/fastMode + backward compat),
advice provider structured-vs-two-pass branch via mock providers.

## Extensibility

`LLMProviderKind` enum + `ProviderRegistry` (id → client/catalog factory). Adding a
provider = new client + catalog + one enum case + capability flags. Recorded in AGENTS.md.
