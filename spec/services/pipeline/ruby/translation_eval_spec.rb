require "rails_helper"
require "json"

# Offline-only tool (docs/ROADMAP.md's translation quality pipeline note):
# runs both the current single-pass prompt and the candidate structured
# (intent/literal/localized) prompt over the same chapters, side by side, so
# a human can judge whether the structured approach is worth its extra JSON
# fragility before any multi-call pipeline gets built. Not wired into
# translate_batch or any TranslationJob — takes a plain directory, not a
# Novel record.
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

  # Both calls for one chapter share the same stdin (the Korean source), so
  # responses are keyed on [marker, variant] and the variant is read back
  # off the --system-prompt-file content itself (structured prompts contain
  # the JSON-object instruction the single-pass prompt doesn't).
  def scripted_claude(bin_dir, responses_by_marker_and_variant)
    fake_claude(bin_dir, <<~RUBY)
      require "json"
      stdin = STDIN.read.force_encoding("UTF-8")
      prompt_path = ARGV[ARGV.index("--system-prompt-file") + 1]
      variant = File.read(prompt_path).include?("Respond with a single JSON object") ? "structured" : "single_pass"
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
      bin = scripted_claude(bin_dir, {
        [ "챕터 1", "single_pass" ] => { is_error: false, result: "single pass one" },
        [ "챕터 1", "structured" ]  => { is_error: false, result: structured_payload.to_json }
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

      chapter_dir = File.join(@output_dir, "chapter_1")
      expect(File.read(File.join(chapter_dir, "single_pass.txt"))).to eq("single pass one")
      expect(JSON.parse(File.read(File.join(chapter_dir, "structured.json")))["localized_translation"]).to eq("localized one")
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
      bin = scripted_claude(bin_dir, {
        [ "챕터 1", "single_pass" ] => { is_error: false, result: "single pass one" },
        [ "챕터 1", "structured" ]  => { is_error: false, result: "not json at all" }
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
      bin = scripted_claude(bin_dir, {
        [ "챕터 1", "single_pass" ] => { is_error: true, subtype: "boom", result: "failed" },
        [ "챕터 1", "structured" ]  => { is_error: false, result: { intent: {}, literal_translation: "l", localized_translation: "loc" }.to_json },
        [ "챕터 2", "single_pass" ] => { is_error: false, result: "single pass two" },
        [ "챕터 2", "structured" ]  => { is_error: false, result: { intent: {}, literal_translation: "l2", localized_translation: "loc2" }.to_json }
      })

      results = described_class.call(
        novel_dir: novel_dir, chapter_numbers: [ 1, 2 ],
        output_dir: @output_dir, config: config_for(bin)
      )

      chapter1, chapter2 = results

      expect(chapter1.single_pass_error).to include("cli_failure")
      expect(chapter1.structured_valid_json).to eq(true)
      expect(File.exist?(File.join(@output_dir, "chapter_1", "single_pass.txt"))).to eq(false)

      expect(chapter2.single_pass_error).to be_nil
      expect(chapter2.structured_error).to be_nil
      expect(File.read(File.join(@output_dir, "chapter_2", "single_pass.txt"))).to eq("single pass two")
    end
  end
end
