#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [ ! -d ".git" ]; then
  echo "Error: must be run from within a git repo" >&2
  exit 1
fi

chmod +x .githooks/pre-commit
git config core.hooksPath .githooks

echo "Installed git hooks via core.hooksPath=.githooks"

