#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FOLDER_ID="1edFf52mpJVSJcOYuP8ACLKX_T64g21Tn"
DEST_DIR="${DEST_DIR:-$HOME/Library/Application Support/DriveCVSync/LinkedIn email}"
DESKTOP_MIRROR_DIR="${DESKTOP_MIRROR_DIR:-$HOME/Desktop/CV/LinkedIn email}"
REMOTE_NAME="${RCLONE_REMOTE:-gdrive_cv}"
UPDATE_SCRIPT="${UPDATE_SCRIPT:-$PROJECT_ROOT/scripts/update_linkedin_applications.py}"

if ! command -v rclone >/dev/null 2>&1; then
  echo "ERROR: rclone is not installed." >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
mkdir -p "$DESKTOP_MIRROR_DIR"

if ! rclone listremotes | grep -qx "${REMOTE_NAME}:"; then
  echo "ERROR: remote '${REMOTE_NAME}' is not configured." >&2
  echo "Run once: $PROJECT_ROOT/scripts/setup_rclone_drive.sh" >&2
  exit 2
fi

# Sync files from Google Drive folder to local target.
rclone copy "${REMOTE_NAME}:" "$DEST_DIR" \
  --drive-root-folder-id "$FOLDER_ID" \
  --create-empty-src-dirs \
  --transfers 4 \
  --checkers 8 \
  --verbose

# Rebuild LinkedIn status and vacancy files after sync.
if [[ ! -f "$UPDATE_SCRIPT" ]]; then
  echo "ERROR: update script not found: $UPDATE_SCRIPT" >&2
  exit 3
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is not installed." >&2
  exit 4
fi

python3 "$UPDATE_SCRIPT" --source-dir "$DEST_DIR"

# Keep a visible mirror on Desktop for manual review.
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$DEST_DIR"/ "$DESKTOP_MIRROR_DIR"/
else
  echo "WARN: rsync not found; skipping Desktop mirror update." >&2
fi
