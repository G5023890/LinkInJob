from __future__ import annotations

from typing import List
import warnings

warnings.filterwarnings("ignore", message=".*NotOpenSSLWarning.*")
warnings.filterwarnings("ignore", module=r"urllib3.*")

try:
    from urllib3.exceptions import NotOpenSSLWarning

    warnings.filterwarnings("ignore", category=NotOpenSSLWarning)
except Exception:
    pass

import requests

GOOGLE_TRANSLATE_URL = "https://translate.googleapis.com/translate_a/single"


def _chunk_text(text: str, max_chars: int = 4000) -> List[str]:
    text = text or ""
    if len(text) <= max_chars:
        return [text]

    chunks: list[str] = []
    start = 0
    while start < len(text):
        end = min(start + max_chars, len(text))
        split_at = text.rfind("\n", start, end)
        if split_at <= start:
            split_at = end
        chunks.append(text[start:split_at])
        start = split_at
    return [chunk for chunk in chunks if chunk]


def _translate_chunk(chunk: str, timeout: int = 20) -> str:
    params = {
        "client": "gtx",
        "sl": "auto",
        "tl": "ru",
        "dt": "t",
        "q": chunk,
    }
    response = requests.get(GOOGLE_TRANSLATE_URL, params=params, timeout=timeout)
    response.raise_for_status()

    payload = response.json()
    if not isinstance(payload, list) or not payload:
        return chunk

    fragments = payload[0]
    if not isinstance(fragments, list):
        return chunk

    translated_parts: list[str] = []
    for frag in fragments:
        if isinstance(frag, list) and frag and frag[0]:
            translated_parts.append(str(frag[0]))

    return "".join(translated_parts).strip() or chunk


def translate_to_ru(text: str | None) -> str | None:
    if text is None:
        return None

    clean = text.strip()
    if not clean:
        return clean

    try:
        chunks = _chunk_text(clean, max_chars=4000)
        translated = [_translate_chunk(chunk) for chunk in chunks]
        return "\n".join(part for part in translated if part).strip() or clean
    except Exception:
        return clean
