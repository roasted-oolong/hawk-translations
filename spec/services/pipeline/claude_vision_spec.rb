require "rails_helper"
require "json"
require "base64"

RSpec.describe Pipeline::ClaudeVision do
  # Same fake-binary technique as spec/services/pipeline/claude_code_spec.rb,
  # emitting real --output-format stream-json lines (one JSON object per
  # line, final type: "result" line authoritative) instead of a single blob.
  def fake_claude(dir, body)
    path = File.join(dir, "claude")
    File.write(path, "#!#{RbConfig.ruby}\n#{body}")
    File.chmod(0o755, path)
    path
  end

  def fake_image(dir, name: "page1.jpg", content: "fake jpeg bytes")
    path = File.join(dir, name)
    File.binwrite(path, content)
    path
  end

  # A method, not a top-level constant: RSpec.describe blocks don't scope
  # bare constant assignments (they leak onto Object), so a same-named
  # ECHO_SCRIPT constant here previously clobbered claude_code_spec.rb's own
  # ECHO_SCRIPT whenever both files loaded in the same run — order-dependent
  # test pollution caught by a full-suite run, not this file in isolation.
  def echo_script
    <<~RUBY
      require "json"
      stdin_content = STDIN.read
      puts({ type: "system", subtype: "init" }.to_json)
      puts({
        type: "result",
        is_error: false,
        result: "transcribed text",
        argv: ARGV,
        stdin: stdin_content
      }.to_json)
    RUBY
  end

  it "invokes the CLI via argv with stream-json input/output and the image content block" do
    Dir.mktmpdir do |dir|
      bin   = fake_claude(dir, echo_script)
      image = fake_image(dir)

      result = described_class.call(image_path: image, claude_bin: bin, model: "claude-sonnet-5",
                                     max_budget_usd: "0.50", process_env: { "HOME" => "/fake/home" })

      expect(result.success?).to eq(true)
      expect(result.output).to eq("transcribed text")
    end
  end

  it "sends argv flags matching the documented shape" do
    Dir.mktmpdir do |dir|
      image = fake_image(dir)

      stdout_capture = Dir.mktmpdir
      script = <<~RUBY
        require "json"
        stdin_content = STDIN.read
        File.write(#{File.join(stdout_capture, "argv.json").inspect}, ARGV.to_json)
        File.write(#{File.join(stdout_capture, "stdin.json").inspect}, stdin_content)
        puts({ type: "result", is_error: false, result: "ok" }.to_json)
      RUBY
      bin = fake_claude(dir, script)

      described_class.call(image_path: image, claude_bin: bin, model: "claude-sonnet-5", max_budget_usd: "0.50")

      argv = JSON.parse(File.read(File.join(stdout_capture, "argv.json")))
      expect(argv).to eq(
        [ "-p",
          "--system-prompt", described_class::SYSTEM_PROMPT,
          "--input-format", "stream-json",
          "--output-format", "stream-json",
          "--verbose",
          "--model", "claude-sonnet-5",
          "--tools", "",
          "--permission-mode", "bypassPermissions",
          "--no-session-persistence",
          "--max-budget-usd", "0.50" ]
      )

      stdin_payload = JSON.parse(File.read(File.join(stdout_capture, "stdin.json")))
      expect(stdin_payload["type"]).to eq("user")
      content = stdin_payload["message"]["content"]
      expect(content[0]["type"]).to eq("image")
      expect(content[0]["source"]["media_type"]).to eq("image/jpeg")
      expect(Base64.strict_decode64(content[0]["source"]["data"])).to eq("fake jpeg bytes")
      expect(content[1]).to eq({ "type" => "text", "text" => "Transcribe this page." })
    ensure
      FileUtils.remove_entry(stdout_capture) if stdout_capture
    end
  end

  describe "a result event reporting is_error" do
    it "categorizes as :cli_failure" do
      Dir.mktmpdir do |dir|
        bin   = fake_claude(dir, <<~RUBY)
          require "json"
          STDIN.read
          puts({ type: "result", is_error: true, subtype: "error_max_turns", result: "gave up" }.to_json)
        RUBY
        image = fake_image(dir)

        result = described_class.call(image_path: image, claude_bin: bin, model: "m", max_budget_usd: "0.50")

        expect(result.success?).to eq(false)
        expect(result.error_category).to eq(:cli_failure)
        expect(result.error_message).to include("error_max_turns")
      end
    end
  end

  describe "no result event in the stream" do
    it "categorizes as :cli_failure" do
      Dir.mktmpdir do |dir|
        bin   = fake_claude(dir, <<~RUBY)
          require "json"
          STDIN.read
          puts({ type: "system", subtype: "init" }.to_json)
        RUBY
        image = fake_image(dir)

        result = described_class.call(image_path: image, claude_bin: bin, model: "m", max_budget_usd: "0.50")

        expect(result.success?).to eq(false)
        expect(result.error_category).to eq(:cli_failure)
        expect(result.error_message).to include("no result event")
      end
    end
  end

  describe "a nonzero exit code" do
    it "categorizes as :cli_failure" do
      Dir.mktmpdir do |dir|
        bin   = fake_claude(dir, <<~RUBY)
          STDIN.read
          exit 1
        RUBY
        image = fake_image(dir)

        result = described_class.call(image_path: image, claude_bin: bin, model: "m", max_budget_usd: "0.50")

        expect(result.success?).to eq(false)
        expect(result.error_category).to eq(:cli_failure)
      end
    end
  end

  describe "timeout" do
    it "categorizes a hung CLI as :timeout" do
      Dir.mktmpdir do |dir|
        bin   = fake_claude(dir, <<~RUBY)
          STDIN.read
          sleep 5
        RUBY
        image = fake_image(dir)

        result = described_class.call(image_path: image, claude_bin: bin, model: "m",
                                       max_budget_usd: "0.50", timeout: 0.3)

        expect(result.success?).to eq(false)
        expect(result.error_category).to eq(:timeout)
      end
    end
  end

  describe "killed by signal" do
    it "categorizes an exit_code of 137 (SIGKILL) as :killed" do
      Dir.mktmpdir do |dir|
        bin   = fake_claude(dir, <<~RUBY)
          STDIN.read
          Process.kill("KILL", Process.pid)
          sleep
        RUBY
        image = fake_image(dir)

        result = described_class.call(image_path: image, claude_bin: bin, model: "m",
                                       max_budget_usd: "0.50", timeout: 5)

        expect(result.success?).to eq(false)
        expect(result.error_category).to eq(:killed)
      end
    end
  end

  describe "binary not found" do
    it "categorizes as :binary_not_found instead of raising" do
      Dir.mktmpdir do |dir|
        image = fake_image(dir)

        result = described_class.call(image_path: image, claude_bin: File.join(dir, "nonexistent"),
                                       model: "m", max_budget_usd: "0.50")

        expect(result.success?).to eq(false)
        expect(result.error_category).to eq(:binary_not_found)
      end
    end
  end
end
