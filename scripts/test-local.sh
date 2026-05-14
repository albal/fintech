#!/usr/bin/env bash
# Run the same checks that CI runs, locally.
# Exit code mirrors CI: non-zero if any step fails.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT}"

BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
RESET='\033[0m'

pass() { echo -e "${GREEN}✓ $*${RESET}"; }
fail() { echo -e "${RED}✗ $*${RESET}"; }
section() { echo -e "\n${BOLD}${CYAN}── $* ──${RESET}"; }

FAILED=0
run() {
  if "$@"; then
    pass "$*"
  else
    fail "$*"
    FAILED=1
  fi
}

# ---------------------------------------------------------------------------
# fmt + validate + test
# ---------------------------------------------------------------------------
section "fmt"
run terraform fmt -check -recursive

section "init"
terraform init -backend=false -input=false -no-color > /dev/null

section "validate"
run terraform validate -no-color

section "test"
run terraform test -no-color

# ---------------------------------------------------------------------------
# tflint
# ---------------------------------------------------------------------------
section "tflint — init"
tflint --init > /dev/null

section "tflint — root"
run tflint --format=default --no-color

section "tflint — modules"
for dir in modules/*/; do
  echo "   ${dir}"
  run tflint --format=default --no-color --chdir="${dir}"
done

# ---------------------------------------------------------------------------
# checkov  (skip list lives in .checkov.yaml — single source of truth)
# ---------------------------------------------------------------------------
section "checkov"
run checkov \
  --directory . \
  --config-file .checkov.yaml \
  --compact \
  --quiet

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
if [[ ${FAILED} -eq 0 ]]; then
  echo -e "${BOLD}${GREEN}All checks passed.${RESET}"
else
  echo -e "${BOLD}${RED}One or more checks failed.${RESET}"
  exit 1
fi
