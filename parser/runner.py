from __future__ import annotations

import argparse
import json
from pathlib import Path

if __package__:
    from .email_parser import parse_email
else:  # pragma: no cover
    import sys

    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from parser.email_parser import parse_email


def parse_folder(folder: str | Path) -> list[dict]:
    base = Path(folder)
    if not base.exists() or not base.is_dir():
        raise NotADirectoryError(str(base))

    files = sorted(
        [*base.rglob("*.txt"), *base.rglob("*.html")],
        key=lambda p: p.name.lower(),
    )

    parsed: list[dict] = []
    for file_path in files:
        try:
            job = parse_email(file_path)
            payload = job.to_dict()
            parsed.append(payload)
            print(f"{payload.get('company') or 'Unknown'} | {payload.get('role') or 'Unknown'} | {payload.get('stage')}")
        except Exception:
            # Keep parser resilient and continue processing all files.
            continue

    output_path = base / "parsed_jobs.json"
    output_path.write_text(json.dumps(parsed, ensure_ascii=False, indent=2), encoding="utf-8")
    return parsed


def _build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Parse job-related emails into structured JSON.")
    parser.add_argument("folder", help="Folder containing .txt/.html email files")
    return parser


def main() -> None:
    args = _build_arg_parser().parse_args()
    parse_folder(args.folder)


if __name__ == "__main__":
    main()
