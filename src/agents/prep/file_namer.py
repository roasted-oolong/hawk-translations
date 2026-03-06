"""File namer — derives output filename. Haiku, titles list only."""

from ..base import call_claude, AgentResult
from ...config import HAIKU_MODEL


async def run_file_namer(korean_filename: str, existing_titles: list[str]) -> AgentResult:
    examples = "\n".join(existing_titles[-5:]) if existing_titles else "(none yet)"

    system = [{"type": "text", "text":
        "You derive English output filenames for translated Korean novel chapters. "
        "Return ONLY the filename — nothing else. No explanation, no punctuation after."
    }]

    prompt = (
        f"Korean source filename: {korean_filename}\n\n"
        f"Existing chapter filenames (match this pattern exactly):\n{examples}\n\n"
        f"Format: Chapter [##] - [English Chapter Title].txt\n"
        f"Return ONLY the filename."
    )

    return await call_claude(
        model=HAIKU_MODEL,
        system_parts=system,
        user_message=prompt,
        agent_name="file_namer",
        label="Naming output file",
    )
