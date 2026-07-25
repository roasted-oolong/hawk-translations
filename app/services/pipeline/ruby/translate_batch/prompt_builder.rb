# ---------------------------------------------------------------------------
# Pipeline::Ruby::TranslateBatch::PromptBuilder
#
# Ruby port of src/prompt_builder.py plus the reference-file-loading half of
# src/translator/chapter_loader.py — assembles TranslationContext and the
# system prompt for one translate_batch call. No knowledge of the API,
# subprocess mechanics, or batch/progress orchestration; receives a novel
# directory and returns plain strings/structs.
#
# SYSTEM_PROMPT_TEMPLATE is a byte-for-byte port of Python's
# build_translation_prompt output (verified against a live
# `python3 -c "from src.prompt_builder import ..."` run — see
# PromptBuilderSpec's byte-match test) with one deliberate difference: the
# "use the web_search tool" sentence is stripped, per the R4 design's
# recommendation (a) in docs/RAILS_REFACTOR_PLAN.md — R3's bridge never
# wired web_search, so the ported prompt must not instruct the model to use
# a tool absent from its own --mcp-config.
# ---------------------------------------------------------------------------
module Pipeline
  module Ruby
    class TranslateBatch
      module PromptBuilder
        TranslationContext = Data.define(
          :novel_info, :translation_guidelines, :narrator_note, :characters,
          :cultural_phrases, :locations, :story, :terminology, :voice_calibration
        )

        # Keys match TranslationContext field names. Ported verbatim from
        # config.py's NOVEL_FILES — chapter_log.md is intentionally excluded
        # there (archive only, never sent to the API), so it has no entry here.
        NOVEL_FILES = {
          novel_info:             [ "novel_info.md", :novel ],
          translation_guidelines: [ "translation_guidelines.md", :novel ],
          voice_calibration:      [ "voice_calibration.md", :bible ],
          characters:             [ "characters.md", :bible ],
          cultural_phrases:       [ "cultural_phrases.md", :bible ],
          locations:              [ "locations.md", :bible ],
          story:                  [ "story.md", :bible ],
          terminology:            [ "terminology.md", :bible ]
        }.freeze

        # Ported from chapter_loader.py's _extract_narrator_note. Ruby's ^/$
        # already anchor per-line (Python's re.MULTILINE is always-on
        # behavior here); /m adds Python's re.DOTALL equivalent (. matches
        # newlines). \z (not \Z) matches Python's \Z exactly — Ruby's \Z
        # would additionally match just before a trailing newline, which
        # Python's \Z does not.
        NARRATOR_NOTE_PATTERN = /^## Narrator Note\s*\n(.*?)(?=^##|\z)/m

        def self.load_reference_files(novel_dir)
          bible_dir = File.join(novel_dir, "bible")
          NOVEL_FILES.to_h do |key, (filename, location)|
            dir = location == :novel ? novel_dir : bible_dir
            [ key, read_file(File.join(dir, filename)) ]
          end
        end

        def self.extract_narrator_note(novel_info)
          match = NARRATOR_NOTE_PATTERN.match(novel_info.to_s)
          match ? match[1].strip : ""
        end

        def self.build_system_prompt(context)
          reference_sections = [
            Pipeline::PromptUtils.section("Novel Info", context.novel_info),
            Pipeline::PromptUtils.section("Translation Guidelines", context.translation_guidelines),
            Pipeline::PromptUtils.section("Voice Calibration", context.voice_calibration),
            Pipeline::PromptUtils.section("Narrator Note", context.narrator_note),
            Pipeline::PromptUtils.section("Character Bible", context.characters),
            Pipeline::PromptUtils.section("Cultural Phrases", context.cultural_phrases),
            Pipeline::PromptUtils.section("Locations", context.locations),
            Pipeline::PromptUtils.section("Story Bible", context.story),
            Pipeline::PromptUtils.section("Terminology", context.terminology)
          ]
          references = reference_sections.reject(&:empty?).join("\n---\n\n")

          # .chomp: Python's f-string ends immediately after {references}
          # with no trailing newline; the heredoc's own closing line adds
          # one Ruby's f-string equivalent doesn't have, so it's stripped
          # here to keep byte-for-byte parity with build_translation_prompt.
          <<~PROMPT.chomp
            You are a professional Korean-to-English literary translator working on a novel intended for potential publishing. Quality is the top priority — take your time and never rush.

            Your sole task in this call is to translate the Korean chapter provided in the user message into English. Follow the Translation Guidelines exactly. Use the reference material below to ensure consistency with established character names, speech patterns, terminology, cultural phrases, and narrative voice.

            Produce the complete translated chapter. Do not summarize, skip sections, or add commentary outside the translation itself.

            ---

            # Reference Material

            #{references}
          PROMPT
        end

        def self.read_file(path)
          File.exist?(path) ? File.read(path, encoding: "UTF-8") : ""
        end
        private_class_method :read_file
      end
    end
  end
end
