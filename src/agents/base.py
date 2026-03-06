"""
Base agent — shared Claude API call with retry/backoff.
All agents import call_claude from here.
"""

import time
import anthropic
from typing import List, Optional
from pydantic import BaseModel


# ── Client (singleton) ────────────────────────────────────────────────────────
_client: Optional[anthropic.Anthropic] = None


def get_client() -> anthropic.Anthropic:
    global _client
    if _client is None:
        import os
        from dotenv import load_dotenv
        load_dotenv()
        api_key = os.getenv("ANTHROPIC_API_KEY")
        if not api_key:
            raise RuntimeError("ANTHROPIC_API_KEY not found in environment.")
        _client = anthropic.Anthropic(api_key=api_key)
    return _client


# ── Result model ──────────────────────────────────────────────────────────────
class AgentResult(BaseModel):
    success: bool
    output: Optional[str] = None
    error: Optional[str] = None
    agent_name: str
    execution_time_ms: int


# ── Core call with retry/backoff ──────────────────────────────────────────────
def call_claude(
    agent_name: str,
    model: str,
    system_parts: List[dict],
    user_message: str,
    max_tokens: int = 16000,
    max_retries: int = 4,
    label: str = "",
) -> AgentResult:
    """
    Call Claude with automatic retry on rate limit (429) errors.
    Backoff: 15s, 30s, 60s, 120s.
    """
    if label:
        print(f"\n  [{label}] calling {model}...")

    backoff_seconds = [15, 30, 60, 120]
    start = time.time()

    for attempt in range(max_retries):
        try:
            client = get_client()
            response = client.messages.create(
                model=model,
                max_tokens=max_tokens,
                system=system_parts,
                messages=[{"role": "user", "content": user_message}],
            )
            text = "".join(
                block.text for block in response.content
                if hasattr(block, "text")
            )
            elapsed = int((time.time() - start) * 1000)
            return AgentResult(
                success=True,
                output=text,
                agent_name=agent_name,
                execution_time_ms=elapsed,
            )

        except anthropic.RateLimitError as e:
            if attempt < max_retries - 1:
                wait = backoff_seconds[attempt]
                print(f"\n  [rate limit] waiting {wait}s before retry "
                      f"(attempt {attempt + 1}/{max_retries})...")
                time.sleep(wait)
            else:
                elapsed = int((time.time() - start) * 1000)
                return AgentResult(
                    success=False,
                    error=f"Rate limit after {max_retries} attempts: {e}",
                    agent_name=agent_name,
                    execution_time_ms=elapsed,
                )

        except anthropic.APIError as e:
            elapsed = int((time.time() - start) * 1000)
            return AgentResult(
                success=False,
                error=f"API error: {e}",
                agent_name=agent_name,
                execution_time_ms=elapsed,
            )

        except Exception as e:
            elapsed = int((time.time() - start) * 1000)
            return AgentResult(
                success=False,
                error=f"Unexpected error: {e}",
                agent_name=agent_name,
                execution_time_ms=elapsed,
            )

    elapsed = int((time.time() - start) * 1000)
    return AgentResult(
        success=False,
        error="Max retries exceeded",
        agent_name=agent_name,
        execution_time_ms=elapsed,
    )
