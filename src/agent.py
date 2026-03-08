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
"""

import os
import sys
from pathlib import Path
import anthropic
from dotenv import load_dotenv

# Ensure the project root is on the path so config.py is importable
# regardless of where this module is imported from.
sys.path.insert(0, str(Path(__file__).parent.parent))

from config import OPUS_MODEL, MAX_TOKENS

load_dotenv()


def call(
    system_prompt: str,
    user_message: str,
    model: str = OPUS_MODEL,
    max_tokens: int = MAX_TOKENS,
) -> str:
    """
    Send a request to the Anthropic API and return the model's text response.

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

    Returns
    -------
    str
        The model's full text response.

    Raises
    ------
    EnvironmentError
        If ANTHROPIC_API_KEY is not set in the environment.
    anthropic.APIError
        If the API call fails for any reason.
    """
    api_key = os.getenv("ANTHROPIC_API_KEY")
    if not api_key:
        raise EnvironmentError(
            "ANTHROPIC_API_KEY is not set. "
            "Add it to your .env file and try again."
        )

    client = anthropic.Anthropic(api_key=api_key)

    response = client.messages.create(
        model=model,
        max_tokens=max_tokens,
        system=system_prompt,
        messages=[
            {"role": "user", "content": user_message}
        ],
    )

    # Extract text from the response content blocks.
    # The API can return multiple blocks; we join all text blocks in order.
    return "".join(
        block.text
        for block in response.content
        if hasattr(block, "text")
    )
