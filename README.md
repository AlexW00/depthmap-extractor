# Depth Map Extractor

A tiny macOS drag-and-drop app that extracts a 16-bit depth map from a photo.

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
