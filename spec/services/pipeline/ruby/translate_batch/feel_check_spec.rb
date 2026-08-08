require "rails_helper"
require "json"

RSpec.describe Pipeline::Ruby::TranslateBatch::FeelCheck do
  def fake_claude(dir, body)
    path = File.join(dir, "claude")
    File.write(path, "#!#{RbConfig.ruby}\n#{body}")
    File.chmod(0o755, path)
    path
  end

  def config_for(claude_bin)
    TranslationConfig.from_env("PATH" => "", "CLAUDE_BIN" => claude_bin)
  end

  # Scripts a single canned response, regardless of input — FeelCheck makes
  # exactly one call, so there's nothing to disambiguate the way
  # translate_batch_spec/chapter_qa_spec's fakes have to.
  def scripted_claude(bin_dir, response)
    fake_claude(bin_dir, <<~RUBY)
      require "json"
      STDIN.read
      puts #{{ is_error: false, result: response.to_json }.to_json.inspect}
    RUBY
  end

  it "rewrites a segment the call flags as not reading naturally, leaves others untouched" do
    Dir.mktmpdir do |bin_dir|
      bin = scripted_claude(bin_dir, {
        segments: [ { segment_id: 1, reads_naturally: false, rewritten_text: "A much smoother sentence." } ]
      })

      result = described_class.call(english_text: "Original clunky sentence.", config: config_for(bin))

      expect(result.ok?).to eq(true)
      expect(result.text).to eq("A much smoother sentence.")
      expect(result.rewritten_count).to eq(1)
    end
  end

  it "keeps the original text unchanged when every segment already reads naturally" do
    Dir.mktmpdir do |bin_dir|
      bin = scripted_claude(bin_dir, { segments: [ { segment_id: 1, reads_naturally: true } ] })

      result = described_class.call(english_text: "Already natural sentence.", config: config_for(bin))

      expect(result.ok?).to eq(true)
      expect(result.text).to eq("Already natural sentence.")
      expect(result.rewritten_count).to eq(0)
    end
  end

  it "excludes scene-marker blocks from what's sent to the model but keeps them verbatim on reassembly" do
    Dir.mktmpdir do |bin_dir|
      # Raises if block 2 (the "***" scene marker) is ever sent as a segment
      # to review — only blocks 1 and 3 should appear.
      bin = fake_claude(bin_dir, <<~RUBY)
        require "json"
        # build_feel_check_user_message wraps the JSON array in a
        # "# Segments" markdown heading (same convention as every other
        # build_*_user_message in prompt_builder.rb) — extract just the
        # array before parsing.
        segments = JSON.parse(STDIN.read[/\\[.*\\]/m])
        raise "scene marker sent to model" if segments.any? { |s| s["text"] == "***" }
        raise "wrong segment ids: \#{segments.map { |s| s['segment_id'] }}" unless segments.map { |s| s["segment_id"] }.sort == [ 1, 3 ]
        response = { segments: [
          { segment_id: 1, reads_naturally: true },
          { segment_id: 3, reads_naturally: true }
        ] }
        puts({ is_error: false, result: response.to_json }.to_json)
      RUBY

      text = "First paragraph text here.\n\n***\n\nSecond paragraph text here."
      result = described_class.call(english_text: text, config: config_for(bin))

      expect(result.ok?).to eq(true)
      expect(result.text).to eq(text)
    end
  end

  it "sends the translation model, not the factcheck model" do
    Dir.mktmpdir do |bin_dir|
      bin = fake_claude(bin_dir, <<~RUBY)
        require "json"
        STDIN.read
        model = ARGV[ARGV.index("--model") + 1]
        raise "wrong model: \#{model}" unless model == "opus"
        puts({ is_error: false, result: { segments: [ { segment_id: 1, reads_naturally: true } ] }.to_json }.to_json)
      RUBY

      result = described_class.call(english_text: "Some sentence.", config: config_for(bin))
      expect(result.ok?).to eq(true)
    end
  end

  it "degrades to the original text without raising when the call itself fails" do
    Dir.mktmpdir do |bin_dir|
      bin = fake_claude(bin_dir, <<~RUBY)
        require "json"
        STDIN.read
        puts({ is_error: true, subtype: "boom", result: "boom" }.to_json)
      RUBY

      result = described_class.call(english_text: "Original sentence.", config: config_for(bin))

      expect(result.ok?).to eq(false)
      expect(result.error_category).to eq(:cli_failure)
      expect(result.text).to eq("Original sentence.")
      expect(result.rewritten_count).to eq(0)
    end
  end

  it "degrades to the original text when the response isn't valid JSON" do
    Dir.mktmpdir do |bin_dir|
      bin = fake_claude(bin_dir, <<~RUBY)
        require "json"
        STDIN.read
        puts({ is_error: false, result: "not json" }.to_json)
      RUBY

      result = described_class.call(english_text: "Original sentence.", config: config_for(bin))

      expect(result.ok?).to eq(false)
      expect(result.error_category).to eq(:unparseable_output)
      expect(result.text).to eq("Original sentence.")
    end
  end

  it "degrades to the original text when the response is missing a segment" do
    Dir.mktmpdir do |bin_dir|
      # Text long enough to produce more than one segment; response below
      # only covers one of them.
      long_text = (1..10).map { |n| "Paragraph #{n} with enough words to be its own block." }.join("\n\n")
      bin = scripted_claude(bin_dir, { segments: [ { segment_id: 1, reads_naturally: true } ] })

      result = described_class.call(english_text: long_text, config: config_for(bin))

      expect(result.ok?).to eq(false)
      expect(result.error_message).to include("coverage error")
      expect(result.text).to eq(long_text)
    end
  end

  it "returns the original text without making a call when there's nothing reviewable" do
    Dir.mktmpdir do |bin_dir|
      # A claude_bin that would raise if ever invoked — proves no call happens.
      bin = fake_claude(bin_dir, "raise 'should not be called'")

      result = described_class.call(english_text: "***", config: config_for(bin))

      expect(result.ok?).to eq(true)
      expect(result.text).to eq("***")
      expect(result.rewritten_count).to eq(0)
    end
  end
end
