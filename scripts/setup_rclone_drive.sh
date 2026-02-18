#!/usr/bin/env bash
set -euo pipefail

REMOTE_NAME="${RCLONE_REMOTE:-gdrive_cv}"

if ! command -v rclone >/dev/null 2>&1; then
  echo "ERROR: rclone is not installed. Install with: brew install rclone" >&2
  exit 1
fi

if rclone listremotes | grep -qx "${REMOTE_NAME}:"; then
  echo "Remote '${REMOTE_NAME}' already exists. Reconnecting OAuth token..."
  rclone config reconnect "${REMOTE_NAME}:" || true
else
  echo "Creating remote '${REMOTE_NAME}' (Google Drive, read-only)..."
  rclone config create "$REMOTE_NAME" drive scope drive.readonly
  echo "Remote created. Completing OAuth..."
  rclone config reconnect "${REMOTE_NAME}:"
fi

echo "Remote '${REMOTE_NAME}' is ready."
