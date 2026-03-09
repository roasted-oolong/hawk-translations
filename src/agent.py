"""
src/agent.py
------------
Responsible for one thing: making a single call to the Anthropic API and
returning the model's text response.

This module has no knowledge of translation, Korean, bible files, or any
domain-specific logic. It receives two plain strings — a system prompt and a
user message — and returns a plain string. All domain knowledge lives
elsewhere.

To change retry logic or add streaming, edit only this file. Nothing else
needs to change.

Model selection and token limits are controlled by the caller via parameters.
Defaults are imported from config.py so there is a single source of truth.

Usage
-----
For simple one-off calls, use the module-level `call()` function — it builds
a client from the environment automatically:

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

import os
import sys
from pathlib import Path
from typing import Protocol

import anthropic
from dotenv import load_dotenv

sys.path.insert(0, str(Path(__file__).parent.parent))

from config import OPUS_MODEL, MAX_TOKENS

load_dotenv()


# ---------------------------------------------------------------------------
# Protocol for injectable API call functions
# ---------------------------------------------------------------------------

class ApiCallFn(Protocol):
    """
    Protocol for a function that takes a system prompt and user message
    and returns the model's text response.

    Used to type-check api_call_fn parameters in modules like runner.py
    that receive the function as a dependency rather than importing agent
    directly.
    """
    def __call__(self, system_prompt: str, user_message: str) -> str: ...


# ---------------------------------------------------------------------------
# Client construction
# ---------------------------------------------------------------------------

def make_client() -> anthropic.Anthropic:
    """
    Build and return an Anthropic client from the environment.

    Call this once at application startup and pass the client into `call()`
    for batch operations, rather than letting `call()` rebuild it each time.

    Raises
    ------
    EnvironmentError
        If ANTHROPIC_API_KEY is not set in the environment.
    """
    api_key = os.getenv("ANTHROPIC_API_KEY")
    if not api_key:
        raise EnvironmentError(
            "ANTHROPIC_API_KEY is not set. "
            "Add it to your .env file and try again."
        )
    return anthropic.Anthropic(api_key=api_key)


# ---------------------------------------------------------------------------
# API call
# ---------------------------------------------------------------------------

# The SDK refuses non-streaming calls that could exceed 10 minutes.
# Streaming is used whenever max_tokens is high enough to trigger that check.
# 32k is a conservative threshold — well below the SDK's internal limit but
# high enough that normal preread/translation calls are unaffected.
_STREAMING_THRESHOLD = 32000


def call(
    system_prompt: str,
    user_message: str,
    model: str = OPUS_MODEL,
    max_tokens: int = MAX_TOKENS,
    client: anthropic.Anthropic | None = None,
) -> str:
    """
    Send a request to the Anthropic API and return the model's text response.

    Streaming is used automatically when max_tokens exceeds _STREAMING_THRESHOLD,
    because the SDK rejects non-streaming calls that may take longer than 10
    minutes. The return value is identical either way — a single complete string.

    Parameters
    ----------
    system_prompt : str
        The full system prompt to send. Assembled by prompt_builder.py.
    user_message : str
        The user-turn message. For translation, this is the Korean source text.
    model : str
        The model to use. Defaults to OPUS_MODEL from config.py.
    max_tokens : int
        Maximum tokens in the response. Defaults to MAX_TOKENS from config.py.
    client : anthropic.Anthropic | None
        Optional pre-built client. If None, one is created from the environment.
        Pass a pre-built client for batch operations to avoid recreating it
        on every call.

    Returns
    -------
    str
        The model's full text response.

    Raises
    ------
    EnvironmentError
        If ANTHROPIC_API_KEY is not set and no client is provided.
    anthropic.APIError
        If the API call fails for any reason.
    """
    if client is None:
        client = make_client()

    params = dict(
        model=model,
        max_tokens=max_tokens,
        system=system_prompt,
        messages=[{"role": "user", "content": user_message}],
    )

    if max_tokens >= _STREAMING_THRESHOLD:
        with client.messages.stream(**params) as stream:
            return stream.get_final_text()

    response = client.messages.create(**params)
    return "".join(
        block.text
        for block in response.content
        if hasattr(block, "text")
    )
