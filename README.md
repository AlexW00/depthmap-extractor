# Depth Map Extractor

<img width="2880" height="1800" alt="extractor-appstore" src="https://github.com/user-attachments/assets/1787f183-6e0f-4a61-a68a-cdf23fc7a686" />

A tiny macOS drag-and-drop app that extracts a 16-bit depth map from a photo.

Available for free on the [App Store](https://apps.apple.com/de/app/depth-map-extractor/id6757020112).

## macOS build (CLI)

1. Create local config:
   - `cp .env.example .env`
   - Edit `.env` with your `DEVELOPMENT_TEAM` and `BUNDLE_IDENTIFIER`
2. Build + launch:
   - `./build-macos.sh`

## Git hooks

Install the repo hooks:

- `./scripts/install-githooks.sh`

The `pre-commit` hook runs `./clean.sh` and stages any changes (e.g. clears signing/team values from the Xcode project file).
