#!/bin/bash
# Validate KRaft Controller service and configuration on Kafka broker VMs.
# Run via Ansible: ansible kafka_controller -i hosts.yaml -m script -a './scripts/validate-kraft-controller.sh' --become

set -e

PASS=0
FAIL=0
WARN=0

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_pass() {
  echo -e "${GREEN}✓ PASS${NC}: $1"
  ((PASS++))
}

log_fail() {
  echo -e "${RED}✗ FAIL${NC}: $1"
  ((FAIL++))
}

log_warn() {
  echo -e "${YELLOW}⚠ WARN${NC}: $1"
  ((WARN++))
}

# Find the active KRaft controller service
find_service() {
  for candidate in confluent-kcontroller confluent-kafka-controller confluent-kafka confluent-server; do
    if systemctl is-active --quiet "$candidate" 2>/dev/null; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

# Find the KRaft controller configuration file
find_config() {
  for candidate in \
    /etc/controller/server.properties \
    /etc/kafka/server.properties \
    /etc/kafka/controller.properties \
    /etc/kafka/kraft/server.properties; do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

# Check if value exists in config
config_has() {
  local config_file="$1"
  local key="$2"
  grep -q "^${key}=" "$config_file"
}

# Get value from config
config_get() {
  local config_file="$1"
  local key="$2"
  grep "^${key}=" "$config_file" | cut -d= -f2- | head -1
}

echo "=========================================="
echo "KRaft Controller Validation"
echo "=========================================="
echo ""

# Find the service
SERVICE=$(find_service)
if [[ -z "$SERVICE" ]]; then
  log_fail "No active KRaft controller service found"
  exit 1
else
  log_pass "Found active service: $SERVICE"
fi

# Find the config
CONFIG=$(find_config)
if [[ -z "$CONFIG" ]]; then
  log_fail "No KRaft controller configuration found"
  exit 1
else
  log_pass "Found configuration: $CONFIG"
fi

echo ""
echo "--- Service Status ---"
systemctl status "$SERVICE" --no-pager || log_fail "Service status check failed"

echo ""
echo "--- Configuration Validation ---"

# Check node.id
if config_has "$CONFIG" "node.id"; then
  NODE_ID=$(config_get "$CONFIG" "node.id")
  log_pass "node.id configured: $NODE_ID"
else
  log_fail "node.id not configured in $CONFIG"
fi

# Check process.roles
if config_has "$CONFIG" "process.roles"; then
  ROLES=$(config_get "$CONFIG" "process.roles")
  if [[ "$ROLES" == *"controller"* ]]; then
    log_pass "process.roles includes controller: $ROLES"
  else
    log_fail "process.roles does not include controller: $ROLES"
  fi
else
  log_fail "process.roles not configured in $CONFIG"
fi

# Check controller.quorum.voters
if config_has "$CONFIG" "controller.quorum.voters"; then
  VOTERS=$(config_get "$CONFIG" "controller.quorum.voters")
  log_pass "controller.quorum.voters configured: $VOTERS"
else
  log_fail "controller.quorum.voters not configured in $CONFIG"
fi

# Check listeners
if config_has "$CONFIG" "listeners"; then
  LISTENERS=$(config_get "$CONFIG" "listeners")
  log_pass "listeners configured: $LISTENERS"
else
  log_fail "listeners not configured in $CONFIG"
fi

# Check controller.listener.names
if config_has "$CONFIG" "controller.listener.names"; then
  CTL_LISTENERS=$(config_get "$CONFIG" "controller.listener.names")
  log_pass "controller.listener.names configured: $CTL_LISTENERS"
else
  log_warn "controller.listener.names not configured in $CONFIG"
fi

# Check log.dirs
if config_has "$CONFIG" "log.dirs"; then
  LOG_DIRS=$(config_get "$CONFIG" "log.dirs")
  log_pass "log.dirs configured: $LOG_DIRS"

  # Verify log.dirs exists and is writable
  for dir in $(echo "$LOG_DIRS" | tr ',' '\n'); do
    if [[ -d "$dir" ]]; then
      if [[ -w "$dir" ]]; then
        log_pass "log.dirs is writable: $dir"
      else
        log_fail "log.dirs is not writable: $dir"
      fi
    else
      log_fail "log.dirs directory does not exist: $dir"
    fi
  done
else
  log_fail "log.dirs not configured in $CONFIG"
fi

echo ""
echo "--- Network Connectivity ---"

# Check if controller listener port is listening
if config_has "$CONFIG" "controller.quorum.voters"; then
  VOTERS=$(config_get "$CONFIG" "controller.quorum.voters")
  # Extract first controller's host and port from format: id@host:port
  CONTROLLER_HOST=$(echo "$VOTERS" | grep -oP '(?<=@)[^:]+' | head -1)
  CONTROLLER_PORT=$(echo "$VOTERS" | grep -oP ':\K[0-9]+' | head -1)

  if [[ -n "$CONTROLLER_HOST" && -n "$CONTROLLER_PORT" ]]; then
    if nc -zv "localhost" "$CONTROLLER_PORT" 2>/dev/null; then
      log_pass "Controller quorum port is listening: $CONTROLLER_PORT"
    else
      log_warn "Controller quorum port not responding on localhost: $CONTROLLER_PORT"
    fi
  fi
fi

echo ""
echo "--- KRaft Controller Metadata ---"

# Check if __cluster_metadata topic exists
kafka-topics --bootstrap-server localhost:9092 --list 2>/dev/null | grep -q "__cluster_metadata" && \
  log_pass "__cluster_metadata topic exists" || \
  log_warn "__cluster_metadata topic not yet created"

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo -e "Passed: ${GREEN}$PASS${NC}"
echo -e "Failed: ${RED}$FAIL${NC}"
echo -e "Warnings: ${YELLOW}$WARN${NC}"
echo ""

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi

exit 0
