#!/bin/bash

set -e
set -u
set -o pipefail 2>/dev/null || true

GITEA_UID="${GITEA_UID:-1000}"
GITEA_GID="${GITEA_GID:-1000}"
: "${COSTRICT_DATA_DIR:?COSTRICT_DATA_DIR is required}"
: "${COSTRICT_BACKEND_DIR:?COSTRICT_BACKEND_DIR is required}"

GITEA_DATA_DIR="${COSTRICT_DATA_DIR}/backend/gitea/data"
SOURCE_CONFIG="${COSTRICT_BACKEND_DIR}/gitea/conf/app.ini"
TARGET_CONFIG="${GITEA_DATA_DIR}/gitea/conf/app.ini"

if [[ ! -f "$SOURCE_CONFIG" ]]; then
    echo "Gitea config not found: $SOURCE_CONFIG" >&2
    exit 1
fi

sudo mkdir -p "$(dirname "$TARGET_CONFIG")"
(
    cd "$COSTRICT_BACKEND_DIR"
    sudo bash scripts/tpl-resolve.sh -f "$SOURCE_CONFIG" -o "$TARGET_CONFIG"
) >/dev/null
sudo chown -R "${GITEA_UID}:${GITEA_GID}" "$GITEA_DATA_DIR"
sudo chmod 0640 "$TARGET_CONFIG"
