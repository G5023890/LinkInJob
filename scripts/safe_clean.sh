#!/usr/bin/env bash
set -euo pipefail

# Safe project cleanup:
# - scans only current project directory
# - excludes .git
# - prints dry-run report first
# - deletes only after explicit confirmation

MODE="dry-run"
if [[ "${1:-}" == "--apply" ]]; then
  MODE="apply"
elif [[ "${1:-}" == "--dry-run" || "${1:-}" == "" ]]; then
  MODE="dry-run"
else
  echo "Usage: $0 [--dry-run|--apply]"
  exit 1
fi

PROJECT_ROOT="$(pwd -P)"
TMP_RAW="$(mktemp)"
TMP_LIST="$(mktemp)"
trap 'rm -f "$TMP_RAW" "$TMP_LIST"' EXIT

human_kb() {
  local kb="${1:-0}"
  awk -v kb="$kb" 'BEGIN {
    split("KB MB GB TB", u, " ");
    i = 1; v = kb + 0;
    while (v >= 1024 && i < 4) { v = v / 1024; i++; }
    printf("%.2f %s", v, u[i]);
  }'
}

append_find_results() {
  # shellcheck disable=SC2068
  find . -path './.git' -prune -o $@ -print0 | while IFS= read -r -d '' path; do
    if [[ "$path" == "./.git" || "$path" == "." || "$path" == "./" ]]; then
      continue
    fi
    printf '%s\n' "$path" >> "$TMP_RAW"
  done
}

# Generic directories
append_find_results -type d \( \
  -name node_modules -o \
  -name dist -o \
  -name build -o \
  -name .cache -o \
  -name tmp -o \
  -name .tmp -o \
  -name .build -o \
  -name __pycache__ -o \
  -name .pytest_cache -o \
  -name .mypy_cache -o \
  -name target -o \
  -name CMakeFiles -o \
  -name .codex -o \
  -name .agent -o \
  -name DerivedData -o \
  -name xcuserdata \
\)

# Generic files
append_find_results -type f \( \
  -name '*.log' -o \
  -name '.DS_Store' -o \
  -name '*.xcuserstate' -o \
  -name '*.pyc' -o \
  -name CMakeCache.txt \
\)

# Go artifacts at project root only (if Go module exists)
if [[ -f "./go.mod" ]]; then
  [[ -d "./bin" ]] && printf '%s\n' "./bin" >> "$TMP_RAW"
  [[ -d "./pkg" ]] && printf '%s\n' "./pkg" >> "$TMP_RAW"
fi

sort -u "$TMP_RAW" | awk 'NF > 0' > "$TMP_LIST"

PROJECT_BEFORE_KB="$(du -sk . | awk '{print $1}')"
TOTAL_DELETE_KB=0
COUNT=0

echo "Project root: $PROJECT_ROOT"
echo "Project size (before): $(human_kb "$PROJECT_BEFORE_KB")"
echo
echo "Candidates for deletion:"
echo "------------------------"

while IFS= read -r path; do
  [[ -e "$path" ]] || continue
  size_kb="$(du -sk "$path" | awk '{print $1}')"
  TOTAL_DELETE_KB=$((TOTAL_DELETE_KB + size_kb))
  COUNT=$((COUNT + 1))
  printf '%9s  %s\n' "$(human_kb "$size_kb")" "$path"
done < "$TMP_LIST"

if [[ "$COUNT" -eq 0 ]]; then
  echo "(nothing found)"
fi

echo
echo "Total candidates: $COUNT"
echo "Total size to delete: $(human_kb "$TOTAL_DELETE_KB")"

if [[ "$MODE" == "dry-run" ]]; then
  echo
  echo "Dry-run complete. Nothing deleted."
  echo "Run with --apply to delete after confirmation."
  exit 0
fi

echo
read -r -p "Delete listed items? Type 'yes' to confirm: " answer
if [[ "$answer" != "yes" ]]; then
  echo "Cancelled. Nothing deleted."
  exit 0
fi

while IFS= read -r path; do
  [[ -e "$path" ]] || continue
  if [[ "$path" == "." || "$path" == "./" || "$path" == "./.git" || "$path" == ".git" ]]; then
    continue
  fi
  rm -rf -- "$path"
done < "$TMP_LIST"

PROJECT_AFTER_KB="$(du -sk . | awk '{print $1}')"
FREED_KB=$((PROJECT_BEFORE_KB - PROJECT_AFTER_KB))
if [[ "$FREED_KB" -lt 0 ]]; then
  FREED_KB=0
fi

echo
echo "Cleanup complete."
echo "Project size (after): $(human_kb "$PROJECT_AFTER_KB")"
echo "Freed space: $(human_kb "$FREED_KB")"
