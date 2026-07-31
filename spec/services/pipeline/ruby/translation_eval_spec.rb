require "rails_helper"
require "json"

# Offline-only tool (docs/ROADMAP.md's translation quality pipeline note):
# runs the current single-pass prompt, the (superseded, kept for history)
# single-call structured prompt, and Call 1 of the committed 2-call pipeline
# (docs/DECISIONS.md's 2026-07-30 entry) over the same chapters, side by
# side, so a human can judge quality/cost/JSON-reliability — and, for Call 1,
# segmentation exhaustiveness/passage_id stability — before any multi-call
# pipeline goes into production. Not wired into translate_batch or any
# TranslationJob — takes a plain directory, not a Novel record.
RSpec.describe Pipeline::Ruby::TranslationEval do
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

  def write_korean_source(novel_dir, num, text)
    File.write(File.join(novel_dir, "chapters", "Chapter #{num} (Korean).txt"), text)
  end

  # All three calls for one chapter share the same stdin (the Korean
  # source), so responses are keyed on [marker, variant] and the variant is
  # read back off the --system-prompt-file content itself: Call 1 is the
  # only prompt with "chapter_level_notes", the (superseded) structured
  # prompt is the only remaining one with "Respond with a single JSON
  # object", everything else is the single-pass prompt.
  def scripted_claude(bin_dir, responses_by_marker_and_variant)
    fake_claude(bin_dir, <<~RUBY)
      require "json"
      stdin = STDIN.read.force_encoding("UTF-8")
      prompt_path = ARGV[ARGV.index("--system-prompt-file") + 1]
      prompt = File.read(prompt_path)
      variant =
        if prompt.include?('"chapter_level_notes"')
          "call1"
        elsif prompt.include?("Respond with a single JSON object")
          "structured"
        else
          "single_pass"
        end
      responses = #{responses_by_marker_and_variant.inspect}
      match = responses.find { |(marker, v), _| stdin.include?(marker) && v == variant }
      raise "no scripted response for \#{variant}: \#{stdin[0,40].inspect}" unless match
      puts match[1].to_json
    RUBY
  end

  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      Dir.mktmpdir do |out|
        @output_dir = out
        example.run
      end
    end
  end

  it "writes single-pass output and parsed structured JSON for each chapter" do
    novel_dir = build_novel_dir(@root)
    write_korean_source(novel_dir, 1, "챕터 1 한국어")

    Dir.mktmpdir do |bin_dir|
      structured_payload = {
        intent: { narrative_purpose: "show distance", emotional_tone: "melancholic" },
        literal_translation: "literal one",
        localized_translation: "localized one"
      }
      call1_payload = {
        passages: [ { passage_id: 1, anchor_quote: "챕터 1 한국어" } ],
        chapter_level_notes: { risks: [] }
      }
      bin = scripted_claude(bin_dir, {
        [ "챕터 1", "single_pass" ] => { is_error: false, result: "single pass one" },
        [ "챕터 1", "structured" ]  => { is_error: false, result: structured_payload.to_json },
        [ "챕터 1", "call1" ]       => { is_error: false, result: call1_payload.to_json }
      })

      results = described_class.call(
        novel_dir: novel_dir, chapter_numbers: [ 1 ],
        output_dir: @output_dir, config: config_for(bin)
      )

      expect(results.size).to eq(1)
      expect(results.first.number).to eq(1)
      expect(results.first.missing_source).to eq(false)
      expect(results.first.single_pass_error).to be_nil
      expect(results.first.structured_error).to be_nil
      expect(results.first.structured_valid_json).to eq(true)
      expect(results.first.call1_error).to be_nil
      expect(results.first.call1_valid_json).to eq(true)
      expect(results.first.call1_segmentation_error).to be_nil

      chapter_dir = File.join(@output_dir, "chapter_1")
      expect(File.read(File.join(chapter_dir, "single_pass.txt"))).to eq("single pass one")
      expect(JSON.parse(File.read(File.join(chapter_dir, "structured.json")))["localized_translation"]).to eq("localized one")
      expect(JSON.parse(File.read(File.join(chapter_dir, "call1.json")))["chapter_level_notes"]).to eq({ "risks" => [] })
    end
  end

  it "passes bible/cultural_patterns.md content into the structured and call1 prompts only, not the single-pass one" do
    novel_dir = build_novel_dir(@root)
    write_korean_source(novel_dir, 1, "챕터 1 한국어")
    File.write(File.join(novel_dir, "bible", "cultural_patterns.md"), "Status-jockeying pattern notes")

    Dir.mktmpdir do |bin_dir|
      bin = fake_claude(bin_dir, <<~RUBY)
        require "json"
        STDIN.read
        prompt_path = ARGV[ARGV.index("--system-prompt-file") + 1]
        prompt = File.read(prompt_path)
        variant =
          if prompt.include?('"chapter_level_notes"')
            "call1"
          elsif prompt.include?("Respond with a single JSON object")
            "structured"
          else
            "single_pass"
          end

        if variant == "single_pass"
          raise "cultural_patterns content leaked into single-pass prompt" if prompt.include?("Status-jockeying pattern notes")
          puts({ is_error: false, result: "single pass" }.to_json)
        else
          raise "missing cultural_patterns content in \#{variant} prompt" unless prompt.include?("Status-jockeying pattern notes")
          payload = variant == "call1" ? { passages: [], chapter_level_notes: { risks: [] } } : { intent: {}, literal_translation: "l", localized_translation: "loc" }
          puts({ is_error: false, result: payload.to_json }.to_json)
        end
      RUBY

      results = described_class.call(
        novel_dir: novel_dir, chapter_numbers: [ 1 ],
        output_dir: @output_dir, config: config_for(bin)
      )

      expect(results.first.single_pass_error).to be_nil
      expect(results.first.structured_error).to be_nil
      expect(results.first.call1_error).to be_nil
    end
  end

  it "skips chapters with no Korean source without calling claude" do
    novel_dir = build_novel_dir(@root)

    results = described_class.call(
      novel_dir: novel_dir, chapter_numbers: [ 1 ],
      output_dir: @output_dir, config: config_for("/bin/true")
    )

    expect(results.first.missing_source).to eq(true)
    expect(File.exist?(File.join(@output_dir, "chapter_1"))).to eq(false)
  end

  it "saves invalid structured JSON raw instead of crashing the run" do
    novel_dir = build_novel_dir(@root)
    write_korean_source(novel_dir, 1, "챕터 1 한국어")

    Dir.mktmpdir do |bin_dir|
      call1_payload = { passages: [ { passage_id: 1, anchor_quote: "챕터 1 한국어" } ], chapter_level_notes: { risks: [] } }
      bin = scripted_claude(bin_dir, {
        [ "챕터 1", "single_pass" ] => { is_error: false, result: "single pass one" },
        [ "챕터 1", "structured" ]  => { is_error: false, result: "not json at all" },
        [ "챕터 1", "call1" ]       => { is_error: false, result: call1_payload.to_json }
      })

      results = described_class.call(
        novel_dir: novel_dir, chapter_numbers: [ 1 ],
        output_dir: @output_dir, config: config_for(bin)
      )

      expect(results.first.structured_valid_json).to eq(false)
      expect(results.first.structured_error).to include("invalid JSON")

      chapter_dir = File.join(@output_dir, "chapter_1")
      expect(File.read(File.join(chapter_dir, "structured.raw.txt"))).to eq("not json at all")
      expect(File.exist?(File.join(chapter_dir, "structured.json"))).to eq(false)
    end
  end

  it "continues past a per-call failure on one chapter and still runs the rest" do
    novel_dir = build_novel_dir(@root)
    write_korean_source(novel_dir, 1, "챕터 1 한국어")
    write_korean_source(novel_dir, 2, "챕터 2 한국어")

    Dir.mktmpdir do |bin_dir|
      call1_payload_1 = { passages: [ { passage_id: 1, anchor_quote: "챕터 1 한국어" } ], chapter_level_notes: { risks: [] } }
      call1_payload_2 = { passages: [ { passage_id: 1, anchor_quote: "챕터 2 한국어" } ], chapter_level_notes: { risks: [] } }
      bin = scripted_claude(bin_dir, {
        [ "챕터 1", "single_pass" ] => { is_error: true, subtype: "boom", result: "failed" },
        [ "챕터 1", "structured" ]  => { is_error: false, result: { intent: {}, literal_translation: "l", localized_translation: "loc" }.to_json },
        [ "챕터 1", "call1" ]       => { is_error: false, result: call1_payload_1.to_json },
        [ "챕터 2", "single_pass" ] => { is_error: false, result: "single pass two" },
        [ "챕터 2", "structured" ]  => { is_error: false, result: { intent: {}, literal_translation: "l2", localized_translation: "loc2" }.to_json },
        [ "챕터 2", "call1" ]       => { is_error: false, result: call1_payload_2.to_json }
      })

      results = described_class.call(
        novel_dir: novel_dir, chapter_numbers: [ 1, 2 ],
        output_dir: @output_dir, config: config_for(bin)
      )

      chapter1, chapter2 = results

      expect(chapter1.single_pass_error).to include("cli_failure")
      expect(chapter1.structured_valid_json).to eq(true)
      expect(chapter1.call1_valid_json).to eq(true)
      expect(File.exist?(File.join(@output_dir, "chapter_1", "single_pass.txt"))).to eq(false)

      expect(chapter2.single_pass_error).to be_nil
      expect(chapter2.structured_error).to be_nil
      expect(chapter2.call1_error).to be_nil
      expect(File.read(File.join(@output_dir, "chapter_2", "single_pass.txt"))).to eq("single pass two")
    end
  end

  describe "Call 1 segmentation validation" do
    def responses_with_call1(korean_text, call1_payload)
      {
        [ "챕터", "single_pass" ] => { is_error: false, result: "single pass" },
        [ "챕터", "structured" ]  => { is_error: false, result: { intent: {}, literal_translation: "l", localized_translation: "loc" }.to_json },
        [ "챕터", "call1" ]       => { is_error: false, result: call1_payload.to_json }
      }
    end

    it "passes when anchor_quote concatenation exactly reconstructs the source chapter with sequential passage_ids" do
      novel_dir = build_novel_dir(@root)
      write_korean_source(novel_dir, 1, "챕터 1 한국어")

      Dir.mktmpdir do |bin_dir|
        call1_payload = {
          passages: [
            { passage_id: 1, anchor_quote: "챕터 1 " },
            { passage_id: 2, anchor_quote: "한국어" }
          ],
          chapter_level_notes: { risks: [] }
        }
        bin = scripted_claude(bin_dir, responses_with_call1("챕터 1 한국어", call1_payload))

        results = described_class.call(
          novel_dir: novel_dir, chapter_numbers: [ 1 ],
          output_dir: @output_dir, config: config_for(bin)
        )

        expect(results.first.call1_valid_json).to eq(true)
        expect(results.first.call1_segmentation_error).to be_nil
      end
    end

    it "tolerates whitespace differences between anchor_quote concatenation and the source" do
      novel_dir = build_novel_dir(@root)
      write_korean_source(novel_dir, 1, "챕터 1  한국어")

      Dir.mktmpdir do |bin_dir|
        call1_payload = {
          passages: [
            { passage_id: 1, anchor_quote: "챕터 1" },
            { passage_id: 2, anchor_quote: "한국어" }
          ],
          chapter_level_notes: { risks: [] }
        }
        bin = scripted_claude(bin_dir, responses_with_call1("챕터 1  한국어", call1_payload))

        results = described_class.call(
          novel_dir: novel_dir, chapter_numbers: [ 1 ],
          output_dir: @output_dir, config: config_for(bin)
        )

        expect(results.first.call1_segmentation_error).to be_nil
      end
    end

    it "flags a gap/overlap when anchor_quote concatenation doesn't reconstruct the source chapter" do
      novel_dir = build_novel_dir(@root)
      write_korean_source(novel_dir, 1, "챕터 1 한국어")

      Dir.mktmpdir do |bin_dir|
        call1_payload = {
          passages: [
            { passage_id: 1, anchor_quote: "챕터 1" },
            { passage_id: 2, anchor_quote: "국어" } # dropped "한" — a gap
          ],
          chapter_level_notes: { risks: [] }
        }
        bin = scripted_claude(bin_dir, responses_with_call1("챕터 1 한국어", call1_payload))

        results = described_class.call(
          novel_dir: novel_dir, chapter_numbers: [ 1 ],
          output_dir: @output_dir, config: config_for(bin)
        )

        expect(results.first.call1_valid_json).to eq(true)
        expect(results.first.call1_segmentation_error).to include("gap or overlap")
      end
    end

    it "flags non-sequential/out-of-order passage_id values" do
      novel_dir = build_novel_dir(@root)
      write_korean_source(novel_dir, 1, "챕터 1 한국어")

      Dir.mktmpdir do |bin_dir|
        call1_payload = {
          passages: [
            { passage_id: 1, anchor_quote: "챕터 1 " },
            { passage_id: 3, anchor_quote: "한국어" } # should be 2
          ],
          chapter_level_notes: { risks: [] }
        }
        bin = scripted_claude(bin_dir, responses_with_call1("챕터 1 한국어", call1_payload))

        results = described_class.call(
          novel_dir: novel_dir, chapter_numbers: [ 1 ],
          output_dir: @output_dir, config: config_for(bin)
        )

        expect(results.first.call1_segmentation_error).to include("passage_id")
      end
    end

    it "flags a missing or empty passages array" do
      novel_dir = build_novel_dir(@root)
      write_korean_source(novel_dir, 1, "챕터 1 한국어")

      Dir.mktmpdir do |bin_dir|
        call1_payload = { passages: [], chapter_level_notes: { risks: [] } }
        bin = scripted_claude(bin_dir, responses_with_call1("챕터 1 한국어", call1_payload))

        results = described_class.call(
          novel_dir: novel_dir, chapter_numbers: [ 1 ],
          output_dir: @output_dir, config: config_for(bin)
        )

        expect(results.first.call1_segmentation_error).to include("passages")
      end
    end

    it "saves invalid call1 JSON raw instead of crashing the run" do
      novel_dir = build_novel_dir(@root)
      write_korean_source(novel_dir, 1, "챕터 1 한국어")

      Dir.mktmpdir do |bin_dir|
        bin = scripted_claude(bin_dir, {
          [ "챕터 1", "single_pass" ] => { is_error: false, result: "single pass one" },
          [ "챕터 1", "structured" ]  => { is_error: false, result: { intent: {}, literal_translation: "l", localized_translation: "loc" }.to_json },
          [ "챕터 1", "call1" ]       => { is_error: false, result: "not json at all" }
        })

        results = described_class.call(
          novel_dir: novel_dir, chapter_numbers: [ 1 ],
          output_dir: @output_dir, config: config_for(bin)
        )

        expect(results.first.call1_valid_json).to eq(false)
        expect(results.first.call1_error).to include("invalid JSON")
        expect(results.first.call1_segmentation_error).to be_nil

        chapter_dir = File.join(@output_dir, "chapter_1")
        expect(File.read(File.join(chapter_dir, "call1.raw.txt"))).to eq("not json at all")
        expect(File.exist?(File.join(chapter_dir, "call1.json"))).to eq(false)
      end
    end
  end
end
