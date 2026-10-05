#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "Checking for potential model conflicts..."

# Directory containing the project
PROJECT_DIR="$(dirname "$0")/.."

# Check for struct/class definitions outside Models directory
echo -e "\n${YELLOW}Checking for model definitions outside Models directory...${NC}"
find "$PROJECT_DIR" -name "*.swift" ! -path "*/Models/*" -type f -exec grep -l "^[[:space:]]*\(struct\|class\).*:.*\(Codable\|Identifiable\)" {} \;

# Check for nested type definitions
echo -e "\n${YELLOW}Checking for nested type definitions...${NC}"
find "$PROJECT_DIR" -name "*.swift" -type f -exec grep -l "^[[:space:]]*\(struct\|class\).*{.*\n.*\(struct\|class\)" {} \;

# Check for duplicate model names
echo -e "\n${YELLOW}Checking for duplicate model names...${NC}"
find "$PROJECT_DIR" -name "*.swift" -type f -exec grep -h "^[[:space:]]*\(struct\|class\).*{" {} \; | sort | uniq -d

echo -e "\n${GREEN}Model conflict check completed.${NC}"
