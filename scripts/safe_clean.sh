#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(pwd -P)"
MODE="dry-run"

if [[ $# -gt 1 ]]; then
  echo "Использование: $0 [--apply]"
  exit 1
fi

if [[ $# -eq 1 ]]; then
  case "$1" in
    --apply)
      MODE="apply"
      ;;
    *)
      echo "Неизвестный аргумент: $1"
      echo "Использование: $0 [--apply]"
      exit 1
      ;;
  esac
fi

declare -a CANDIDATES=()
declare -a SKIPPED_GO_PATHS=()

humanize_kb() {
  local kb="$1"
  awk -v kb="$kb" 'BEGIN {
    bytes = kb * 1024
    split("B KiB MiB GiB TiB", units, " ")
    i = 1
    while (bytes >= 1024 && i < 5) {
      bytes /= 1024
      i++
    }
    printf("%.2f %s", bytes, units[i])
  }'
}

size_kb() {
  local path="$1"
  du -sk "$path" | awk '{print $1}'
}

is_go_bin_artifact() {
  local dir="$1"
  local parent
  parent="$(cd "$dir/.." && pwd -P)"

  [[ -f "$parent/go.mod" ]] || return 1

  if find "$dir" -type f \( -name "*.sh" -o -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.rb" -o -name "*.pl" -o -name "*.zsh" -o -name "*.fish" -o -name "*.command" \) -print -quit | grep -q .; then
    return 1
  fi

  while IFS= read -r -d '' f; do
    if [[ -x "$f" ]]; then
      return 0
    fi
  done < <(find "$dir" -type f -print0)

  return 1
}

is_go_pkg_artifact() {
  local dir="$1"
  local parent
  parent="$(cd "$dir/.." && pwd -P)"

  [[ -f "$parent/go.mod" ]] || return 1

  if [[ -d "$dir/mod" || -d "$dir/sumdb" ]]; then
    return 0
  fi

  return 1
}

collect_candidates() {
  local -a raw=()
  local -a filtered=()
  local -a sorted=()
  local -a pruned=()
  local path base kept line

  SKIPPED_GO_PATHS=()

  while IFS= read -r -d '' path; do
    raw+=("$path")
  done < <(
    find "$ROOT_DIR" \
      -name .git -prune -o \
      \( \
        -type d \( \
          -name node_modules -o \
          -name dist -o \
          -name build -o \
          -name .cache -o \
          -name tmp -o \
          -name .tmp -o \
          -name .build -o \
          -name DerivedData -o \
          -name __pycache__ -o \
          -name .pytest_cache -o \
          -name .mypy_cache -o \
          -name target -o \
          -name bin -o \
          -name pkg -o \
          -name CMakeFiles -o \
          -name xcuserdata -o \
          -name .codex -o \
          -name .agent \
        \) -o \
        -type f \( \
          -name "*.log" -o \
          -name ".DS_Store" -o \
          -name "*.xcuserstate" -o \
          -name "*.pyc" -o \
          -name "CMakeCache.txt" \
        \) \
      \) -print0
  )

  if [[ ${#raw[@]} -gt 0 ]]; then
    for path in "${raw[@]}"; do
      base="$(basename "$path")"

      if [[ "$base" == "bin" ]]; then
        if is_go_bin_artifact "$path"; then
          filtered+=("$path")
        else
          SKIPPED_GO_PATHS+=("$path")
        fi
        continue
      fi

      if [[ "$base" == "pkg" ]]; then
        if is_go_pkg_artifact "$path"; then
          filtered+=("$path")
        else
          SKIPPED_GO_PATHS+=("$path")
        fi
        continue
      fi

      filtered+=("$path")
    done
  fi

  if [[ ${#filtered[@]} -gt 0 ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && sorted+=("$line")
    done < <(printf '%s\n' "${filtered[@]}" | sort -u)
  fi

  if [[ ${#sorted[@]} -gt 0 ]]; then
    for path in "${sorted[@]}"; do
      local skip=0

      if [[ ${#pruned[@]} -gt 0 ]]; then
        for kept in "${pruned[@]}"; do
          if [[ "$path" == "$kept" ]]; then
            skip=1
            break
          fi

          if [[ -d "$kept" && "$path" == "$kept/"* ]]; then
            skip=1
            break
          fi
        done
      fi

      if [[ "$skip" -eq 0 ]]; then
        pruned+=("$path")
      fi
    done
  fi

  CANDIDATES=()
  if [[ ${#pruned[@]} -gt 0 ]]; then
    CANDIDATES=("${pruned[@]}")
  fi
}

print_report() {
  local project_kb total_kb
  project_kb="$(size_kb "$ROOT_DIR")"
  total_kb=0

  echo "Текущая директория проекта: $ROOT_DIR"
  echo "Размер проекта: $(humanize_kb "$project_kb")"
  echo
  echo "Найдено для удаления:"

  if [[ ${#CANDIDATES[@]} -eq 0 ]]; then
    echo "  (ничего не найдено)"
  else
    for path in "${CANDIDATES[@]}"; do
      local kb rel
      kb="$(size_kb "$path")"
      total_kb=$((total_kb + kb))
      rel="${path#$ROOT_DIR/}"
      printf '  %-10s %s\n' "$(humanize_kb "$kb")" "$rel"
    done
  fi

  echo
  echo "Суммарный размер к удалению: $(humanize_kb "$total_kb")"

  if [[ ${#SKIPPED_GO_PATHS[@]} -gt 0 ]]; then
    echo
    echo "Пропущены как потенциально НЕ build-артефакты (Go):"
    for path in "${SKIPPED_GO_PATHS[@]}"; do
      echo "  ${path#$ROOT_DIR/}"
    done
  fi
}

safe_delete() {
  local path="$1"

  case "$path" in
    "$ROOT_DIR"/*) ;;
    *)
      echo "Пропуск (вне текущей директории): $path"
      return
      ;;
  esac

  if [[ "$path" == *"/.git" || "$path" == *"/.git/"* ]]; then
    echo "Пропуск (.git защищен): $path"
    return
  fi

  if [[ -d "$path" && ! -L "$path" ]]; then
    rm -rf -- "$path"
  elif [[ -e "$path" || -L "$path" ]]; then
    rm -f -- "$path"
  fi
}

collect_candidates
print_report

if [[ "$MODE" == "dry-run" ]]; then
  echo
  echo "Dry-run завершен. Для удаления выполните: $0 --apply"
  exit 0
fi

if [[ ${#CANDIDATES[@]} -eq 0 ]]; then
  echo
  echo "Удалять нечего."
  exit 0
fi

echo
read -r -p "Подтвердить удаление перечисленных путей? [y/N]: " answer
case "$answer" in
  y|Y|yes|YES)
    ;;
  *)
    echo "Отменено пользователем."
    exit 0
    ;;
esac

before_kb="$(size_kb "$ROOT_DIR")"

for path in "${CANDIDATES[@]}"; do
  echo "Удаление: ${path#$ROOT_DIR/}"
  safe_delete "$path"
done

after_kb="$(size_kb "$ROOT_DIR")"
freed_kb=$((before_kb - after_kb))
if (( freed_kb < 0 )); then
  freed_kb=0
fi

echo
echo "Новый размер проекта: $(humanize_kb "$after_kb")"
echo "Освобождено: $(humanize_kb "$freed_kb")"
