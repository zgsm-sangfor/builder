#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

${SCRIPT_DIR}/install-costrict-admin.sh
${SCRIPT_DIR}/install-mirror.sh
