from __future__ import annotations

from pathlib import Path

from .extractors import (
    detect_domain_name_from_url,
    extract_company,
    extract_date,
    extract_description,
    extract_job_link,
    extract_location,
    extract_role,
    extract_sender,
    extract_subject,
    normalize_email,
)
from .models import ParsedJob
from .stage_detector import detect_email_type, detect_stage
from .translator import translate_to_ru


def _read_file(file_path: Path) -> str:
    try:
        return file_path.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        try:
            return file_path.read_text(errors="ignore")
        except Exception:
            return ""


def parse_email(file_path: str | Path) -> ParsedJob:
    path = Path(file_path)
    raw_text = _read_file(path)
    normalized = normalize_email(raw_text)

    subject = None
    sender = None
    email_type = "unknown"
    stage = "Applied"
    company = None
    role = None
    location = None
    job_link = None
    description_en = None
    description_ru = None
    extracted_date = None

    try:
        subject = extract_subject(raw_text, normalized)
    except Exception:
        pass
    if not subject:
        try:
            stem = path.stem
            if " - " in stem:
                subject = stem.split(" - ", 1)[1].strip()
        except Exception:
            pass

    try:
        sender = extract_sender(raw_text)
    except Exception:
        pass

    try:
        email_type = detect_email_type(normalized)
        stage = detect_stage(email_type)
    except Exception:
        stage = "Applied"

    try:
        company = extract_company(subject, normalized, sender)
    except Exception:
        company = None

    try:
        role = extract_role(subject, normalized)
    except Exception:
        role = None

    try:
        location = extract_location(normalized)
    except Exception:
        location = None

    try:
        job_link = extract_job_link(normalized)
    except Exception:
        job_link = None

    if not company:
        try:
            company = detect_domain_name_from_url(job_link)
        except Exception:
            company = None

    try:
        description_en = extract_description(normalized)
    except Exception:
        description_en = normalized[:2000] if normalized else None

    try:
        description_ru = translate_to_ru(description_en)
    except Exception:
        description_ru = description_en

    try:
        extracted_date = extract_date(raw_text, path)
    except Exception:
        extracted_date = None

    return ParsedJob(
        company=company,
        role=role,
        location=location,
        stage=stage,
        job_link=job_link,
        description_en=description_en,
        description_ru=description_ru,
        date=extracted_date,
        source_file=str(path),
    )
