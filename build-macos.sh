#!/bin/bash

set -euo pipefail

# By default we configure signing from .env (like Zettel). Set SKIP_CONFIGURE=1 to skip.
SKIP_CONFIGURE=${SKIP_CONFIGURE:-0}

if [[ "$SKIP_CONFIGURE" != "1" && -f "./configure.sh" ]]; then
  ./configure.sh
fi

CONFIGURATION=${CONFIGURATION:-Debug}
SCHEME=${SCHEME:-"Depth Map Extractor"}
DERIVED_DATA_PATH=${DERIVED_DATA_PATH:-build/DerivedData}

echo "Building Depth Map Extractor for macOS..."
xcodebuild -project "Depth Map Extractor.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -destination "platform=macOS,arch=arm64" \
  build

echo "Build complete!"
echo "Launching app..."
open "$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/Depth Map Extractor.app"

