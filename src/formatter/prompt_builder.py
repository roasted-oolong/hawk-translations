"""
src/formatter/prompt_builder.py
--------------------------------
Responsible for one thing: assembling the system prompt and user message
sent to the formatting agent.

This module has no knowledge of the API, file I/O, or orchestration.
It receives a dict of chapter number → raw Korean text and returns two plain
strings (system prompt, user message). Nothing more.

Batching: multiple chapters are sent in a single call. Each chapter is wrapped
in === CHAPTER N === / === END CHAPTER N === delimiters so the response can
be split back into individual chapters by response_parser.py.

To change the formatting instructions the model receives, edit only this file.
"""


# ---------------------------------------------------------------------------
# Prompts
# ---------------------------------------------------------------------------

_SYSTEM_PROMPT = """\
You are a text formatting assistant for Korean literary source files.

Your sole task is to make the Korean text more readable by fixing structural issues
introduced during file creation or OCR — such as broken sentences, unnatural line
breaks in the middle of a clause, and split words.

Rules:
- Merge lines that are broken mid-sentence or mid-clause into a single coherent sentence.
- Fix unnatural word breaks where a single word has been split across lines.
- Preserve every word, phrase, and sentence exactly as written. Do not rephrase.
- Do not add, remove, or substitute any content.
- Do not translate. Do not summarise. Do not reorder content.
- Preserve intentional paragraph breaks — a blank line between paragraphs should remain.
- Preserve dialogue formatting — each new speaker's line should remain on its own line.
- Preserve chapter headings, section markers, and any structural elements as-is.

Output format:
- For each chapter, output its formatted text wrapped in delimiters exactly as shown:

=== CHAPTER N ===
[formatted text here]
=== END CHAPTER N ===

- Replace N with the actual chapter number.
- Output all chapters in the order they were provided.
- Do not include any commentary, preamble, or text outside the delimiters.
"""


def build_system_prompt() -> str:
    """Return the formatting system prompt."""
    return _SYSTEM_PROMPT


def build_user_message(chapters: dict[int, str]) -> str:
    """
    Assemble the user message for a batch of chapters.

    Parameters
    ----------
    chapters : dict[int, str]
        Mapping of chapter number → raw Korean text, in the order to process.

    Returns
    -------
    str
        The user-turn message to send to the API.
    """
    blocks = []
    for num in sorted(chapters.keys()):
        text = chapters[num].strip()
        blocks.append(f"=== CHAPTER {num} ===\n{text}\n=== END CHAPTER {num} ===")

    chapter_text = "\n\n".join(blocks)
    return f"Format the following Korean chapter(s) for readability:\n\n{chapter_text}"
