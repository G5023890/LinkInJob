from __future__ import annotations

import html
import re
from datetime import datetime
from email.utils import parsedate_to_datetime
from pathlib import Path
from urllib.parse import urlparse


def normalize_email(text: str) -> str:
    try:
        clean = html.unescape(text or "")
        clean = re.sub(r"<[^>]+>", " ", clean)
        clean = clean.replace("\r\n", "\n").replace("\r", "\n")
        clean = re.sub(r"[ \t]+", " ", clean)
        clean = re.sub(r"\n{3,}", "\n\n", clean)
        lines = [line.strip() for line in clean.split("\n")]
        return "\n".join(lines).strip()
    except Exception:
        return (text or "").strip()


def extract_subject(raw_text: str, normalized_text: str) -> str | None:
    try:
        match = re.search(r"(?im)^(?:subject|тема):\s*(.+)$", raw_text or "")
        if match:
            return match.group(1).strip()

        # Fallback to first meaningful line
        for line in (normalized_text or "").split("\n")[:40]:
            stripped = line.strip()
            low = stripped.lower()
            if re.match(r"^(from|to|date|subject|от|кому|дата|тема):", low):
                continue
            if stripped in {"-----", "----------------------------------------"}:
                continue
            if len(stripped) >= 8 and "@" not in low:
                return line.strip()
    except Exception:
        pass
    return None


def extract_sender(raw_text: str) -> str | None:
    try:
        match = re.search(r"(?im)^(?:from|от):\s*(.+)$", raw_text or "")
        return match.group(1).strip() if match else None
    except Exception:
        return None


def _titleize_domain(domain: str) -> str:
    base = domain.split(".")[0]
    base = re.sub(r"[^a-zA-Z0-9]+", " ", base)
    return " ".join(part.capitalize() for part in base.split() if part) or None


def _company_from_sender(sender: str | None) -> str | None:
    if not sender:
        return None
    sender_name = re.sub(r"<[^>]+>", "", sender).strip().strip("\"'")
    if sender_name and "@" in sender_name:
        sender_name = ""
    if sender_name and len(sender_name) > 2 and "linkedin" not in sender_name.lower():
        return sender_name
    m = re.search(r"([A-Za-z0-9._%+-]+)@([A-Za-z0-9.-]+\.[A-Za-z]{2,})", sender)
    if not m:
        return None
    domain = m.group(2).lower()
    if "linkedin." in domain:
        return None
    return _titleize_domain(domain)


def _cleanup_company(value: str | None) -> str | None:
    if not value:
        return None
    value = re.sub(r"\s+", " ", value).strip(" -:;,.\t")
    if len(value) < 2:
        return None
    low = value.lower()
    if re.search(r"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\b", low):
        return None
    if low in {"linkedin", "дата", "от", "subject"}:
        return None
    if sum(ch.isdigit() for ch in value) >= 4:
        return None
    return value


def extract_company(subject: str | None, text: str, sender: str | None = None) -> str | None:
    haystacks = [subject or "", text or ""]

    patterns = [
        r"(?:sent to|at|from)\s+([A-Z][A-Za-z0-9&.\- ]{2,60})",
        r"(?:application(?:\s+was)?\s+sent\s+to)\s+([A-Z][A-Za-z0-9&.\- ]{2,60})",
        r"(?:в\s+компани(?:ю|и)|компания)\s+([A-ZА-Я][A-Za-zА-Яа-я0-9&.\- ]{2,80})",
    ]

    try:
        for source in haystacks:
            for pat in patterns:
                m = re.search(pat, source)
                if m:
                    candidate = _cleanup_company(m.group(1))
                    if candidate:
                        if candidate.lower() in {"linkedin", "дата", "от"}:
                            continue
                        return candidate

        # Labeled lines
        lines = (text or "").split("\n")
        for idx, line in enumerate(lines[:-1]):
            if line.lower().strip() in {"company:", "organization:", "компания:", "организация:"}:
                candidate = _cleanup_company(lines[idx + 1])
                if candidate:
                    return candidate

        if subject:
            m = re.search(r"(?i)\bat\s+([A-Z][A-Za-z0-9&.\- ]{2,80})", subject)
            if m:
                candidate = _cleanup_company(m.group(1))
                if candidate and "linkedin" not in candidate.lower():
                    return candidate

        sender_based = _company_from_sender(sender)
        if sender_based:
            return sender_based
    except Exception:
        pass

    return None


def _cleanup_role(role: str | None) -> str | None:
    if not role:
        return None
    role = re.sub(r"\s+", " ", role).strip(" -:;,.\t")
    if len(role) < 2:
        return None
    if role.lower() in {"от", "дата", "тема", "from", "date", "subject"}:
        return None
    if role.count(" ") > 18:
        return None
    bad_fragments = [
        "hi ",
        "your application was sent to",
        "your saved job",
        "thank you",
        "текст",
        "дата:",
        "от:",
        "ваша заявка",
        "мы получили",
    ]
    low = role.lower()
    if any(fragment in low for fragment in bad_fragments):
        return None
    if low.startswith("at ") or low.startswith("at"):
        return None
    return role


def extract_role(subject: str | None, text: str) -> str | None:
    source = "\n".join(filter(None, [subject or "", text or ""]))

    patterns = [
        r"(?:position|role|for the position)\s+(.+?)(?:\n| at | in )",
        r"(?i)for\s+the\s+(.+?)\s+position",
        r"(?i)thank you for applying for the\s+(.+?)\s+position",
        r"(?i)application for\s+(.+?)(?:\n| at | in )",
        r"(?i)ваканси(?:я|ю)\s+[«\"]?(.+?)[»\"]?(?:\s+в|\n|$)",
        r"(?i)apply now to\s+[‘'\"]?(.+?)[’'\"]?(?:$|\n)",
    ]

    try:
        for pat in patterns:
            m = re.search(pat, source, flags=re.IGNORECASE)
            if m:
                candidate = _cleanup_role(m.group(1))
                if candidate:
                    return candidate

        # Subject fallback: text before colon often role in digest emails
        if subject:
            if re.search(r"(?i)your application was sent to|ваша заявка на вакансию", subject):
                return None
            m = re.match(r"\s*([^:]{2,120}):", subject)
            if m:
                role = _cleanup_role(m.group(1))
                if role:
                    return role
            # Quoted role fallback
            m2 = re.search(r"[\"“”«»]([^\"“”«»]{2,120})[\"“”«»]", subject)
            if m2:
                role = _cleanup_role(m2.group(1))
                if role:
                    return role

        # First meaningful line fallback
        for line in (text or "").split("\n"):
            stripped = line.strip()
            low = stripped.lower()
            if re.match(r"^(from|to|date|subject|от|кому|дата|тема):", low):
                continue
            if stripped in {"-----", "----------------------------------------"}:
                continue
            if len(stripped) >= 6 and not re.search(r"https?://|@", stripped):
                if stripped.lower() not in {
                    "job description",
                    "about the role",
                    "responsibilities",
                    "what you'll do",
                    "about this job",
                    "от",
                    "дата",
                    "тема",
                }:
                    return _cleanup_role(stripped)
    except Exception:
        pass

    return None


def extract_location(text: str) -> str | None:
    try:
        patterns = [
            r"\b(Remote|Hybrid)\b",
            r"\b([A-Z][a-z]+(?:\s[A-Z][a-z]+),\sIsrael)\b",
            r"\b(Tel Aviv|Israel)\b",
        ]
        for pat in patterns:
            m = re.search(pat, text or "")
            if m:
                return m.group(1).strip()
    except Exception:
        pass
    return None


def extract_job_link(text: str) -> str | None:
    try:
        urls = re.findall(r"https?://[^\s]+", text or "")
        if not urls:
            return None

        noise_fragments = [
            "/help/",
            "unsubscribe",
            "email-unsubscribe",
            "/mypreferences/",
            "/psettings/",
            "/share?",
            "/feed/",
            "trkemail=",
            "securityhelp",
        ]

        filtered: list[str] = []
        for url in urls:
            lower = url.lower().rstrip(".,;)")
            if any(fragment in lower for fragment in noise_fragments):
                continue
            filtered.append(url.rstrip(".,;)"))

        if not filtered:
            filtered = [u.rstrip(".,;)") for u in urls]

        def rank(url: str) -> tuple[int, int]:
            lower = url.lower()
            if "linkedin.com" in lower and ("/jobs/view/" in lower or "/company/" in lower or "/jobs/search/" in lower):
                return (0, len(url))
            if "greenhouse.io" in lower or "greenhouse" in lower:
                return (1, len(url))
            if "lever.co" in lower or "lever" in lower:
                return (2, len(url))
            if "workday" in lower:
                return (3, len(url))
            return (4, len(url))

        ranked = sorted(filtered, key=rank)
        return ranked[0]
    except Exception:
        return None


def extract_description(text: str) -> str | None:
    if not text:
        return None

    try:
        lowered = text.lower()
        markers = [
            "job description",
            "about the role",
            "responsibilities",
            "what you'll do",
            "about this job",
        ]

        for marker in markers:
            idx = lowered.find(marker)
            if idx >= 0:
                chunk = text[idx : idx + 5000]
                chunk = re.sub(r"\n{3,}", "\n\n", chunk).strip()
                return chunk[:5000]

        fallback = text[:2000].strip()
        return fallback or None
    except Exception:
        return (text[:2000] if text else None)


def extract_date(raw_text: str, file_path: Path) -> str | None:
    try:
        date_match = re.search(r"(?im)^(?:date|дата):\s*(.+)$", raw_text or "")
        if date_match:
            parsed = parsedate_to_datetime(date_match.group(1).strip())
            if parsed:
                return parsed.isoformat()
    except Exception:
        pass

    try:
        ts = file_path.stat().st_mtime
        return datetime.fromtimestamp(ts).isoformat()
    except Exception:
        return None


def detect_domain_name_from_url(url: str | None) -> str | None:
    if not url:
        return None
    try:
        host = urlparse(url).hostname
        if not host:
            return None
        if "linkedin.com" in host.lower():
            return None
        parts = host.split(".")
        if len(parts) < 2:
            return None
        return _titleize_domain(parts[-2])
    except Exception:
        return None
