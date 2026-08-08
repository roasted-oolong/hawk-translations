require "rails_helper"
require "json"

# Direct, file-I/O-free coverage of the shared step-running logic. Both
# Pipeline::Ruby::TranslationEval (offline, dumps files) and production
# Pipeline::Ruby::TranslateBatch call through this class — see their own
# specs for end-to-end behavior built on top of it (file writes, chapter
# attachment, batch-level continue/abort semantics).
RSpec.describe Pipeline::Ruby::TranslateBatch::FiveStepRunner do
  def fake_claude(dir, body)
    path = File.join(dir, "claude")
    File.write(path, "#!#{RbConfig.ruby}\n#{body}")
    File.chmod(0o755, path)
    path
  end

  def config_for(claude_bin)
    TranslationConfig.from_env("PATH" => "", "CLAUDE_BIN" => claude_bin)
  end

  def build_novel_dir(root)
    dir = File.join(root, "test-novel")
    FileUtils.mkdir_p(File.join(dir, "bible"))
    FileUtils.mkdir_p(File.join(dir, "chapters"))
    dir
  end

  def runner_for(novel_dir, claude_bin)
    described_class.build_for_novel(
      novel_dir: novel_dir, novel_directory_name: File.basename(novel_dir), config: config_for(claude_bin)
    )
  end

  # Same technique as translation_eval_spec.rb: each step's system prompt has
  # a unique JSON-shape marker, so one fake claude binary can serve all 5
  # calls for a chapter.
  def scripted_claude(bin_dir, responses_by_variant)
    fake_claude(bin_dir, <<~RUBY)
      require "json"
      STDIN.read
      prompt_path = ARGV[ARGV.index("--system-prompt-file") + 1]
      prompt = File.read(prompt_path)
      variant =
        if prompt.include?('"blocks"')
          "segmentation"
        elsif prompt.include?('"core_message"')
          "analysis"
        elsif prompt.include?('"localized_passages"')
          "localization"
        elsif prompt.include?('"names_preserved"')
          "factcheck"
        elsif prompt.include?('"continuous_utterance"')
          "editor"
        else
          raise "unrecognized system prompt variant"
        end
      responses = #{responses_by_variant.inspect}
      response = responses.fetch(variant) { raise "no scripted response for \#{variant}" }
      puts response.to_json
    RUBY
  end

  def happy_responses
    {
      "segmentation" => { is_error: false, result: { blocks: [ { block_id: 1, speaker: "narration", label: "BREAK" } ] }.to_json },
      "analysis" => { is_error: false, result: { passages: [ { passage_id: 1, core_message: "m", emphasis: "e", pacing_rhythm: "p", voice_register: "v", narrative_function: "f", cultural_signals: "", localization_strategy: { category: "none", notes: "" }, bible_entries_used: [] } ] }.to_json },
      "localization" => { is_error: false, result: { localized_passages: [ { passage_id: 1, localized_translation: "translated" } ] }.to_json },
      "factcheck" => { is_error: false, result: { reviewed_passages: [ { passage_id: 1, checks: { names_preserved: true }, findings: [] } ], review_summary: {} }.to_json },
      "editor" => { is_error: false, result: { reviewed_passages: [ { passage_id: 1, checks: { continuous_utterance: true }, findings: [] } ], review_summary: {} }.to_json }
    }
  end

  around do |example|
    Dir.mktmpdir { |root| @root = root; example.run }
  end

  it "runs all 5 steps successfully and assembles the chapter text" do
    novel_dir = build_novel_dir(@root)

    Dir.mktmpdir do |bin_dir|
      bin = scripted_claude(bin_dir, happy_responses)
      outcome = runner_for(novel_dir, bin).run_chapter(1, "챕터 1 한국어")

      expect(outcome.number).to eq(1)
      expect(outcome.segmentation.ok?).to eq(true)
      expect(outcome.analysis.ok?).to eq(true)
      expect(outcome.localization.ok?).to eq(true)
      expect(outcome.factcheck.ok?).to eq(true)
      expect(outcome.editor.ok?).to eq(true)
      expect(outcome.assembled_text).to eq("translated")
    end
  end

  it "never calls factcheck/editor and leaves them nil when run_qa: false" do
    novel_dir = build_novel_dir(@root)

    Dir.mktmpdir do |bin_dir|
      bin = fake_claude(bin_dir, <<~RUBY)
        require "json"
        STDIN.read
        prompt_path = ARGV[ARGV.index("--system-prompt-file") + 1]
        prompt = File.read(prompt_path)
        raise "factcheck/editor must not be called when run_qa: false" if prompt.include?('"names_preserved"') || prompt.include?('"continuous_utterance"')
        variant =
          if prompt.include?('"blocks"')
            "segmentation"
          elsif prompt.include?('"core_message"')
            "analysis"
          elsif prompt.include?('"localized_passages"')
            "localization"
          end
        payload = case variant
          when "segmentation" then { blocks: [ { block_id: 1, speaker: "narration", label: "BREAK" } ] }
          when "analysis" then { passages: [ { passage_id: 1, core_message: "m", emphasis: "e", pacing_rhythm: "p", voice_register: "v", narrative_function: "f", cultural_signals: "", localization_strategy: { category: "none", notes: "" }, bible_entries_used: [] } ] }
          when "localization" then { localized_passages: [ { passage_id: 1, localized_translation: "translated" } ] }
          end
        puts({ is_error: false, result: payload.to_json }.to_json)
      RUBY

      outcome = runner_for(novel_dir, bin).run_chapter(1, "챕터 1 한국어", run_qa: false)

      expect(outcome.segmentation.ok?).to eq(true)
      expect(outcome.analysis.ok?).to eq(true)
      expect(outcome.localization.ok?).to eq(true)
      expect(outcome.factcheck).to be_nil
      expect(outcome.editor).to be_nil
      expect(outcome.assembled_text).to eq("translated")
    end
  end

  %w[segmentation analysis localization factcheck editor].each do |failing_step|
    it "reports a call failure at #{failing_step} and skips whatever depends on it" do
      novel_dir = build_novel_dir(@root)

      Dir.mktmpdir do |bin_dir|
        responses = happy_responses
        responses[failing_step] = { is_error: true, subtype: "boom", result: "failed" }
        bin = scripted_claude(bin_dir, responses)
        outcome = runner_for(novel_dir, bin).run_chapter(1, "챕터 1 한국어")

        step = outcome.public_send(failing_step)
        expect(step.call_error).to include("cli_failure")
        expect(step.error_category).to eq(:cli_failure)

        case failing_step
        when "segmentation"
          expect(outcome.analysis.call_error).to eq("skipped: segmentation did not produce valid, fully-covered passages")
          expect(outcome.localization.call_error).to eq("skipped: analysis did not produce valid, fully-covered output")
          expect(outcome.factcheck.call_error).to eq("skipped: localization did not produce valid, fully-covered translation")
          expect(outcome.editor.call_error).to eq("skipped: localization did not produce valid, fully-covered translation")
          expect(outcome.assembled_text).to be_nil
        when "analysis"
          expect(outcome.localization.call_error).to eq("skipped: analysis did not produce valid, fully-covered output")
          expect(outcome.assembled_text).to be_nil
        when "localization"
          expect(outcome.factcheck.call_error).to eq("skipped: localization did not produce valid, fully-covered translation")
          expect(outcome.editor.call_error).to eq("skipped: localization did not produce valid, fully-covered translation")
          expect(outcome.assembled_text).to be_nil
        when "factcheck"
          # editor is independent of factcheck and localization still succeeded
          expect(outcome.editor.ok?).to eq(true)
          expect(outcome.assembled_text).to eq("translated")
        when "editor"
          expect(outcome.factcheck.ok?).to eq(true)
          expect(outcome.assembled_text).to eq("translated")
        end
      end
    end
  end

  it "reports a coverage error (not a call error) when segmentation drops a candidate block, with nil error_category" do
    novel_dir = build_novel_dir(@root)
    korean_text = (1..10).map { |i| "문단 #{i} 내용입니다." }.join("\n\n") # 2 candidate blocks

    Dir.mktmpdir do |bin_dir|
      responses = happy_responses
      responses["segmentation"] = { is_error: false, result: { blocks: [ { block_id: 1, speaker: "narration", label: "BREAK" } ] }.to_json }
      bin = scripted_claude(bin_dir, responses)
      outcome = runner_for(novel_dir, bin).run_chapter(1, korean_text)

      expect(outcome.segmentation.call_error).to be_nil
      expect(outcome.segmentation.valid_json).to eq(true)
      expect(outcome.segmentation.coverage_error).to include("missing")
      expect(outcome.segmentation.error_category).to be_nil
      expect(outcome.analysis.call_error).to eq("skipped: segmentation did not produce valid, fully-covered passages")
    end
  end

  it "reports a coverage error when analysis drops a passage_id from segmentation" do
    novel_dir = build_novel_dir(@root)

    Dir.mktmpdir do |bin_dir|
      responses = happy_responses
      responses["analysis"] = { is_error: false, result: { passages: [] }.to_json }
      bin = scripted_claude(bin_dir, responses)
      outcome = runner_for(novel_dir, bin).run_chapter(1, "챕터 1 한국어")

      expect(outcome.analysis.call_error).to be_nil
      expect(outcome.analysis.coverage_error).to include("missing")
      expect(outcome.analysis.error_category).to be_nil
      expect(outcome.localization.call_error).to eq("skipped: analysis did not produce valid, fully-covered output")
    end
  end

  it "reports a coverage error when localization drops a passage_id from analysis" do
    novel_dir = build_novel_dir(@root)

    Dir.mktmpdir do |bin_dir|
      responses = happy_responses
      responses["localization"] = { is_error: false, result: { localized_passages: [] }.to_json }
      bin = scripted_claude(bin_dir, responses)
      outcome = runner_for(novel_dir, bin).run_chapter(1, "챕터 1 한국어")

      expect(outcome.localization.call_error).to be_nil
      expect(outcome.localization.coverage_error).to include("missing")
      expect(outcome.localization.error_category).to be_nil
      expect(outcome.assembled_text).to be_nil
      expect(outcome.factcheck.call_error).to eq("skipped: localization did not produce valid, fully-covered translation")
    end
  end

  it "calls factcheck with factcheck_model, every other step with translation_model" do
    novel_dir = build_novel_dir(@root)

    Dir.mktmpdir do |bin_dir|
      models_log = File.join(bin_dir, "models.log")
      bin = fake_claude(bin_dir, <<~RUBY)
        require "json"
        STDIN.read
        prompt_path = ARGV[ARGV.index("--system-prompt-file") + 1]
        prompt = File.read(prompt_path)
        model = ARGV[ARGV.index("--model") + 1]
        variant =
          if prompt.include?('"blocks"')
            "segmentation"
          elsif prompt.include?('"core_message"')
            "analysis"
          elsif prompt.include?('"localized_passages"')
            "localization"
          elsif prompt.include?('"names_preserved"')
            "factcheck"
          elsif prompt.include?('"continuous_utterance"')
            "editor"
          end
        File.open(#{models_log.inspect}, "a") { |f| f.puts "\#{variant}:\#{model}" }

        payload =
          case variant
          when "segmentation" then { blocks: [ { block_id: 1, speaker: "narration", label: "BREAK" } ] }
          when "analysis" then { passages: [ { passage_id: 1, core_message: "m", emphasis: "e", pacing_rhythm: "p", voice_register: "v", narrative_function: "f", cultural_signals: "", localization_strategy: { category: "none", notes: "" }, bible_entries_used: [] } ] }
          when "localization" then { localized_passages: [ { passage_id: 1, localized_translation: "x" } ] }
          when "factcheck" then { reviewed_passages: [ { passage_id: 1, checks: {}, findings: [] } ], review_summary: {} }
          when "editor" then { reviewed_passages: [ { passage_id: 1, checks: {}, findings: [] } ], review_summary: {} }
          end
        puts({ is_error: false, result: payload.to_json }.to_json)
      RUBY

      runner_for(novel_dir, bin).run_chapter(1, "챕터 1 한국어")

      models_by_variant = File.readlines(models_log).map(&:chomp).to_h { |line| line.split(":", 2) }
      expect(models_by_variant["factcheck"]).to eq("sonnet")
      expect(models_by_variant["segmentation"]).to eq("opus")
      expect(models_by_variant["analysis"]).to eq("opus")
      expect(models_by_variant["localization"]).to eq("opus")
      expect(models_by_variant["editor"]).to eq("opus")
    end
  end
end
