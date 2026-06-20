# Release setup (one-time)

The CI is scaffolded but **inert** until these secrets exist. Once they do, every
push to `main` (touching `Sources/`, `script/`, or `Package.swift`) auto-cuts a
signed, notarized DMG release and bumps the Homebrew cask — no further manual work.

Pipeline: `auto-release.yml` (version bump) → `build-release.yml` (build → Developer
ID sign → notarize → DMG → GitHub Release → `update-tap` writes the cask).

## Required repo secrets

Add under **Settings → Secrets and variables → Actions** of `kargnas/mac-optimizing-looper`.

| Secret | What it is | How to get it |
|---|---|---|
| `BUILD_CERTIFICATE_BASE64` | Developer ID Application cert as base64 `.p12` | Export the cert+key from Keychain as `.p12`, then `base64 -i cert.p12 \| pbcopy` |
| `P12_PASSWORD` | Password you set on that `.p12` export | — |
| `KEYCHAIN_PASSWORD` | Any throwaway string | Used only to unlock the ephemeral CI keychain |
| `APPLE_ID` | Apple Developer account email | — |
| `APPLE_APP_PASSWORD` | App-specific password for notarization | appleid.apple.com → Sign-In & Security → App-Specific Passwords |
| `APPLE_TEAM_ID` | 10-char Team ID | developer.apple.com → Membership |
| `TAP_SSH_KEY` | Private deploy key with **write** to `kargnas/homebrew-tap` | `ssh-keygen -t ed25519`; add the public key as a write deploy key on the tap repo, paste the private key here |
| `SPARKLE_PRIVATE_KEY` | EdDSA private key that signs the Sparkle appcast | **Already set.** Generated via `generate_keys --account MacOptimizingLooper`; the matching public key is baked into `Info.plist` (`SUPublicEDKey`) by `script/build-app.zsh` |

You need an Apple Developer Program membership (the "Developer ID Application"
certificate type) to sign + notarize.

## First release

After the secrets are in:

```bash
# patch bump happens automatically on the next push to main, OR cut one now:
gh workflow run auto-release.yml -f bump=minor    # → v0.1.0
```

`update-tap` **creates** `Casks/mac-optimizing-looper.rb` in the tap on the first run
(no need to pre-add it), then keeps `version` + `sha256` in sync on every release.

Then `brew install --cask kargnas/tap/mac-optimizing-looper` works.

## Sparkle in-app auto-update (wired)

The app embeds Sparkle and self-updates; `brew upgrade` is no longer the only path.

- **App side**: `Package.swift` depends on Sparkle; `AppDelegate` starts
  `SPUStandardUpdaterController` (only from a real `.app` bundle) and adds a
  "Check for Updates…" menu item. `script/build-app.zsh` embeds `Sparkle.framework`,
  writes `SUFeedURL` + `SUPublicEDKey` into `Info.plist`, and signs the framework's
  nested helpers inside-out.
- **CI side**: `build-release.yml` builds with `SPARKLE_AUTO=1` (enables background
  checks), EdDSA-signs the notarized DMG with `SPARKLE_PRIVATE_KEY`, generates
  `appcast.xml`, and uploads it alongside the DMG.
- **Feed**: `SUFeedURL` points at
  `https://github.com/kargnas/mac-optimizing-looper/releases/latest/download/appcast.xml`
  — the `latest` alias always resolves to the newest release's appcast.

The EdDSA key pair is one-time and **must not be regenerated** — losing the private
key (kept in the login keychain under account `MacOptimizingLooper` and mirrored to
the `SPARKLE_PRIVATE_KEY` secret) would strand every installed copy, since they only
trust updates signed by the original key.

`SUEnableAutomaticChecks`/`SUAutomaticallyUpdate` are gated to release builds only
(`SPARKLE_AUTO=1`); local ad-hoc bundles never auto-replace themselves on quit.
