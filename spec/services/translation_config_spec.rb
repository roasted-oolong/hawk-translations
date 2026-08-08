require "rails_helper"

RSpec.describe TranslationConfig do
  def fake_executable(dir, name)
    path = File.join(dir, name)
    File.write(path, "#!/bin/sh\nexit 0\n")
    File.chmod(0o755, path)
    path
  end

  def env(overrides = {})
    { "PATH" => "" }.merge(overrides)
  end

  describe "defaults" do
    it "defaults TRANSLATION_BACKEND, CALIBRATION_BACKEND, and FORMAT_BACKEND to claude_code" do
      Dir.mktmpdir do |dir|
        fake_executable(dir, "claude")
        config = described_class.from_env(env("PATH" => dir))

        expect(config.translation_backend).to eq("claude_code")
        expect(config.calibration_backend).to eq("claude_code")
        expect(config.format_backend).to eq("claude_code")
      end
    end

    it "defaults LLM_BASE_URL, LLM_API_KEY, TRANSLATION_MODEL, and the budget" do
      Dir.mktmpdir do |dir|
        fake_executable(dir, "claude")
        config = described_class.from_env(env("PATH" => dir))

        expect(config.llm_base_url).to eq("http://localhost:11434/v1")
        expect(config.llm_api_key).to eq("local")
        expect(config.translation_model).to eq("opus")
        expect(config.translation_max_budget_usd).to eq(3.00)
      end
    end

    it "defaults FACTCHECK_MODEL to sonnet, independently of TRANSLATION_MODEL" do
      Dir.mktmpdir do |dir|
        fake_executable(dir, "claude")
        config = described_class.from_env(env("PATH" => dir, "TRANSLATION_MODEL" => "opus"))

        expect(config.factcheck_model).to eq("sonnet")
      end
    end

    it "allows FACTCHECK_MODEL to be overridden independently of TRANSLATION_MODEL" do
      Dir.mktmpdir do |dir|
        fake_executable(dir, "claude")
        config = described_class.from_env(env("PATH" => dir, "FACTCHECK_MODEL" => "haiku"))

        expect(config.factcheck_model).to eq("haiku")
        expect(config.translation_model).to eq("opus")
      end
    end

    it "defaults BIBLE_ENTRY_SUGGESTION_MODEL to haiku, independently of TRANSLATION_MODEL" do
      Dir.mktmpdir do |dir|
        fake_executable(dir, "claude")
        config = described_class.from_env(env("PATH" => dir, "TRANSLATION_MODEL" => "opus"))

        expect(config.bible_entry_suggestion_model).to eq("haiku")
      end
    end

    it "allows BIBLE_ENTRY_SUGGESTION_MODEL to be overridden independently of TRANSLATION_MODEL" do
      Dir.mktmpdir do |dir|
        fake_executable(dir, "claude")
        config = described_class.from_env(env("PATH" => dir, "BIBLE_ENTRY_SUGGESTION_MODEL" => "sonnet"))

        expect(config.bible_entry_suggestion_model).to eq("sonnet")
        expect(config.translation_model).to eq("opus")
      end
    end
  end

  describe "TRANSLATION_BACKEND / CALIBRATION_BACKEND" do
    it "accepts local and claude_code independently of each other" do
      Dir.mktmpdir do |dir|
        fake_executable(dir, "claude")
        config = described_class.from_env(env(
          "PATH" => dir, "TRANSLATION_BACKEND" => "local", "CALIBRATION_BACKEND" => "claude_code"
        ))

        expect(config.translation_backend).to eq("local")
        expect(config.calibration_backend).to eq("claude_code")
      end
    end

    it "raises a clear error naming the offending var for an unrecognized TRANSLATION_BACKEND" do
      Dir.mktmpdir do |dir|
        fake_executable(dir, "claude")
        expect {
          described_class.from_env(env("PATH" => dir, "TRANSLATION_BACKEND" => "bogus"))
        }.to raise_error(TranslationConfig::ConfigError, /TRANSLATION_BACKEND/)
      end
    end

    it "raises a clear error naming the offending var for an unrecognized CALIBRATION_BACKEND" do
      Dir.mktmpdir do |dir|
        fake_executable(dir, "claude")
        expect {
          described_class.from_env(env("PATH" => dir, "CALIBRATION_BACKEND" => "bogus"))
        }.to raise_error(TranslationConfig::ConfigError, /CALIBRATION_BACKEND/)
      end
    end

    it "accepts FORMAT_BACKEND independently of TRANSLATION_BACKEND/CALIBRATION_BACKEND" do
      Dir.mktmpdir do |dir|
        fake_executable(dir, "claude")
        config = described_class.from_env(env("PATH" => dir, "FORMAT_BACKEND" => "local"))

        expect(config.format_backend).to eq("local")
        expect(config.translation_backend).to eq("claude_code")
      end
    end

    it "raises a clear error naming the offending var for an unrecognized FORMAT_BACKEND" do
      Dir.mktmpdir do |dir|
        fake_executable(dir, "claude")
        expect {
          described_class.from_env(env("PATH" => dir, "FORMAT_BACKEND" => "bogus"))
        }.to raise_error(TranslationConfig::ConfigError, /FORMAT_BACKEND/)
      end
    end
  end

  describe "TRANSLATION_MAX_BUDGET_USD" do
    it "parses a valid decimal string" do
      Dir.mktmpdir do |dir|
        fake_executable(dir, "claude")
        config = described_class.from_env(env("PATH" => dir, "TRANSLATION_MAX_BUDGET_USD" => "5.50"))

        expect(config.translation_max_budget_usd).to eq(5.50)
      end
    end

    it "raises for a non-numeric value" do
      Dir.mktmpdir do |dir|
        fake_executable(dir, "claude")
        expect {
          described_class.from_env(env("PATH" => dir, "TRANSLATION_MAX_BUDGET_USD" => "lots"))
        }.to raise_error(TranslationConfig::ConfigError, /TRANSLATION_MAX_BUDGET_USD/)
      end
    end

    it "raises for a negative value" do
      Dir.mktmpdir do |dir|
        fake_executable(dir, "claude")
        expect {
          described_class.from_env(env("PATH" => dir, "TRANSLATION_MAX_BUDGET_USD" => "-1"))
        }.to raise_error(TranslationConfig::ConfigError, /TRANSLATION_MAX_BUDGET_USD/)
      end
    end
  end

  describe "CLAUDE_BIN resolution" do
    it "resolves the default 'claude' name to an absolute path via PATH" do
      Dir.mktmpdir do |dir|
        expected = fake_executable(dir, "claude")
        config = described_class.from_env(env("PATH" => dir))

        expect(config.claude_bin).to eq(expected)
        expect(config.claude_bin).to start_with("/")
      end
    end

    it "raises a clear error when the default name isn't found on PATH" do
      Dir.mktmpdir do |dir|
        expect {
          described_class.from_env(env("PATH" => dir))
        }.to raise_error(TranslationConfig::ConfigError, /CLAUDE_BIN|claude/)
      end
    end

    it "accepts an absolute, executable CLAUDE_BIN as-is, with no further PATH search" do
      Dir.mktmpdir do |dir|
        custom = fake_executable(dir, "my-claude")
        config = described_class.from_env(env("PATH" => "", "CLAUDE_BIN" => custom))

        expect(config.claude_bin).to eq(custom)
      end
    end

    it "raises when CLAUDE_BIN is absolute but not executable" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "not-executable")
        File.write(path, "nope")

        expect {
          described_class.from_env(env("PATH" => "", "CLAUDE_BIN" => path))
        }.to raise_error(TranslationConfig::ConfigError, /CLAUDE_BIN/)
      end
    end

    it "raises when CLAUDE_BIN is set to a non-absolute path rather than silently searching PATH for it" do
      Dir.mktmpdir do |dir|
        fake_executable(dir, "sneaky-claude")

        expect {
          described_class.from_env(env("PATH" => dir, "CLAUDE_BIN" => "sneaky-claude"))
        }.to raise_error(TranslationConfig::ConfigError, /absolute/)
      end
    end
  end
end
