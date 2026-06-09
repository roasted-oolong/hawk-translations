"""
src/agent.py
------------
Responsible for one thing: making a single call to a local LLM via an
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

The `ApiCallFn` Protocol is exported for type-checking callers that accept
an api_call_fn argument.
"""

import sys
from pathlib import Path
from typing import Protocol

from openai import OpenAI
from dotenv import load_dotenv

sys.path.insert(0, str(Path(__file__).parent.parent))

from config import OPUS_MODEL, MAX_TOKENS, LLM_BASE_URL, LLM_API_KEY

load_dotenv()


# ---------------------------------------------------------------------------
# Protocol for injectable API call functions
# ---------------------------------------------------------------------------

class ApiCallFn(Protocol):
    def __call__(self, system_prompt: str, user_message: str) -> str: ...


# ---------------------------------------------------------------------------
# Client construction
# ---------------------------------------------------------------------------

def make_client() -> OpenAI:
    """Build and return an OpenAI-compatible client from the environment."""
    return OpenAI(base_url=LLM_BASE_URL, api_key=LLM_API_KEY, timeout=1200.0)


# ---------------------------------------------------------------------------
# API call
# ---------------------------------------------------------------------------

def call(
    system_prompt: str,
    user_message: str,
    model: str = OPUS_MODEL,
    max_tokens: int = MAX_TOKENS,
    client: OpenAI | None = None,
) -> str:
    """
    Send a request to the local LLM and return the model's text response.

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
        Optional pre-built client. If None, one is created from the environment.
        Pass a pre-built client for batch operations to avoid recreating it
        on every call.

    Returns
    -------
    str
        The model's full text response.
    """
    if client is None:
        client = make_client()

    response = client.chat.completions.create(
        model=model,
        max_tokens=max_tokens,
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_message},
        ],
    )
    return response.choices[0].message.content or ""
