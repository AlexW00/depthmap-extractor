#!/bin/bash

# Script to configure the Xcode project with environment variables.
# This script should be run before building the project (unless you skip signing).

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PROJECT_FILE="Depth Map Extractor.xcodeproj/project.pbxproj"
PROJECT_FILE_BACKUP="${PROJECT_FILE}.backup"

echo -e "${YELLOW}Configuring Depth Map Extractor project...${NC}"

if [ ! -f .env ]; then
  echo -e "${RED}Error: .env file not found!${NC}"
  echo "Please copy .env.example to .env and fill in your values:"
  echo "  cp .env.example .env"
  exit 1
fi

set -o allexport
source .env
set +o allexport

if [ -z "${DEVELOPMENT_TEAM:-}" ] || [ "${DEVELOPMENT_TEAM}" = "YOUR_TEAM_ID_HERE" ]; then
  echo -e "${RED}Error: DEVELOPMENT_TEAM not set in .env file${NC}"
  exit 1
fi

if [ -z "${BUNDLE_IDENTIFIER:-}" ] || [ "${BUNDLE_IDENTIFIER}" = "com.yourcompany.depth-map-extractor" ]; then
  echo -e "${RED}Error: BUNDLE_IDENTIFIER not set in .env file${NC}"
  exit 1
fi

if [ ! -f "$PROJECT_FILE_BACKUP" ]; then
  cp "$PROJECT_FILE" "$PROJECT_FILE_BACKUP"
  echo "Created backup: $PROJECT_FILE_BACKUP"
fi

# Replace empty placeholders inserted by clean.sh
sed -i '' "s/DEVELOPMENT_TEAM = \"\";/DEVELOPMENT_TEAM = $DEVELOPMENT_TEAM;/g" "$PROJECT_FILE"
sed -i '' "s/PRODUCT_BUNDLE_IDENTIFIER = \"\";/PRODUCT_BUNDLE_IDENTIFIER = $BUNDLE_IDENTIFIER;/g" "$PROJECT_FILE"

echo -e "${GREEN}✓ Configured project with:${NC}"
echo "  Development Team: $DEVELOPMENT_TEAM"
echo "  Bundle Identifier: $BUNDLE_IDENTIFIER"
echo -e "${GREEN}✓ Project is ready to build!${NC}"

