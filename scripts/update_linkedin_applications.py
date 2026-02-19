#!/usr/bin/env python3
import argparse
import html
import re
import unicodedata
import urllib.request
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple


HOME = Path.home()
ICLOUD_ROOT = HOME / "Library" / "Mobile Documents" / "iCloud~md~obsidian" / "Documents" / "M.Greg"
WORK_ROOT = ICLOUD_ROOT / "Работа"

DEFAULT_SOURCE_DIR = HOME / "Library" / "Application Support" / "DriveCVSync" / "LinkedIn Archive"
DEFAULT_TARGET_FILE = WORK_ROOT / "Поданные и откланенные заявки" / "System_Administrator.md"
DEFAULT_VACANCIES_FILE = WORK_ROOT / "LinkedIn" / "Компания.md"
DEFAULT_COMPANY_DIR = WORK_ROOT / "LinkedIn"
DEFAULT_ARCHIVE_DIR = WORK_ROOT / "LinkedIn" / "Archive"
DEFAULT_MANUAL_DIR = WORK_ROOT / "Поданные и откланенные заявки" / "System_Administrator"
DEFAULT_REVIEW_FILE = WORK_ROOT / "LinkedIn" / "Проверить_вручную.md"


def normalize_company(name: str) -> str:
    normalized = unicodedata.normalize("NFKC", name)
    normalized = normalized.replace("\u00a0", " ").replace("\u202f", " ")
    cleaned = " ".join(normalized.split())
    cleaned = cleaned.strip(".,!?:;\"'()[]«»“”")
    cleaned = cleaned.strip()
    return cleaned


def extract_subject(text: str) -> str:
    match = re.search(r"^(?:Тема|ТЕМА):\s*(.+)$", text, flags=re.MULTILINE)
    if match:
        return match.group(1).strip()
    return ""


def first_company_match(text: str, patterns: List[str]) -> Optional[str]:
    for pattern in patterns:
        match = re.search(pattern, text, flags=re.IGNORECASE | re.MULTILINE)
        if match:
            company = normalize_company(match.group(1))
            if company:
                return company
    return None


def extract_company(text: str, filename: str) -> Optional[str]:
    subject = extract_subject(text)
    haystack = f"{subject}\n{text}\n{filename}"

    patterns = [
        r"Ваша заявка была отправлена в компанию\s+([^\n]+)",
        r"Ваша заявка на вакансию.+?в компании\s+([^\n]+)",
        r"Ваша заявка была просмотрена в компании\s+([^\n]+)",
        r"your application was sent to\s+([^\n!]+)",
        r"Your application was viewed by\s+([^\n]+)",
        r"Thank you for applying to\s+([^\n!]+)",
        r"Thanks for applying to\s+([^\n!]+)",
        r"Wow\s*-\s*thanks for applying to\s+([^\n!]+)",
        r"Thank you for applying for.+?\sat\s+([^\n\.,!]+)",
        r"Thanks for applying for.+?\sat\s+([^\n\.,!]+)",
        r"Application to\s+([^\n\)]+)",
        r"position at\s*([A-Za-z][A-Za-z0-9& .\-]{1,60})",
        r"Your application at\s+([^\n]+)",
    ]

    company = first_company_match(haystack, patterns)
    if company:
        return company

    # Fallback: take last fragment after a dash in filename if it looks like a company.
    fallback = re.sub(r"^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}\s+-\s+", "", filename).replace(".txt", "")
    fallback = normalize_company(fallback)
    if fallback and "LinkedIn data archive" not in fallback:
        return fallback
    return None


def classify(text: str) -> Tuple[bool, bool, bool]:
    lowered = text.lower()

    is_noise = any(
        marker in lowered
        for marker in [
            "оповещение о вакансиях linkedin",
            "новая вакансия, соответствующая вашим предпочтениям",
            "new jobs similar to",
            "your full linkedin data archive is ready",
            " and more",
        ]
    )
    if is_noise:
        return False, False, False

    is_rejection = any(
        marker in lowered
        for marker in [
            "application_rejected",
            "move forward with other candidates",
            "decided to move forward with other candidates",
            "решили двигаться дальше",
            "отклон",
            "отказ",
        ]
    )

    interview_patterns = [
        r"interview invitation",
        r"invited to (an )?interview",
        r"invite you to (an )?interview",
        r"schedule (an )?interview",
        r"приглаш[а-я]* на собесед",
        r"приглашаем на собесед",
        r"приглашение на собесед",
        r"назначить собесед",
    ]
    is_interview = any(re.search(pattern, lowered) for pattern in interview_patterns)

    is_application = any(
        marker in lowered
        for marker in [
            "ваша заявка была отправлена в компанию",
            "ваша заявка на вакансию",
            "ваша заявка была просмотрена в компании",
            "thank you for applying",
            "thanks for applying",
            "wow - thanks for applying",
            "we got it: thanks for applying",
            "your application at",
            "your application was viewed by",
            "application to ",
            "application has been received",
            "your application was sent to",
            "we now know that you’d like to join our team",
            "we now know that you'd like to join our team",
        ]
    )

    return is_application, is_rejection, is_interview


def is_vacancy_digest(text: str) -> bool:
    lowered = text.lower()
    return any(
        marker in lowered
        for marker in [
            "linkedin job alerts",
            "оповещения о вакансиях linkedin",
            "your job alert for",
            "ваше оповещение о вакансиях",
            "new jobs similar to",
            "jobs similar to",
            "hired roles near you",
            "apply now to",
        ]
    )


def is_non_job_noise(text: str) -> bool:
    lowered = text.lower()
    return any(
        marker in lowered
        for marker in [
            "your full linkedin data archive is ready",
            "share their thoughts on linkedin",
        ]
    )


def format_date(date_raw: str) -> str:
    match = re.match(r"^(\d{4})-(\d{2})-(\d{2})$", date_raw)
    if not match:
        return date_raw
    year, month, day = match.groups()
    return f"{day}.{month}.{year}"


def extract_vacancy_offers(text: str, email_date: str) -> List[Tuple[str, str, str, str]]:
    """
    Extract offers from job alert/recommendation emails.
    Returns tuples of (company, date, role, url).
    """
    offers: List[Tuple[str, str, str, str]] = []
    seen: Set[Tuple[str, str, str, str]] = set()
    lowered = text.lower()

    is_vacancy_mail = is_vacancy_digest(text)
    if not is_vacancy_mail:
        return offers

    block_pattern = re.compile(
        r"(?ms)^\s*(?P<role>[^\n]{2,120})\n"
        r"(?P<company>[^\n]{2,120})\n"
        r"[^\n]{0,120}\n"
        r"(?:[^\n]*\n){0,5}?"
        r"(?:View job|См\.\s*вакансию):\s*(?P<url>https?://\S+)"
    )

    for match in block_pattern.finditer(text):
        role = normalize_company(match.group("role"))
        company = normalize_company(match.group("company"))
        url = match.group("url").strip()

        if company.lower().startswith("ваша заявка была"):
            continue
        if role.lower() in {"текст", "jobs similar to"}:
            continue

        item = (company, email_date, role, url)
        if company and role and url and item not in seen:
            seen.add(item)
            offers.append(item)

    # Fallback for lines like: "Jobs similar to ... at WalkMe https://..."
    inline_pattern = re.compile(
        r"(?im)^(?:Jobs similar to|Вакансии, похожие на).+?\bat\s+(.+?)\s+(https?://\S+)\s*$"
    )
    for match in inline_pattern.finditer(text):
        company = normalize_company(match.group(1))
        role = "Позиция по ссылке"
        url = match.group(2).strip()
        item = (company, email_date, role, url)
        if company and url and item not in seen:
            seen.add(item)
            offers.append(item)

    return offers


def build_vacancies_markdown(vacancies: List[Tuple[str, str, str, str]]) -> str:
    lines: List[str] = []
    if not vacancies:
        lines.append("Нет новых предложений вакансий.")
        lines.append("")
        return "\n".join(lines)

    for company, date_raw, role, url in vacancies:
        lines.append(company)
        lines.append(format_date(date_raw))
        lines.append(role)
        lines.append(f"[Ссылка]({url})")
        lines.append("")
    return "\n".join(lines)


def filename_from_company(company: str) -> str:
    cleaned = normalize_company(company)
    cleaned = re.sub(r"[\\\\/:*?\"<>|]+", " ", cleaned)
    cleaned = " ".join(cleaned.split())
    return f"{cleaned}.md" if cleaned else "Компания.md"


def extract_job_id(url: str) -> Optional[str]:
    match = re.search(r"/jobs/view/(\d+)", url)
    if match:
        return match.group(1)
    match = re.search(r"/comm/jobs/view/(\d+)", url)
    if match:
        return match.group(1)
    return None


def strip_html_to_text(raw_html: str) -> str:
    text = re.sub(r"(?is)<br\\s*/?>", "\n", raw_html)
    text = re.sub(r"(?is)</p>", "\n\n", text)
    text = re.sub(r"(?is)</li>", "\n", text)
    text = re.sub(r"(?is)<li[^>]*>", "- ", text)
    text = re.sub(r"(?is)<[^>]+>", "", text)
    text = html.unescape(text)
    lines = [ln.rstrip() for ln in text.splitlines()]
    cleaned = "\n".join(lines)
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned).strip()
    return cleaned


def fetch_about_job_text(job_url: str, cache: Dict[str, str]) -> str:
    job_id = extract_job_id(job_url)
    if not job_id:
        return "Не удалось определить jobId из ссылки."
    if job_id in cache:
        return cache[job_id]

    api_url = f"https://www.linkedin.com/jobs-guest/jobs/api/jobPosting/{job_id}"
    req = urllib.request.Request(api_url, headers={"User-Agent": "Mozilla/5.0"})
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            raw = response.read().decode("utf-8", errors="ignore")
    except Exception as exc:  # pragma: no cover - network dependent
        text = f"Не удалось получить описание автоматически: {exc}"
        cache[job_id] = text
        return text

    # Description block on LinkedIn public job page payload.
    match = re.search(r'(?is)<div class="show-more-less-html__markup[^>]*>(.*?)</div>', raw)
    if not match:
        text = "Блок 'About the job' не найден автоматически. Откройте ссылку вручную."
        cache[job_id] = text
        return text

    text = strip_html_to_text(match.group(1))
    if not text:
        text = "Описание вакансии пустое или недоступно."
    cache[job_id] = text
    return text


def write_company_files(vacancies: List[Tuple[str, str, str, str]], company_dir: Path) -> Tuple[int, Set[str]]:
    grouped: Dict[str, List[Tuple[str, str, str]]] = {}
    for company, date_raw, role, url in vacancies:
        grouped.setdefault(company, []).append((date_raw, role, url))

    company_dir.mkdir(parents=True, exist_ok=True)
    fetched_cache: Dict[str, str] = {}
    created = 0
    generated_names: Set[str] = set()

    for company in sorted(grouped, key=lambda x: x.lower()):
        lines: List[str] = [company, ""]
        for date_raw, role, url in grouped[company]:
            lines.append(format_date(date_raw))
            lines.append(role)
            lines.append(f"[Ссылка]({url})")
            lines.append("")
            lines.append("About the job:")
            lines.append(fetch_about_job_text(url, fetched_cache))
            lines.append("")
            lines.append("---")
            lines.append("")

        content = "\n".join(lines).rstrip() + "\n"
        path = company_dir / filename_from_company(company)
        path.write_text(content, encoding="utf-8")
        generated_names.add(path.name)
        created += 1

    return created, generated_names


def company_key(name: str) -> str:
    return normalize_company(name).casefold()


def archived_companies_from_dir(archive_dir: Path) -> Set[str]:
    keys: Set[str] = set()
    if not archive_dir.exists():
        return keys
    for p in archive_dir.iterdir():
        if not p.is_file():
            continue
        if p.suffix.lower() not in {".md", ".txt"}:
            continue
        keys.add(company_key(p.stem))
    return keys


def load_manual_status_overrides(
    manual_dir: Path,
) -> Tuple[Set[str], Set[str], Set[str], Set[str], Set[str], Set[str]]:
    """
    Manual overrides from:
    - <manual_dir>/applied/*.md|*.txt
    - <manual_dir>/rejected/*.md|*.txt
    - <manual_dir>/interview/*.md|*.txt
    """
    applied_names: Set[str] = set()
    rejected_names: Set[str] = set()
    interview_names: Set[str] = set()
    applied_keys: Set[str] = set()
    rejected_keys: Set[str] = set()
    interview_keys: Set[str] = set()

    mapping = {
        "applied": (applied_names, applied_keys),
        "rejected": (rejected_names, rejected_keys),
        "interview": (interview_names, interview_keys),
    }

    for folder, targets in mapping.items():
        names_target, keys_target = targets
        d = manual_dir / folder
        d.mkdir(parents=True, exist_ok=True)
        for p in d.iterdir():
            if not p.is_file():
                continue
            if p.suffix.lower() not in {".md", ".txt"}:
                continue
            name = normalize_company(p.stem)
            if not name:
                continue
            names_target.add(name)
            keys_target.add(company_key(name))

    return applied_names, rejected_names, interview_names, applied_keys, rejected_keys, interview_keys


def sorted_unique(values: Set[str]) -> List[str]:
    return sorted(values, key=lambda v: v.lower())


def build_markdown(applied: List[str], rejected: List[str], interviews: List[str]) -> str:
    lines: List[str] = []
    lines.append("#Компании с поданным резюме")
    lines.extend([f"- {company}" for company in applied] or ["- Пока нет данных."])
    lines.append("")
    lines.append("#Компании ответившие отказом")
    lines.extend([f"- {company}" for company in rejected] or ["- Пока нет данных."])
    lines.append("")
    lines.append("#Компании пригласившие на интервью")
    lines.extend([f"- {company}" for company in interviews] or ["- Пока нет данных."])
    lines.append("")
    return "\n".join(lines)


def build_review_markdown(entries: List[Tuple[str, str, str]]) -> str:
    lines: List[str] = []
    lines.append("#Письма для ручной проверки")
    if not entries:
        lines.append("- Нет писем для ручной проверки.")
        lines.append("")
        return "\n".join(lines)

    for filename, date_raw, subject in entries:
        lines.append(f"- {filename}")
        if date_raw:
            lines.append(f"  Дата: {format_date(date_raw)}")
        if subject:
            lines.append(f"  Тема: {subject}")
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Analyze LinkedIn email .txt files and update markdown summary."
    )
    parser.add_argument("--source-dir", type=Path, default=DEFAULT_SOURCE_DIR)
    parser.add_argument("--target-file", type=Path, default=DEFAULT_TARGET_FILE)
    parser.add_argument("--vacancies-file", type=Path, default=DEFAULT_VACANCIES_FILE)
    parser.add_argument("--company-dir", type=Path, default=DEFAULT_COMPANY_DIR)
    parser.add_argument("--archive-dir", type=Path, default=DEFAULT_ARCHIVE_DIR)
    parser.add_argument("--manual-dir", type=Path, default=DEFAULT_MANUAL_DIR)
    parser.add_argument("--review-file", type=Path, default=DEFAULT_REVIEW_FILE)
    args = parser.parse_args()

    source_dir = args.source_dir
    target_file = args.target_file
    vacancies_file = args.vacancies_file
    company_dir = args.company_dir
    archive_dir = args.archive_dir
    manual_dir = args.manual_dir
    review_file = args.review_file

    if not source_dir.exists():
        raise SystemExit(f"Source directory not found: {source_dir}")

    applied: Set[str] = set()
    rejected: Set[str] = set()
    interviews: Set[str] = set()
    vacancies: List[Tuple[str, str, str, str]] = []
    seen_vacancies: Set[Tuple[str, str, str, str]] = set()
    review_entries: List[Tuple[str, str, str]] = []
    archived_names: Set[str] = set()
    archived_company_keys: Set[str] = archived_companies_from_dir(archive_dir)
    if archive_dir.exists():
        archived_names = {p.name for p in archive_dir.glob("*.txt")}
    (
        manual_applied_names,
        manual_rejected_names,
        manual_interview_names,
        manual_applied_keys,
        manual_rejected_keys,
        manual_interview_keys,
    ) = load_manual_status_overrides(manual_dir)

    for file_path in sorted(source_dir.glob("*.txt")):
        try:
            text = file_path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue

        date_match = re.match(r"^(\d{4}-\d{2}-\d{2})_", file_path.name)
        email_date = date_match.group(1) if date_match else ""
        subject = extract_subject(text)

        if file_path.name in archived_names:
            offers_from_file: List[Tuple[str, str, str, str]] = []
        else:
            offers_from_file = extract_vacancy_offers(text, email_date)

        for offer in offers_from_file:
            if offer not in seen_vacancies:
                seen_vacancies.add(offer)
                vacancies.append(offer)

        company = extract_company(text, file_path.name)
        if not company:
            continue

        is_application, is_rejection, is_interview = classify(text)
        if is_application or is_rejection or is_interview:
            applied.add(company)
        if is_rejection:
            rejected.add(company)
        if is_interview:
            interviews.add(company)

        if not (is_application or is_rejection or is_interview):
            suspect = any(
                marker in text.lower()
                for marker in [
                    "apply",
                    "applying",
                    "application",
                    "заявк",
                    "resume",
                    "cv",
                    "job",
                    "vacancy",
                    "position",
                ]
            )
            if suspect and not is_vacancy_digest(text) and not is_non_job_noise(text):
                review_entries.append((file_path.name, email_date, subject))

    status_companies: Set[str] = {company_key(c) for c in applied | rejected | interviews}
    status_companies |= manual_applied_keys | manual_rejected_keys | manual_interview_keys
    filtered_vacancies: List[Tuple[str, str, str, str]] = []
    excluded_companies: Set[str] = set()
    for company, date_raw, role, url in vacancies:
        ckey = company_key(company)
        if ckey in status_companies:
            excluded_companies.add(company)
            continue
        if ckey in archived_company_keys:
            excluded_companies.add(company)
            continue
        filtered_vacancies.append((company, date_raw, role, url))

    content = build_markdown(
        applied=sorted(manual_applied_names, key=lambda v: v.lower()),
        rejected=sorted(manual_rejected_names, key=lambda v: v.lower()),
        interviews=sorted(manual_interview_names, key=lambda v: v.lower()),
    )

    target_file.parent.mkdir(parents=True, exist_ok=True)
    target_file.write_text(content, encoding="utf-8")
    vacancies_file.parent.mkdir(parents=True, exist_ok=True)
    vacancies_file.write_text(build_vacancies_markdown(filtered_vacancies), encoding="utf-8")
    company_dir.mkdir(parents=True, exist_ok=True)
    for company in excluded_companies:
        excluded_path = company_dir / filename_from_company(company)
        if excluded_path.exists():
            excluded_path.unlink()
    company_files, generated_names = write_company_files(filtered_vacancies, company_dir)
    keep_names = generated_names | {vacancies_file.name, review_file.name}
    for p in company_dir.glob("*.md"):
        if p.name not in keep_names and p.is_file():
            p.unlink()
    review_file.parent.mkdir(parents=True, exist_ok=True)
    review_file.write_text(build_review_markdown(review_entries), encoding="utf-8")

    print(f"Updated: {target_file}")
    print(f"Updated: {vacancies_file}")
    print(f"Updated: {review_file}")
    print(f"Updated company files in: {company_dir}")
    print(f"Applied: {len(applied)} | Rejected: {len(rejected)} | Interviews: {len(interviews)}")
    print(f"Vacancy offers: {len(filtered_vacancies)} (filtered from {len(vacancies)})")
    print(f"Excluded by status: {len(excluded_companies)}")
    print(f"Archive excludes: {len(archived_company_keys)} companies, {len(archived_names)} txt files")
    print(
        "Manual overrides:"
        " source=System_Administrator hierarchy"
        f" applied={len(manual_applied_names)}, rejected={len(manual_rejected_names)}, interview={len(manual_interview_names)}"
    )
    print(f"Company files: {company_files}")
    print(f"Manual review emails: {len(review_entries)}")


if __name__ == "__main__":
    main()
