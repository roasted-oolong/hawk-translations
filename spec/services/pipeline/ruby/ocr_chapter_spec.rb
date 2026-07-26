require "rails_helper"
require "json"

RSpec.describe Pipeline::Ruby::OcrChapter do
  def fake_claude(dir, body)
    path = File.join(dir, "claude")
    File.write(path, "#!#{RbConfig.ruby}\n#{body}")
    File.chmod(0o755, path)
    path
  end

  def fake_image(dir, name)
    path = File.join(dir, name)
    File.binwrite(path, "fake bytes for #{name}")
    path
  end

  def config_for(claude_bin)
    TranslationConfig.from_env("PATH" => "", "CLAUDE_BIN" => claude_bin)
  end

  it "transcribes each image in argv order and joins the results" do
    Dir.mktmpdir do |dir|
      bin = fake_claude(dir, <<~RUBY)
        require "json"
        require "base64"
        stdin = JSON.parse(STDIN.read)
        encoded = stdin.dig("message", "content", 0, "source", "data")
        decoded = Base64.strict_decode64(encoded)
        puts({ type: "result", is_error: false, result: "transcribed: \#{decoded}" }.to_json)
      RUBY

      page1 = fake_image(dir, "page1.jpg")
      page2 = fake_image(dir, "page2.jpg")

      result = described_class.call([ page1, page2 ], config: config_for(bin), model: "m", max_budget_usd: "0.50")

      expect(result.success?).to eq(true)
      expect(result.output).to eq(
        "transcribed: fake bytes for page1.jpg\n\ntranscribed: fake bytes for page2.jpg"
      )
    end
  end

  it "returns a single failure Result on the first per-image error, without transcribing later pages" do
    Dir.mktmpdir do |dir|
      call_count_file = File.join(dir, "calls")
      File.write(call_count_file, "0")

      bin = fake_claude(dir, <<~RUBY)
        require "json"
        STDIN.read
        count = File.read(#{call_count_file.inspect}).to_i + 1
        File.write(#{call_count_file.inspect}, count.to_s)
        puts({ type: "result", is_error: true, subtype: "boom", result: "failed" }.to_json)
      RUBY

      page1 = fake_image(dir, "page1.jpg")
      page2 = fake_image(dir, "page2.jpg")

      result = described_class.call([ page1, page2 ], config: config_for(bin), model: "m", max_budget_usd: "0.50")

      expect(result.success?).to eq(false)
      expect(result.error_message).to include("page1.jpg")
      expect(result.error_message).to include("cli_failure")
      expect(File.read(call_count_file)).to eq("1")
    end
  end

  it "returns a failure Result when no image paths are given" do
    result = described_class.call([], config: config_for("/bin/true"))

    expect(result.success?).to eq(false)
    expect(result.error_message).to include("no image paths")
  end
end
