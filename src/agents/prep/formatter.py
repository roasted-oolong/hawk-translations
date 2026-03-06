"""Formatter — cleans raw Korean source. Haiku, no bible needed."""

from ..base import call_claude, AgentResult
from ...config import HAIKU_MODEL


async def run_formatter(korean_raw: str) -> AgentResult:
    system = [{"type": "text", "text":
        "You are a Korean text formatter. Your only job is to clean raw Korean "
        "text so it reads naturally. Fix spacing, line breaks, and OCR/encoding "
        "artifacts. Return ONLY the cleaned Korean text — no commentary, no translation."
    }]

    prompt = f"Format and clean this raw Korean chapter text:\n\n{korean_raw}"

    return await call_claude(
        model=HAIKU_MODEL,
        system_parts=system,
        user_message=prompt,
        agent_name="formatter",
        label="Formatting Korean source",
    )
