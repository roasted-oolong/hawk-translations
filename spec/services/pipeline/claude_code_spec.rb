require "rails_helper"
require "json"

RSpec.describe Pipeline::ClaudeCode do
  # Writes an executable Ruby script standing in for the real `claude` CLI.
  # It reads stdin (the user message), reads whatever file
  # --system-prompt-file points at, and echoes both back plus the raw ARGV
  # and a slice of its own ENV in a JSON blob on stdout — so specs can
  # assert on exactly what this class fed the subprocess without needing
  # the real binary.
  def fake_claude(dir, body)
    path = File.join(dir, "claude")
    # Shebang points at the running interpreter's absolute path rather than
    # "/usr/bin/env ruby" — the child's env allowlist deliberately excludes
    # PATH (see Pipeline::ClaudeCode), so an env-mediated shebang wouldn't
    # resolve.
    File.write(path, "#!#{RbConfig.ruby}\n#{body}")
    File.chmod(0o755, path)
    path
  end

  ECHO_SCRIPT = <<~RUBY
    require "json"
    stdin_content = STDIN.read
    prompt_file   = ARGV[ARGV.index("--system-prompt-file") + 1]
    puts({
      is_error: false,
      result: "ok",
      argv: ARGV,
      stdin: stdin_content,
      system_prompt_file_content: File.read(prompt_file),
      env_seen: { "HOME" => ENV["HOME"], "PATH" => ENV["PATH"],
                   "MCP_CONNECTION_NONBLOCKING" => ENV["MCP_CONNECTION_NONBLOCKING"] }
    }.to_json)
  RUBY

  def config_for(claude_bin, overrides = {})
    env = { "PATH" => "", "CLAUDE_BIN" => claude_bin }.merge(overrides)
    TranslationConfig.from_env(env)
  end

  describe "argv shape and env allowlist" do
    it "invokes the CLI via argv array with the documented flags, stdin, and env allowlist" do
      Dir.mktmpdir do |dir|
        bin = fake_claude(dir, ECHO_SCRIPT)
        config = config_for(bin, "TRANSLATION_MODEL" => "opus", "TRANSLATION_MAX_BUDGET_USD" => "3.00")

        result = described_class.call(
          system_prompt: "be a translator",
          user_message:  "translate this",
          config:        config,
          process_env:   { "HOME" => "/fake/home", "PATH" => "/should/not/be/forwarded" }
        )

        expect(result.success?).to eq(true)
        argv = result.raw["argv"]

        expect(argv[0]).to eq("-p")
        expect(argv[1]).to eq("--system-prompt-file")
        expect(argv[3..]).to eq(
          [ "--output-format", "json",
            "--model", "opus",
            "--tools", "",
            "--permission-mode", "bypassPermissions",
            "--no-session-persistence",
            "--max-budget-usd", "3.0" ]
        )

        expect(result.raw["system_prompt_file_content"]).to eq("be a translator")
        expect(result.raw["stdin"]).to eq("translate this")

        env_seen = result.raw["env_seen"]
        expect(env_seen["HOME"]).to eq("/fake/home")
        expect(env_seen["MCP_CONNECTION_NONBLOCKING"]).to eq("false")
        expect(env_seen["PATH"]).to be_nil
      end
    end

    it "uses the model: override instead of config.translation_model when given" do
      Dir.mktmpdir do |dir|
        bin = fake_claude(dir, ECHO_SCRIPT)
        config = config_for(bin, "TRANSLATION_MODEL" => "opus")

        result = described_class.call(
          system_prompt: "be a translator", user_message: "translate this",
          config: config, model: "sonnet"
        )

        argv = result.raw["argv"]
        expect(argv[argv.index("--model") + 1]).to eq("sonnet")
      end
    end

    it "falls back to config.translation_model when model: is not given" do
      Dir.mktmpdir do |dir|
        bin = fake_claude(dir, ECHO_SCRIPT)
        config = config_for(bin, "TRANSLATION_MODEL" => "opus")

        result = described_class.call(
          system_prompt: "be a translator", user_message: "translate this", config: config
        )

        argv = result.raw["argv"]
        expect(argv[argv.index("--model") + 1]).to eq("opus")
      end
    end

    it "deletes the system-prompt temp file after the call" do
      Dir.mktmpdir do |dir|
        bin = fake_claude(dir, ECHO_SCRIPT)
        config = config_for(bin)

        result = described_class.call(system_prompt: "x", user_message: "y", config: config)

        prompt_path = result.raw["argv"][result.raw["argv"].index("--system-prompt-file") + 1]
        expect(File.exist?(prompt_path)).to eq(false)
      end
    end

    it "inserts --strict-mcp-config/--mcp-config only when mcp_config is given" do
      Dir.mktmpdir do |dir|
        bin = fake_claude(dir, ECHO_SCRIPT)
        config = config_for(bin)

        result = described_class.call(
          system_prompt: "x", user_message: "y", config: config,
          mcp_config: { "mcpServers" => { "hawk_skills" => { "command" => "/bin/true" } } }
        )

        argv = result.raw["argv"]
        idx = argv.index("--strict-mcp-config")
        expect(idx).not_to be_nil
        expect(argv[idx + 1]).to eq("--mcp-config")
        expect(JSON.parse(argv[idx + 2])).to eq({ "mcpServers" => { "hawk_skills" => { "command" => "/bin/true" } } })
      end
    end
  end

  describe "a successful call" do
    it "returns a Result with success? true and the parsed output string" do
      Dir.mktmpdir do |dir|
        bin = fake_claude(dir, <<~RUBY)
          require "json"
          STDIN.read
          puts({ is_error: false, result: "translated text" }.to_json)
        RUBY
        config = config_for(bin)

        result = described_class.call(system_prompt: "s", user_message: "u", config: config)

        expect(result.success?).to eq(true)
        expect(result.output).to eq("translated text")
        expect(result.error_category).to be_nil
      end
    end
  end

  describe "a CLI-reported failure (nonzero exit or is_error)" do
    it "categorizes is_error: true as :cli_failure" do
      Dir.mktmpdir do |dir|
        bin = fake_claude(dir, <<~RUBY)
          require "json"
          STDIN.read
          puts({ is_error: true, subtype: "error_max_turns", result: "gave up" }.to_json)
        RUBY
        config = config_for(bin)

        result = described_class.call(system_prompt: "s", user_message: "u", config: config)

        expect(result.success?).to eq(false)
        expect(result.error_category).to eq(:cli_failure)
        expect(result.error_message).to include("error_max_turns")
      end
    end

    it "categorizes a nonzero exit code as :cli_failure even if is_error is absent" do
      Dir.mktmpdir do |dir|
        bin = fake_claude(dir, <<~RUBY)
          require "json"
          STDIN.read
          puts({ result: "boom" }.to_json)
          exit 1
        RUBY
        config = config_for(bin)

        result = described_class.call(system_prompt: "s", user_message: "u", config: config)

        expect(result.success?).to eq(false)
        expect(result.error_category).to eq(:cli_failure)
      end
    end
  end

  describe "unparseable output" do
    it "categorizes non-JSON stdout as :unparseable_output" do
      Dir.mktmpdir do |dir|
        bin = fake_claude(dir, <<~RUBY)
          STDIN.read
          puts "not json at all"
        RUBY
        config = config_for(bin)

        result = described_class.call(system_prompt: "s", user_message: "u", config: config)

        expect(result.success?).to eq(false)
        expect(result.error_category).to eq(:unparseable_output)
      end
    end
  end

  describe "timeout" do
    it "categorizes a hung CLI as :timeout" do
      Dir.mktmpdir do |dir|
        bin = fake_claude(dir, <<~RUBY)
          STDIN.read
          sleep 5
        RUBY
        config = config_for(bin)

        result = described_class.call(system_prompt: "s", user_message: "u", config: config, timeout: 0.3)

        expect(result.success?).to eq(false)
        expect(result.error_category).to eq(:timeout)
      end
    end
  end

  describe "killed by signal" do
    it "categorizes an exit_code of 137 (SIGKILL) as :killed" do
      Dir.mktmpdir do |dir|
        bin = fake_claude(dir, <<~RUBY)
          STDIN.read
          Process.kill("KILL", Process.pid)
          sleep
        RUBY
        config = config_for(bin)

        result = described_class.call(system_prompt: "s", user_message: "u", config: config, timeout: 5)

        expect(result.success?).to eq(false)
        expect(result.error_category).to eq(:killed)
      end
    end
  end

  describe "binary vanishing between config resolution and spawn" do
    it "categorizes as :binary_not_found instead of raising" do
      Dir.mktmpdir do |dir|
        bin = fake_claude(dir, ECHO_SCRIPT)
        config = config_for(bin)
        File.delete(bin)

        result = described_class.call(system_prompt: "s", user_message: "u", config: config)

        expect(result.success?).to eq(false)
        expect(result.error_category).to eq(:binary_not_found)
      end
    end
  end
end
