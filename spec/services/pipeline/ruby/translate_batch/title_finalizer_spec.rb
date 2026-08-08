require "rails_helper"

RSpec.describe Pipeline::Ruby::TranslateBatch::TitleFinalizer do
  def fake_claude(dir, body)
    path = File.join(dir, "claude")
    File.write(path, "#!#{RbConfig.ruby}\n#{body}")
    File.chmod(0o755, path)
    path
  end

  def config_for(claude_bin)
    TranslationConfig.from_env("PATH" => "", "CLAUDE_BIN" => claude_bin)
  end

  # Scripts a single canned response, regardless of input — TitleFinalizer
  # makes exactly one call, same reasoning as FeelCheck's own scripted_claude.
  def scripted_claude(bin_dir, response)
    fake_claude(bin_dir, <<~RUBY)
      require "json"
      STDIN.read
      puts #{{ is_error: false, result: response }.to_json.inspect}
    RUBY
  end

  it "replaces the draft title with the finalized one, leaves the body untouched" do
    Dir.mktmpdir do |bin_dir|
      bin = scripted_claude(bin_dir, "Final Title")

      result = described_class.call(
        korean_text:  "한국어 제목\n\n한국어 본문 텍스트.",
        english_text: "Draft Title\n\nEnglish body text.",
        config:       config_for(bin)
      )

      expect(result.ok?).to eq(true)
      expect(result.text).to eq("Final Title\n\nEnglish body text.")
    end
  end

  it "returns the English text unchanged, without making a call, when the Korean has no separable title line" do
    Dir.mktmpdir do |bin_dir|
      bin = fake_claude(bin_dir, "raise 'should not be called'")

      result = described_class.call(
        korean_text:  "한 줄짜리 한국어 텍스트, 빈 줄이 없음.",
        english_text: "Draft Title\n\nEnglish body text.",
        config:       config_for(bin)
      )

      expect(result.ok?).to eq(true)
      expect(result.text).to eq("Draft Title\n\nEnglish body text.")
    end
  end

  it "returns the English text unchanged, without making a call, when the English has no separable title line" do
    Dir.mktmpdir do |bin_dir|
      bin = fake_claude(bin_dir, "raise 'should not be called'")

      result = described_class.call(
        korean_text:  "한국어 제목\n\n한국어 본문 텍스트.",
        english_text: "One-line English text, no blank line at all.",
        config:       config_for(bin)
      )

      expect(result.ok?).to eq(true)
      expect(result.text).to eq("One-line English text, no blank line at all.")
    end
  end

  it "degrades to the draft title without raising when the call itself fails" do
    Dir.mktmpdir do |bin_dir|
      bin = fake_claude(bin_dir, <<~RUBY)
        require "json"
        STDIN.read
        puts({ is_error: true, subtype: "boom", result: "boom" }.to_json)
      RUBY

      result = described_class.call(
        korean_text:  "한국어 제목\n\n한국어 본문 텍스트.",
        english_text: "Draft Title\n\nEnglish body text.",
        config:       config_for(bin)
      )

      expect(result.ok?).to eq(false)
      expect(result.error_category).to eq(:cli_failure)
      expect(result.text).to eq("Draft Title\n\nEnglish body text.")
    end
  end

  it "degrades to the draft title when the model returns an empty title" do
    Dir.mktmpdir do |bin_dir|
      bin = scripted_claude(bin_dir, "   ")

      result = described_class.call(
        korean_text:  "한국어 제목\n\n한국어 본문 텍스트.",
        english_text: "Draft Title\n\nEnglish body text.",
        config:       config_for(bin)
      )

      expect(result.ok?).to eq(false)
      expect(result.error_category).to eq(:empty_title)
      expect(result.text).to eq("Draft Title\n\nEnglish body text.")
    end
  end

  it "sends the translation model, not the factcheck model" do
    Dir.mktmpdir do |bin_dir|
      bin = fake_claude(bin_dir, <<~RUBY)
        require "json"
        STDIN.read
        model = ARGV[ARGV.index("--model") + 1]
        raise "wrong model: \#{model}" unless model == "opus"
        puts({ is_error: false, result: "Final Title" }.to_json)
      RUBY

      result = described_class.call(
        korean_text:  "한국어 제목\n\n한국어 본문 텍스트.",
        english_text: "Draft Title\n\nEnglish body text.",
        config:       config_for(bin)
      )

      expect(result.ok?).to eq(true)
    end
  end
end
