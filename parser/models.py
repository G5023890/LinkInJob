from __future__ import annotations

from dataclasses import asdict, dataclass


@dataclass
class ParsedJob:
    company: str | None
    role: str | None
    location: str | None
    stage: str
    job_link: str | None
    description_en: str | None
    description_ru: str | None
    date: str | None
    source_file: str

    def to_dict(self) -> dict:
        return asdict(self)
