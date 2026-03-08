"""
src/review/discussion.py
------------------------
Responsible for one thing: running an interactive follow-up conversation
with Opus about a specific finding, pattern, or retirement candidate.

Called when the user types 'e' (edit/discuss) at a confirmation prompt.
The conversation runs in a loop until the user types 'done', 'accept', or
'skip', at which point control returns to the caller with a decision.

This module has no knowledge of file I/O, bible structure, or how findings
were generated. It receives the context already assembled by the caller and
conducts the conversation. Nothing more.
"""

import anthropic

from config import OPUS_MODEL, MAX_TOKENS


# ---------------------------------------------------------------------------
# Return values
# ---------------------------------------------------------------------------

class DiscussionResult:
    ACCEPT = "accept"   # Write / remove as-is (or as revised)
    SKIP   = "skip"     # Do nothing with this item
    # The revised content is stored in .content (may be None for SKIP)

    def __init__(self, outcome: str, content: str | None = None):
        self.outcome = outcome
        self.content = content

    @property
    def accepted(self) -> bool:
        return self.outcome == self.ACCEPT

    @property
    def skipped(self) -> bool:
        return self.outcome == self.SKIP


# ---------------------------------------------------------------------------
# Discussion loop
# ---------------------------------------------------------------------------

_INSTRUCTIONS = """\
  Commands:
    [message]  — send a message to Opus
    accept     — accept the current version and continue
    skip       — discard this item and continue
    show       — reprint the current version of this item
"""

_DISCUSSION_SYSTEM = """\
You are helping a translator refine a voice calibration entry or review finding.
The translator may push back, ask for revisions, or ask questions about your reasoning.

Respond concisely. If asked to revise an entry, produce the complete revised version
in the same format as the original — ready to copy directly into the calibration file.
Do not add commentary outside the revised entry unless the translator asks a question.
"""


def run_discussion(
    item_label: str,
    item_content: str,
    original_context: str,
    client: anthropic.Anthropic,
) -> DiscussionResult:
    """
    Run an interactive discussion loop about a single review item.

    Parameters
    ----------
    item_label : str
        Short label shown in the prompt (e.g. "New Pattern 1/2").
    item_content : str
        The current text of the item being discussed.
    original_context : str
        The original user message from the review call — contains the
        translated chapter and voice calibration, giving Opus full context
        for the discussion.
    client : anthropic.Anthropic
        Pre-built Anthropic client.

    Returns
    -------
    DiscussionResult
        Outcome (accept/skip) and the final content to write, if accepted.
    """
    current_content = item_content
    history: list[dict] = []

    # Seed the conversation with the original context and the item.
    seed = (
        f"Here is the full review context (translated chapter + voice calibration):\n\n"
        f"{original_context}\n\n"
        f"---\n\n"
        f"The item we are discussing:\n\n{current_content}"
    )
    history.append({"role": "user", "content": seed})

    print()
    print(_INSTRUCTIONS)

    while True:
        raw = input(f"  [{item_label}] > ").strip()

        if not raw:
            continue

        command = raw.lower()

        if command == "accept":
            return DiscussionResult(DiscussionResult.ACCEPT, current_content)

        if command == "skip":
            return DiscussionResult(DiscussionResult.SKIP)

        if command == "show":
            print()
            print(current_content)
            print()
            continue

        # Treat anything else as a message to Opus.
        history.append({"role": "user", "content": raw})

        response = client.messages.create(
            model=OPUS_MODEL,
            max_tokens=MAX_TOKENS,
            system=_DISCUSSION_SYSTEM,
            messages=history,
        )

        reply = "".join(
            block.text
            for block in response.content
            if hasattr(block, "text")
        )

        history.append({"role": "assistant", "content": reply})

        print()
        print(reply)
        print()

        # If the reply looks like a revised entry (starts with ##), update
        # current_content so 'accept' writes the latest version.
        if reply.lstrip().startswith("##"):
            current_content = reply.strip()
            print("  (Current version updated. Type 'accept' to write, 'show' to review.)")
            print()
