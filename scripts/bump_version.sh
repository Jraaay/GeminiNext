#!/bin/bash
# ============================================================
# bump_version.sh - Gemini Next Desktop Version Auto-Management Script
#
# Usage:
#   ./scripts/bump_version.sh <version|patch|minor|major>
#
# Examples:
#   ./scripts/bump_version.sh patch   # 0.1.1 → 0.1.2
#   ./scripts/bump_version.sh minor   # 0.1.1 → 0.2.0
#   ./scripts/bump_version.sh major   # 0.1.1 → 1.0.0
#   ./scripts/bump_version.sh 1.2.3   # Specify version directly
# ============================================================

set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No color

# Locate project root (parent of the script directory)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PBXPROJ="$PROJECT_ROOT/GeminiNext.xcodeproj/project.pbxproj"

# Check arguments
if [ $# -ne 1 ]; then
    echo -e "${RED}Error: Please provide a version argument${NC}"
    echo ""
    echo "Usage: $0 <version|patch|minor|major>"
    echo ""
    echo "Examples:"
    echo "  $0 patch    # Increment patch version (0.1.1 → 0.1.2)"
    echo "  $0 minor    # Increment minor version (0.1.1 → 0.2.0)"
    echo "  $0 major    # Increment major version (0.1.1 → 1.0.0)"
    echo "  $0 1.2.3    # Specify version directly"
    exit 1
fi

# Check if pbxproj file exists
if [ ! -f "$PBXPROJ" ]; then
    echo -e "${RED}Error: Cannot find project.pbxproj${NC}"
    echo "Please make sure to run this script from the project root directory"
    exit 1
fi

# Read current version
CURRENT_VERSION=$(grep -m1 'MARKETING_VERSION' "$PBXPROJ" | sed 's/.*= *\(.*\);/\1/' | tr -d ' ')

if [ -z "$CURRENT_VERSION" ]; then
    echo -e "${RED}Error: Unable to read current version from project.pbxproj${NC}"
    exit 1
fi

echo -e "${YELLOW}Current version: ${CURRENT_VERSION}${NC}"

# Parse current version
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

# Calculate new version
INPUT="$1"
case "$INPUT" in
    patch)
        NEW_VERSION="$MAJOR.$MINOR.$((PATCH + 1))"
        ;;
    minor)
        NEW_VERSION="$MAJOR.$((MINOR + 1)).0"
        ;;
    major)
        NEW_VERSION="$((MAJOR + 1)).0.0"
        ;;
    *)
        # Validate input is a valid semantic version
        if [[ ! "$INPUT" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo -e "${RED}Error: Invalid version format '${INPUT}'${NC}"
            echo "Version must be in X.Y.Z format (e.g. 1.2.3)"
            exit 1
        fi
        NEW_VERSION="$INPUT"
        ;;
esac

# Check if new version is the same as current version
if [ "$NEW_VERSION" = "$CURRENT_VERSION" ]; then
    echo -e "${RED}Error: New version is the same as current version (${CURRENT_VERSION})${NC}"
    exit 1
fi

# Check if tag already exists
if git -C "$PROJECT_ROOT" rev-parse "v$NEW_VERSION" >/dev/null 2>&1; then
    echo -e "${RED}Error: Tag v${NEW_VERSION} already exists${NC}"
    exit 1
fi

echo -e "${GREEN}New version: ${NEW_VERSION}${NC}"
echo ""

# Update MARKETING_VERSION in project.pbxproj
sed -i '' "s/MARKETING_VERSION = ${CURRENT_VERSION};/MARKETING_VERSION = ${NEW_VERSION};/g" "$PBXPROJ"

# Increment CURRENT_PROJECT_VERSION (build number for Sparkle version comparison)
CURRENT_BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION' "$PBXPROJ" | sed 's/.*= *\(.*\);/\1/' | tr -d ' ')
NEW_BUILD=$((CURRENT_BUILD + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION = ${CURRENT_BUILD};/CURRENT_PROJECT_VERSION = ${NEW_BUILD};/g" "$PBXPROJ"

# Verify update was successful
UPDATED_VERSION=$(grep -m1 'MARKETING_VERSION' "$PBXPROJ" | sed 's/.*= *\(.*\);/\1/' | tr -d ' ')
if [ "$UPDATED_VERSION" != "$NEW_VERSION" ]; then
    echo -e "${RED}Error: Version update failed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ project.pbxproj updated${NC}"
echo -e "${GREEN}   MARKETING_VERSION: ${CURRENT_VERSION} → ${NEW_VERSION}${NC}"
echo -e "${GREEN}   CURRENT_PROJECT_VERSION: ${CURRENT_BUILD} → ${NEW_BUILD}${NC}"

# Prompt user to run git commands
echo ""
echo -e "${YELLOW}Run the following commands to complete the release:${NC}"
echo ""
echo "  git add GeminiNext.xcodeproj/project.pbxproj"
echo "  git commit -m \"release: v${NEW_VERSION}\""
echo "  git tag v${NEW_VERSION}"
echo "  git push && git push --tags"
echo ""
