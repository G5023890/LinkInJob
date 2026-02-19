#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${HOME}/Library/Application Support/ArgosTranslate"
LIB_DIR="${BASE_DIR}/python_lib"
PKG_DIR="${BASE_DIR}/packages"
BIN_DIR="${BASE_DIR}/bin"
LEGACY_PKG_DIR="${HOME}/.local/share/argos-translate/packages"

mkdir -p "${LIB_DIR}" "${PKG_DIR}" "${BIN_DIR}"

python3 -m pip install --upgrade --target "${LIB_DIR}" argostranslate

if [ -d "${LEGACY_PKG_DIR}" ]; then
  rsync -a --ignore-existing "${LEGACY_PKG_DIR}/" "${PKG_DIR}/"
fi

cat > "${BIN_DIR}/argos_translate_cli.py" <<'PY'
#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

BASE_DIR = Path.home() / "Library" / "Application Support" / "ArgosTranslate"
LIB_DIR = BASE_DIR / "python_lib"
PKG_DIR = BASE_DIR / "packages"

if str(LIB_DIR) not in sys.path:
    sys.path.insert(0, str(LIB_DIR))
os.environ.setdefault("ARGOS_PACKAGES_DIR", str(PKG_DIR))

import argostranslate.translate as argos_translate  # noqa: E402


def guess_source_codes(text: str) -> list[str]:
    if re.search(r"[\u0590-\u05FF]", text or ""):
        return ["he", "en"]
    if re.search(r"[\u0600-\u06FF]", text or ""):
        return ["ar", "en"]
    if re.search(r"[А-Яа-яЁё]", text or ""):
        return ["ru"]
    return ["en", "de", "fr", "es", "pt", "it"]


def translate_text(text: str, source: str | None, target: str) -> str:
    installed = argos_translate.get_installed_languages()
    by_code = {lang.code: lang for lang in installed}
    target_lang = by_code.get(target)
    if target_lang is None:
        raise RuntimeError(f"Target model '{target}' is not installed in {os.environ.get('ARGOS_PACKAGES_DIR')}")

    source_codes = [source] if source else guess_source_codes(text)
    for code in source_codes:
        if not code or code == target:
            continue
        src = by_code.get(code)
        if src is None:
            continue
        try:
            return src.get_translation(target_lang).translate(text)
        except Exception:
            continue

    for src in installed:
        if src.code == target:
            continue
        try:
            return src.get_translation(target_lang).translate(text)
        except Exception:
            continue

    raise RuntimeError("No suitable source->target Argos model installed")


def main() -> int:
    parser = argparse.ArgumentParser(description="Local Argos Translate CLI")
    parser.add_argument("--text", help="Text to translate")
    parser.add_argument("--file", help="Path to input file", default="")
    parser.add_argument("--from", dest="source", help="Source language code (optional)", default="")
    parser.add_argument("--to", dest="target", help="Target language code", default="ru")
    args = parser.parse_args()

    text = args.text or ""
    if args.file:
      text = Path(args.file).read_text(encoding="utf-8", errors="ignore")
    if not text.strip():
        print("No input text", file=sys.stderr)
        return 2

    out = translate_text(text, args.source or None, args.target)
    sys.stdout.write(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY

cat > "${BIN_DIR}/argos-translate" <<'SH2'
#!/usr/bin/env bash
set -euo pipefail
BASE_DIR="${HOME}/Library/Application Support/ArgosTranslate"
export ARGOS_PACKAGES_DIR="${ARGOS_PACKAGES_DIR:-${BASE_DIR}/packages}"
export PYTHONPATH="${BASE_DIR}/python_lib${PYTHONPATH:+:${PYTHONPATH}}"
exec /usr/bin/python3 "${BASE_DIR}/bin/argos_translate_cli.py" "$@"
SH2

chmod +x "${BIN_DIR}/argos_translate_cli.py" "${BIN_DIR}/argos-translate"

echo "Argos runtime prepared at: ${BASE_DIR}"
echo "CLI: ${BIN_DIR}/argos-translate"
