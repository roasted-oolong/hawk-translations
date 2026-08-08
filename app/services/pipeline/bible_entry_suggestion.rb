require "json"

# ---------------------------------------------------------------------------
# Pipeline::BibleEntrySuggestion
#
# One-shot LLM call scoped to a single new bible entry — not part of the
# bible_build/PrereadRunner batch pipeline (that markdown-file pipeline was
# sunset in favor of exactly this kind of inline, per-entry workflow, see
# docs/DECISIONS.md's 2026-07-30 entry). Called synchronously from
# BibleEntrySuggestionsController when a translator Tab-selects English text
# in a chapter editor and chooses "Create as Character/Location/…": given the
# selected English text, some surrounding context, and the chapter's full
# Korean source, finds the Korean equivalent and a small set of
# type-specific descriptive fields to prefill the quick-create form with.
#
# Modeled on Pipeline::Ruby::TranslateBatch::TitleFinalizer — a Result
# struct, one Pipeline::ClaudeCode call, and "failure degrades, it doesn't
# raise": an empty fields hash just means the form's fields stay blank for
# the user to fill in by hand, same as before this feature existed. Never a
# reason to block entry creation.
# ---------------------------------------------------------------------------
module Pipeline
  class BibleEntrySuggestion
    # Keyed by the same `param` string BibleLookupController's
    # CREATE_TYPE_CONFIG/TYPE_PARAMS already use for these types
    # (bible_character, bible_location, ...) — one shared vocabulary across
    # the JS payload, this map, and each bible_*_controller's entry_params,
    # rather than a fourth naming scheme. BibleStoryEntry has no Korean
    # field and isn't listed here — "find the Korean equivalent" doesn't
    # apply to it (see docs/DECISIONS.md).
    FIELD_SPECS = {
      "bible_character" => {
        korean_key:   "korean_name",
        korean_label: "Korean name",
        fields: [
          { key: "role",    label: "Role",    hint: "their function in the story so far, e.g. protagonist's mentor, rival swordsman" },
          { key: "aliases", label: "Aliases",  hint: "other names, titles, or nicknames this character is called by in the given text, comma-separated" },
          { key: "notes",   label: "Notes",    hint: "translation-relevant notes: honorifics used, naming conventions, anything a translator should know" }
        ]
      },
      "bible_location" => {
        korean_key:   "korean_name",
        korean_label: "Korean name",
        fields: [
          { key: "significance", label: "Significance", hint: "why this place matters in the given text" },
          { key: "notes",        label: "Notes",         hint: "translation-relevant notes: preferred rendering, alternatives to avoid" }
        ]
      },
      "bible_terminology" => {
        korean_key:   "korean_term",
        korean_label: "Korean term",
        fields: [
          { key: "definition",   label: "Definition",   hint: "what the term means and how it's used in the given text" },
          { key: "usage_notes",  label: "Usage notes",  hint: "how it should be rendered, capitalized, or whether to leave it untranslated" },
          { key: "notes",        label: "Notes",         hint: "anything else worth flagging" }
        ]
      },
      "bible_cultural_phrase" => {
        korean_key:   "korean_phrase",
        korean_label: "Korean phrase",
        fields: [
          { key: "established_translation", label: "Established translation", hint: "the rendering actually used in the English text" },
          { key: "intended_meaning",        label: "Intended meaning",        hint: "the literal meaning and intended nuance" },
          { key: "notes",                   label: "Notes",                   hint: "when it's used, recurrence, anything else worth flagging" }
        ]
      }
    }.freeze

    Result = Struct.new(:fields, :error_category, :error_message, keyword_init: true) do
      def ok?
        error_category.nil?
      end
    end

    def self.call(entry_type:, english_text:, context_text:, korean_source_text:, config: TranslationConfig.from_env, mcp_config: nil)
      new(entry_type: entry_type, english_text: english_text, context_text: context_text,
          korean_source_text: korean_source_text, config: config, mcp_config: mcp_config).call
    end

    def initialize(entry_type:, english_text:, context_text:, korean_source_text:, config:, mcp_config:)
      @entry_type         = entry_type
      @english_text       = english_text
      @context_text       = context_text
      @korean_source_text = korean_source_text
      @config             = config
      @mcp_config         = mcp_config
    end

    def call
      spec = FIELD_SPECS[@entry_type]
      return empty_result unless spec
      return empty_result if @korean_source_text.blank?

      result = Pipeline::ClaudeCode.call(
        system_prompt: Pipeline::Ruby::TranslateBatch::PromptBuilder.build_bible_entry_suggestion_system_prompt(
          korean_label: spec[:korean_label], korean_key: spec[:korean_key], fields: spec[:fields]
        ),
        user_message: Pipeline::Ruby::TranslateBatch::PromptBuilder.build_bible_entry_suggestion_user_message(
          english_text: @english_text, context_text: @context_text.to_s, korean_source_text: @korean_source_text
        ),
        config:     @config,
        mcp_config: @mcp_config,
        model:      @config.translation_model,
        timeout:    45
      )
      return degrade(result.error_category, "#{result.error_category}: #{result.error_message}") unless result.success?

      begin
        parsed = JSON.parse(result.output)
      rescue JSON::ParserError => e
        return degrade(:unparseable_output, "invalid JSON (#{e.message})")
      end

      allowed_keys = [ spec[:korean_key], *spec[:fields].map { |f| f[:key].to_s } ]
      fields = parsed.slice(*allowed_keys)
        .transform_values { |v| v.to_s.strip }
        .reject { |_, v| v.empty? }

      Result.new(fields: fields)
    end

    private

    def empty_result
      Result.new(fields: {})
    end

    def degrade(error_category, error_message)
      Result.new(fields: {}, error_category: error_category || :suggestion_error, error_message: error_message)
    end
  end
end
