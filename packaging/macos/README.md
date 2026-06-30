# Building Notch for macOS (Apple Silicon / arm64)

This directory contains everything needed to produce a native **arm64**
`Notch.app` for Apple Silicon Macs.

## What gets built

- `dist/Notch.app` — the application bundle (arm64)
- `dist/Notch-arm64.dmg` — a drag-to-Applications disk image (optional)

The Vosk speech model is downloaded at build time and bundled inside the app at
`Notch.app/Contents/MacOS/model`, so the build is fully self-contained and
runs offline.

## Build locally (on an Apple Silicon Mac)

```bash
# From the repo root
MAKE_DMG=1 bash packaging/macos/build_macos_arm.sh
```

Requirements:

- macOS on Apple Silicon
- Python 3.9+ (`python3`)
- Xcode command line tools (`xcode-select --install`) for `codesign`, `sips`,
  `iconutil`, and `hdiutil`

Useful env overrides:

| Variable         | Default                                   | Purpose                              |
| ---------------- | ----------------------------------------- | ------------------------------------ |
| `MAKE_DMG`       | `0`                                       | Set `1` to also build a `.dmg`       |
| `VOSK_MODEL_URL` | small `en-us` model                       | Swap in a larger/different model     |
| `PYTHON`         | `python3`                                 | Choose a specific interpreter        |

## Build in CI (no Mac required)

A GitHub Actions workflow at `.github/workflows/build-macos-arm.yml` runs on the
`macos-14` (Apple Silicon) runner and uploads `Notch-arm64.zip` and
`Notch-arm64.dmg` as build artifacts.

- Run it manually: **Actions → Build macOS (Apple Silicon) → Run workflow**
- Push a `v*` tag to also attach the artifacts to a GitHub Release.

## Running an unsigned build

This build is **ad-hoc signed** (required for arm64 to launch at all) but **not
notarized**. The first time you open it, Gatekeeper may block it. Either:

- Right-click the app → **Open** → **Open**, or
- Remove the quarantine attribute:

  ```bash
  xattr -dr com.apple.quarantine /path/to/Notch.app
  ```

## Notarization (for public distribution)

To distribute without Gatekeeper warnings you need an Apple Developer account
and a "Developer ID Application" certificate. The high-level steps (not wired
into CI, since they require secrets):

1. Sign with your Developer ID:
   `codesign --force --deep --options runtime --sign "Developer ID Application: …" Notch.app`
2. Submit for notarization:
   `xcrun notarytool submit Notch-arm64.dmg --apple-id … --team-id … --password … --wait`
3. Staple the ticket: `xcrun stapler staple Notch.app` (and the DMG).

Add the certificate and credentials as repository secrets and extend the
workflow if/when you want signed, notarized releases.
