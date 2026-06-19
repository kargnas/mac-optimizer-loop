# Release setup (one-time)

The CI is scaffolded but **inert** until these secrets exist. Once they do, every
push to `main` (touching `Sources/`, `script/`, or `Package.swift`) auto-cuts a
signed, notarized DMG release and bumps the Homebrew cask — no further manual work.

Pipeline: `auto-release.yml` (version bump) → `build-release.yml` (build → Developer
ID sign → notarize → DMG → GitHub Release → `update-tap` writes the cask).

## Required repo secrets

Add under **Settings → Secrets and variables → Actions** of `kargnas/mac-optimizer-loop`.

| Secret | What it is | How to get it |
|---|---|---|
| `BUILD_CERTIFICATE_BASE64` | Developer ID Application cert as base64 `.p12` | Export the cert+key from Keychain as `.p12`, then `base64 -i cert.p12 \| pbcopy` |
| `P12_PASSWORD` | Password you set on that `.p12` export | — |
| `KEYCHAIN_PASSWORD` | Any throwaway string | Used only to unlock the ephemeral CI keychain |
| `APPLE_ID` | Apple Developer account email | — |
| `APPLE_APP_PASSWORD` | App-specific password for notarization | appleid.apple.com → Sign-In & Security → App-Specific Passwords |
| `APPLE_TEAM_ID` | 10-char Team ID | developer.apple.com → Membership |
| `TAP_SSH_KEY` | Private deploy key with **write** to `kargnas/homebrew-tap` | `ssh-keygen -t ed25519`; add the public key as a write deploy key on the tap repo, paste the private key here |

You need an Apple Developer Program membership (the "Developer ID Application"
certificate type) to sign + notarize.

## First release

After the secrets are in:

```bash
# patch bump happens automatically on the next push to main, OR cut one now:
gh workflow run auto-release.yml -f bump=minor    # → v0.1.0
```

`update-tap` **creates** `Casks/mac-optimizer-loop.rb` in the tap on the first run
(no need to pre-add it), then keeps `version` + `sha256` in sync on every release.

Then `brew install --cask kargnas/tap/mac-optimizer-loop` works.

## Not wired yet (future "full line")

- **Sparkle in-app auto-update.** cctrans embeds Sparkle (a `SUFeedURL` + EdDSA
  public key in `Info.plist`) and publishes an `appcast.xml` per release. That is a
  code change to the app target, not just CI, so it is intentionally left out here.
  Until then, updates come via `brew upgrade --cask mac-optimizer-loop`.
