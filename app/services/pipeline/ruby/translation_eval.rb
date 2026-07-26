require "fileutils"
require "json"

# ---------------------------------------------------------------------------
# Pipeline::Ruby::TranslationEval
#
# Offline-only prototype harness for the translation quality pipeline idea
# in docs/ROADMAP.md — runs both the existing single-pass prompt and the
# candidate structured (intent/literal/localized) prompt over the same
# chapters, writing both outputs to disk for a human to compare. Not wired
# into translate_batch.rb, PipelineJob, or any TranslationJob: the point is
# to judge quality/cost/JSON-reliability before committing to any change in
# production behavior. Driven by bin/translation_eval.
#
# Takes a plain novel directory rather than a Novel record — this runs
# outside the job system entirely, against chapters already on disk.
# ---------------------------------------------------------------------------
module Pipeline
  module Ruby
    class TranslationEval
      ChapterResult = Struct.new(
        :number, :missing_source, :single_pass_error, :structured_error, :structured_valid_json,
        keyword_init: true
      )

      def self.call(novel_dir:, chapter_numbers:, output_dir:, config: TranslationConfig.from_env)
        new(novel_dir: novel_dir, chapter_numbers: chapter_numbers, output_dir: output_dir, config: config).call
      end

      def initialize(novel_dir:, chapter_numbers:, output_dir:, config:)
        @novel_dir        = novel_dir
        @chapters_dir     = File.join(novel_dir, "chapters")
        @chapter_numbers  = chapter_numbers
        @output_dir       = output_dir
        @config           = config
      end

      def call
        reference_data        = TranslateBatch::PromptBuilder.load_reference_files(@novel_dir)
        narrator_note         = TranslateBatch::PromptBuilder.extract_narrator_note(reference_data[:novel_info])
        context                = TranslateBatch::PromptBuilder::TranslationContext.new(**reference_data, narrator_note: narrator_note)
        single_pass_prompt     = TranslateBatch::PromptBuilder.build_system_prompt(context)
        structured_prompt      = TranslateBatch::PromptBuilder.build_structured_system_prompt(context)
        mcp_config              = TranslateBatch::BridgeConfig.mcp_config(novel_directory_name: File.basename(@novel_dir))

        @chapter_numbers.map { |num| run_chapter(num, single_pass_prompt, structured_prompt, mcp_config) }
      end

      private

      def run_chapter(num, single_pass_prompt, structured_prompt, mcp_config)
        korean_path = File.join(@chapters_dir, "Chapter #{num} (Korean).txt")
        return ChapterResult.new(number: num, missing_source: true) unless File.exist?(korean_path)

        korean_text = File.read(korean_path, encoding: "UTF-8")
        chapter_dir = File.join(@output_dir, "chapter_#{num}")
        FileUtils.mkdir_p(chapter_dir)

        single_pass_error = run_single_pass(chapter_dir, single_pass_prompt, korean_text, mcp_config)
        structured_error, structured_valid_json = run_structured(chapter_dir, structured_prompt, korean_text, mcp_config)

        ChapterResult.new(
          number: num, missing_source: false,
          single_pass_error: single_pass_error,
          structured_error: structured_error,
          structured_valid_json: structured_valid_json
        )
      end

      def run_single_pass(chapter_dir, system_prompt, korean_text, mcp_config)
        result = Pipeline::ClaudeCode.call(
          system_prompt: system_prompt, user_message: korean_text, config: @config, mcp_config: mcp_config
        )
        return "#{result.error_category}: #{result.error_message}" unless result.success?

        File.write(File.join(chapter_dir, "single_pass.txt"), result.output, encoding: "UTF-8")
        nil
      end

      def run_structured(chapter_dir, system_prompt, korean_text, mcp_config)
        result = Pipeline::ClaudeCode.call(
          system_prompt: system_prompt, user_message: korean_text, config: @config, mcp_config: mcp_config
        )
        return [ "#{result.error_category}: #{result.error_message}", nil ] unless result.success?

        begin
          parsed = JSON.parse(result.output)
        rescue JSON::ParserError => e
          File.write(File.join(chapter_dir, "structured.raw.txt"), result.output, encoding: "UTF-8")
          return [ "invalid JSON (#{e.message})", false ]
        end

        File.write(File.join(chapter_dir, "structured.json"), JSON.pretty_generate(parsed), encoding: "UTF-8")
        [ nil, true ]
      end
    end
  end
end
