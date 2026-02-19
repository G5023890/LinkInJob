#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FOLDER_ID="1edFf52mpJVSJcOYuP8ACLKX_T64g21Tn"
DEST_DIR="${DEST_DIR:-$HOME/Library/Application Support/DriveCVSync/LinkedIn Archive}"
REMOTE_NAME="${RCLONE_REMOTE:-gdrive_cv}"
UPDATE_SCRIPT="${UPDATE_SCRIPT:-$PROJECT_ROOT/scripts/update_linkedin_applications.py}"

RCLONE_BIN="${RCLONE_BIN:-}"
if [[ -z "$RCLONE_BIN" ]]; then
  if command -v rclone >/dev/null 2>&1; then
    RCLONE_BIN="$(command -v rclone)"
  elif [[ -x /opt/homebrew/bin/rclone ]]; then
    RCLONE_BIN="/opt/homebrew/bin/rclone"
  elif [[ -x /usr/local/bin/rclone ]]; then
    RCLONE_BIN="/usr/local/bin/rclone"
  elif [[ -x /usr/bin/rclone ]]; then
    RCLONE_BIN="/usr/bin/rclone"
  fi
fi

if [[ -z "$RCLONE_BIN" || ! -x "$RCLONE_BIN" ]]; then
  echo "ERROR: rclone is not installed or not found in PATH." >&2
  echo "Checked PATH and common locations: /opt/homebrew/bin, /usr/local/bin, /usr/bin" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"

if ! "$RCLONE_BIN" listremotes | grep -qx "${REMOTE_NAME}:"; then
  echo "ERROR: remote '${REMOTE_NAME}' is not configured." >&2
  echo "Run once: $PROJECT_ROOT/scripts/setup_rclone_drive.sh" >&2
  exit 2
fi

# Sync files from Google Drive folder to local target.
"$RCLONE_BIN" copy "${REMOTE_NAME}:" "$DEST_DIR" \
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
