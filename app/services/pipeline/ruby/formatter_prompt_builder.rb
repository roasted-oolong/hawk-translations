# ---------------------------------------------------------------------------
# Pipeline::Ruby::FormatterPromptBuilder
#
# Ruby port of src/formatter/prompt_builder.py — assembles the system prompt
# and user message for a formatting call. No knowledge of the API, file I/O,
# or orchestration; receives a chapter-number => raw-text hash and returns two
# plain strings.
#
# Batch-shaped (chapters: {Integer => String}) even though
# FormatKoreanChapterJob only ever formats one chapter at a time today —
# ported with the same signature as the Python original so a future batch
# caller costs nothing extra.
#
# SYSTEM_PROMPT is a byte-for-byte port of Python's _SYSTEM_PROMPT, verified
# against a live `python3` invocation of build_system_prompt() (see
# spec/fixtures/formatter/system_prompt.txt and this class's spec).
# ---------------------------------------------------------------------------
module Pipeline
  module Ruby
    module FormatterPromptBuilder
      SYSTEM_PROMPT = <<~PROMPT
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
      PROMPT

      def self.build_system_prompt
        SYSTEM_PROMPT
      end

      def self.build_user_message(chapters)
        blocks = chapters.keys.sort.map do |num|
          "=== CHAPTER #{num} ===\n#{chapters[num].strip}\n=== END CHAPTER #{num} ==="
        end

        "Format the following Korean chapter(s) for readability:\n\n#{blocks.join("\n\n")}"
      end
    end
  end
end
