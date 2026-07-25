require "rails_helper"

RSpec.describe Pipeline::Ruby::TranslateBatch::BridgeConfig do
  describe ".mcp_config" do
    it "builds a command/args/env triple for bin/mcp_skill_bridge, resolved to absolute paths" do
      config = described_class.mcp_config(
        novel_directory_name: "idols-rewind",
        process_env: { "HOME" => "/fake/home" }
      )

      server = config.dig("mcpServers", "hawk_skills")
      expect(server["command"]).to eq(RbConfig.ruby)
      expect(server["command"]).to start_with("/")
      expect(server["args"]).to eq([ Rails.root.join("bin", "mcp_skill_bridge").to_s ])
      expect(server["args"].first).to start_with("/")
    end

    it "builds the bridge env as an explicit allowlist, excluding secrets not needed to boot Rails locally" do
      config = described_class.mcp_config(
        novel_directory_name: "idols-rewind",
        process_env: { "HOME" => "/fake/home", "DATABASE_URL" => "postgres://leak", "RAILS_MASTER_KEY" => "leak" }
      )

      env = config.dig("mcpServers", "hawk_skills", "env")
      expect(env).to eq(
        "RAILS_ENV"       => Rails.env.to_s,
        "BUNDLE_GEMFILE"  => Bundler.default_gemfile.to_s,
        "HAWK_BRIDGE_NOVEL_DIRECTORY_NAME" => "idols-rewind",
        "HOME"            => "/fake/home"
      )
    end

    it "omits HOME entirely rather than forwarding a nil value when the process env has none" do
      config = described_class.mcp_config(novel_directory_name: "idols-rewind", process_env: {})

      env = config.dig("mcpServers", "hawk_skills", "env")
      expect(env).not_to have_key("HOME")
    end
  end
end
