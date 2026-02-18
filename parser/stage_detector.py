from __future__ import annotations


def detect_email_type(text: str) -> str:
    lowered = (text or "").lower()

    applied_markers = [
        "your application was sent",
        "application submitted",
    ]
    auto_reply_markers = [
        "we received your application",
        "thank you for applying",
    ]
    interview_markers = [
        "interview",
        "schedule a call",
        "invite you to",
    ]
    reject_markers = [
        "we regret",
        "not moving forward",
        "unfortunately",
    ]

    if any(marker in lowered for marker in applied_markers):
        return "applied"
    if any(marker in lowered for marker in auto_reply_markers):
        return "auto_reply"
    if any(marker in lowered for marker in interview_markers):
        return "interview"
    if any(marker in lowered for marker in reject_markers):
        return "reject"
    return "unknown"


def detect_stage(email_type: str) -> str:
    mapping = {
        "applied": "Applied",
        "auto_reply": "Applied",
        "interview": "Interview",
        "reject": "Rejected",
        "unknown": "Applied",
    }
    return mapping.get(email_type, "Applied")
