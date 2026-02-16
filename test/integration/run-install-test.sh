#!/usr/bin/env bash

# Integration test script
# Validates installation in Docker containers
#
# Usage:
#   ./run-install-test.sh                    # Run all platforms
#   ./run-install-test.sh ubuntu-22          # Run single platform
#   ./run-install-test.sh ubuntu-22 debian   # Run specific platforms

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG_DIR="${PROJECT_ROOT}/tmp"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Available platforms
ALL_PLATFORMS=("ubuntu-22" "ubuntu-24" "arch" "debian")

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# Track current docker compose process
DOCKER_COMPOSE_PID=""

# Cleanup function
cleanup() {
  echo ""
  echo -e "${YELLOW}Received interrupt signal, cleaning up...${NC}"
  
  # Kill docker compose if running
  if [[ -n "${DOCKER_COMPOSE_PID}" ]]; then
    kill "${DOCKER_COMPOSE_PID}" 2>/dev/null || true
    wait "${DOCKER_COMPOSE_PID}" 2>/dev/null || true
  fi
  
  # Stop all containers
  cd "${SCRIPT_DIR}"
  docker compose down 2>/dev/null || true
  
  echo -e "${YELLOW}Cleanup complete${NC}"
  exit 130
}

# Trap signals
trap cleanup SIGINT SIGTERM

# Determine which platforms to test
PLATFORMS=()
if [[ $# -eq 0 ]]; then
  # No arguments - run all platforms
  PLATFORMS=("${ALL_PLATFORMS[@]}")
else
  # Validate provided platforms
  for platform in "$@"; do
    # Check if platform is valid
    valid=false
    for valid_platform in "${ALL_PLATFORMS[@]}"; do
      if [[ "${platform}" == "${valid_platform}" ]]; then
        valid=true
        break
      fi
    done
    
    if [[ "${valid}" == "true" ]]; then
      PLATFORMS+=("${platform}")
    else
      echo -e "${RED}Error: Unknown platform '${platform}'${NC}"
      echo "Available platforms: ${ALL_PLATFORMS[*]}"
      exit 1
    fi
  done
fi

echo -e "${BLUE}Starting integration tests for: ${PLATFORMS[*]}${NC}"
echo ""

# Change to test directory
cd "${SCRIPT_DIR}"

# Clean up any running containers but keep images and volumes
docker compose down 2>/dev/null || true

# Test results
FAILED=()
PASSED=()

for platform in "${PLATFORMS[@]}"; do
  echo -e "${BLUE}Testing ${platform}...${NC}"
  
  # Run docker compose in background to track PID
  docker compose run --rm "${platform}" 2>&1 | tee "${LOG_DIR}/test-${platform}.log" &
  DOCKER_COMPOSE_PID=$!
  
  # Wait for completion and check exit status
  if wait "${DOCKER_COMPOSE_PID}"; then
    echo -e "${GREEN}✓ ${platform} passed${NC}"
    PASSED+=("${platform}")
  else
    EXIT_CODE=$?
    # Exit code 130 means SIGINT, 143 means SIGTERM
    if [[ ${EXIT_CODE} -eq 130 ]] || [[ ${EXIT_CODE} -eq 143 ]]; then
      echo -e "${YELLOW}Test interrupted${NC}"
      cleanup
    fi
    echo -e "${RED}✗ ${platform} failed${NC}"
    FAILED+=("${platform}")
  fi
  
  DOCKER_COMPOSE_PID=""
  echo ""
done

# Clean up containers only (keep images and volumes for next run)
docker compose down

# Summary
TOTAL_TESTED=${#PLATFORMS[@]}
TOTAL_PASSED=${#PASSED[@]}
TOTAL_FAILED=${#FAILED[@]}

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Integration Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

if [ ${TOTAL_PASSED} -gt 0 ]; then
  echo -e "${GREEN}Passed (${TOTAL_PASSED}/${TOTAL_TESTED}):${NC}"
  for platform in "${PASSED[@]}"; do
    echo -e "  ${GREEN}✓${NC} ${platform}"
  done
  echo ""
fi

if [ ${TOTAL_FAILED} -gt 0 ]; then
  echo -e "${RED}Failed (${TOTAL_FAILED}/${TOTAL_TESTED}):${NC}"
  for platform in "${FAILED[@]}"; do
    echo -e "  ${RED}✗${NC} ${platform}"
    echo -e "     Log: ${LOG_DIR}/test-${platform}.log"
  done
  echo ""
  exit 1
else
  echo -e "${GREEN}All tests passed!${NC}"
  exit 0
fi
