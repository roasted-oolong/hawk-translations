require "rails_helper"
require "json"

RSpec.describe Pipeline::Ruby::FormatKoreanChapter do
  def fake_claude(dir, body)
    path = File.join(dir, "claude")
    File.write(path, "#!#{RbConfig.ruby}\n#{body}")
    File.chmod(0o755, path)
    path
  end

  def config_for(overrides = {})
    TranslationConfig.from_env({ "PATH" => "", "CLAUDE_BIN" => "/bin/true" }.merge(overrides))
  end

  describe "claude_code backend (the default, matching clean_chapter.py's current default)" do
    it "builds the formatter prompt, calls claude, and returns the parsed chapter text" do
      Dir.mktmpdir do |dir|
        bin = fake_claude(dir, <<~RUBY)
          require "json"
          stdin = STDIN.read
          raise "raw text missing from prompt" unless stdin.include?("raw korean text")
          puts({ is_error: false, result: "=== CHAPTER 1 ===\\ncleaned text\\n=== END CHAPTER 1 ===" }.to_json)
        RUBY

        result = described_class.call("raw korean text", config: config_for("CLAUDE_BIN" => bin))

        expect(result.success?).to eq(true)
        expect(result.output).to eq("cleaned text")
      end
    end

    it "returns a failure Result when the claude call fails, without raising" do
      Dir.mktmpdir do |dir|
        bin = fake_claude(dir, <<~RUBY)
          require "json"
          STDIN.read
          puts({ is_error: true, subtype: "boom", result: "failed" }.to_json)
        RUBY

        result = described_class.call("raw text", config: config_for("CLAUDE_BIN" => bin))

        expect(result.success?).to eq(false)
        expect(result.error_message).to include("cli_failure")
      end
    end

    it "returns a failure Result when the response can't be parsed for chapter 1" do
      Dir.mktmpdir do |dir|
        bin = fake_claude(dir, <<~RUBY)
          require "json"
          STDIN.read
          puts({ is_error: false, result: "no delimiters here" }.to_json)
        RUBY

        result = described_class.call("raw text", config: config_for("CLAUDE_BIN" => bin))

        expect(result.success?).to eq(false)
        expect(result.error_message).to include("failed to parse")
      end
    end
  end

  describe "local backend (FORMAT_BACKEND=local)" do
    it "calls the local LLM endpoint instead of claude" do
      stub_request(:post, "http://localhost:11434/v1/chat/completions")
        .to_return(status: 200, body: {
          choices: [ { message: { content: "=== CHAPTER 1 ===\ncleaned locally\n=== END CHAPTER 1 ===" } } ]
        }.to_json)

      result = described_class.call("raw text", config: config_for("FORMAT_BACKEND" => "local"))

      expect(result.success?).to eq(true)
      expect(result.output).to eq("cleaned locally")
    end

    it "returns a failure Result when the local endpoint is unreachable" do
      stub_request(:post, "http://localhost:11434/v1/chat/completions").to_raise(Errno::ECONNREFUSED)

      result = described_class.call("raw text", config: config_for("FORMAT_BACKEND" => "local"))

      expect(result.success?).to eq(false)
      expect(result.error_message).to include("connection_failed")
    end
  end

  describe "empty input" do
    it "returns a failure Result without calling any backend" do
      result = described_class.call("   ", config: config_for)

      expect(result.success?).to eq(false)
      expect(result.error_message).to eq("empty input")
    end
  end
end
