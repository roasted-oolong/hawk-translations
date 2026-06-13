"""
src/agent.py
------------
Responsible for one thing: making a call to a local LLM via an
OpenAI-compatible API and returning the model's text response.

This module has no knowledge of translation, Korean, bible files, or any
domain-specific logic. It receives two plain strings — a system prompt and a
user message — and returns a plain string. All domain knowledge lives
elsewhere.

The LLM endpoint and API key are read from LLM_BASE_URL and LLM_API_KEY in
the environment (see config.py). Defaults point to Ollama on localhost.

Usage
-----
For simple one-off calls, use the module-level `call()` function:

    from src.agent import call
    result = call(system_prompt="...", user_message="...")

For batch operations (e.g. the preread loop), build a client once and inject
it to avoid recreating it per call:

    from src.agent import make_client, call
    client = make_client()
    result = call(system_prompt="...", user_message="...", client=client)

To give the agent skills (e.g. web search), pass a list of Skill instances:

    from src.skills.web_search import WebSearchSkill
    result = call(system_prompt="...", user_message="...", skills=[WebSearchSkill()])

The agent will loop — executing skill calls and feeding results back — until
the model produces a final text response.

The `ApiCallFn` Protocol is exported for type-checking callers that accept
an api_call_fn argument.
"""

import ipaddress
import json
import sys
from pathlib import Path
from typing import Protocol, TYPE_CHECKING
from urllib.parse import urlparse

from openai import OpenAI
from dotenv import load_dotenv

sys.path.insert(0, str(Path(__file__).parent.parent))

from config import OPUS_MODEL, MAX_TOKENS, LLM_BASE_URL, LLM_API_KEY

if TYPE_CHECKING:
    from src.skills.base import Skill

load_dotenv()

_MAX_SKILL_ITERATIONS = 10


# ---------------------------------------------------------------------------
# Protocol for injectable API call functions
# ---------------------------------------------------------------------------

class ApiCallFn(Protocol):
    def __call__(self, system_prompt: str, user_message: str) -> str: ...


# ---------------------------------------------------------------------------
# Client construction
# ---------------------------------------------------------------------------

def _is_local_endpoint(url: str) -> bool:
    """Return True when url points to a loopback or private-network host.

    Local endpoints (localhost, 127.x, private RFC-1918 ranges) run on the
    user's own hardware at no per-token cost, so we impose no timeout and let
    inference finish however long it takes.  Remote endpoints (api.openai.com,
    etc.) are metered, so we keep a sensible timeout.
    """
    try:
        host = urlparse(url).hostname or ""
        if host in ("localhost", "::1"):
            return True
        addr = ipaddress.ip_address(host)
        return addr.is_loopback or addr.is_private
    except ValueError:
        return False  # non-IP hostname other than "localhost" → treat as remote


def make_client() -> OpenAI:
    """Build and return an OpenAI-compatible client from the environment.

    Timeout is disabled for local endpoints (no cost, just slow hardware) and
    capped at 1200 s for remote/paid APIs.
    """
    timeout = None if _is_local_endpoint(LLM_BASE_URL) else 1200.0
    return OpenAI(base_url=LLM_BASE_URL, api_key=LLM_API_KEY, timeout=timeout)


# ---------------------------------------------------------------------------
# API call
# ---------------------------------------------------------------------------

def call(
    system_prompt: str,
    user_message: str,
    model: str = OPUS_MODEL,
    max_tokens: int = MAX_TOKENS,
    client: OpenAI | None = None,
    skills: "list[Skill] | None" = None,
) -> str:
    """
    Send a request to the local LLM and return the model's text response.

    When `skills` are provided the function runs an agentic loop: if the model
    requests a skill call, the skill is executed and the result is fed back
    into the conversation. This repeats until the model produces a plain text
    response or the iteration ceiling is reached.

    Parameters
    ----------
    system_prompt : str
        The full system prompt. Assembled by prompt_builder.py.
    user_message : str
        The user-turn message. For translation, this is the Korean source text.
    model : str
        The model to use. Defaults to OPUS_MODEL from config.py.
    max_tokens : int
        Maximum tokens in the response. Defaults to MAX_TOKENS from config.py.
    client : OpenAI | None
        Optional pre-built client. Pass for batch operations to avoid
        recreating the client on every call.
    skills : list[Skill] | None
        Optional skills the model may invoke. Each Skill provides its own
        tool definition and execution logic.

    Returns
    -------
    str
        The model's full text response.
    """
    if client is None:
        client = make_client()

    messages: list[dict] = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_message},
    ]

    if not skills:
        response = client.chat.completions.create(
            model=model,
            max_tokens=max_tokens,
            messages=messages,
        )
        return response.choices[0].message.content or ""

    skills_by_name = {skill.name: skill for skill in skills}
    tools = [skill.tool_definition for skill in skills]

    for _ in range(_MAX_SKILL_ITERATIONS):
        response = client.chat.completions.create(
            model=model,
            max_tokens=max_tokens,
            messages=messages,
            tools=tools,
        )

        message = response.choices[0].message

        if not message.tool_calls:
            return message.content or ""

        # Append the assistant turn (with its tool_calls) back into messages.
        messages.append({
            "role": "assistant",
            "content": message.content,
            "tool_calls": [
                {
                    "id": tc.id,
                    "type": "function",
                    "function": {
                        "name": tc.function.name,
                        "arguments": tc.function.arguments,
                    },
                }
                for tc in message.tool_calls
            ],
        })

        # Execute each requested skill and return results as tool messages.
        for tool_call in message.tool_calls:
            skill = skills_by_name.get(tool_call.function.name)
            tool_args = json.loads(tool_call.function.arguments)
            result = skill.execute(tool_args) if skill else f"[Unknown skill: {tool_call.function.name}]"

            messages.append({
                "role": "tool",
                "tool_call_id": tool_call.id,
                "content": result,
            })

    return message.content or ""
