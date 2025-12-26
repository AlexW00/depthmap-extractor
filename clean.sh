#!/bin/bash

# Script to clean/reset the Xcode project configuration.
# This removes configured values (e.g. signing team + bundle id) so they don't get committed.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PROJECT_FILE="Depth Map Extractor.xcodeproj/project.pbxproj"

echo -e "${YELLOW}Cleaning Depth Map Extractor project configuration...${NC}"

if [ ! -f "$PROJECT_FILE" ]; then
  echo -e "${RED}Error: $PROJECT_FILE not found${NC}"
  exit 1
fi

echo "Resetting signing + bundle identifier placeholders..."
sed -i '' 's/DEVELOPMENT_TEAM = [^;]*;/DEVELOPMENT_TEAM = \"\";/g' "$PROJECT_FILE"
sed -i '' 's/PRODUCT_BUNDLE_IDENTIFIER = [^;]*;/PRODUCT_BUNDLE_IDENTIFIER = \"\";/g' "$PROJECT_FILE"

echo -e "${GREEN}✓ Reset DEVELOPMENT_TEAM and PRODUCT_BUNDLE_IDENTIFIER to empty values${NC}"
echo -e "${GREEN}✓ Project cleaned${NC}"
echo "Note: Run './configure.sh' before building (unless you disable code signing)."

