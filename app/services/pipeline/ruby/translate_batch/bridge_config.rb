# ---------------------------------------------------------------------------
# Pipeline::Ruby::TranslateBatch::BridgeConfig
#
# Builds the `--mcp-config` payload Pipeline::ClaudeCode passes through to
# the `claude` CLI so it spawns bin/mcp_skill_bridge (R3) as an MCP server
# for one translate_batch call. Per R4's design in
# docs/RAILS_REFACTOR_PLAN.md: simpler than Python's _mcp_config_json (no
# skill-spec serialization — R3's bridge hardcodes its one registered tool
# class), but the interpreter/script must be resolved to absolute paths and
# the bridge's env is a from-{} allowlist derived independently from R1's
# claude-CLI allowlist (different trust boundary — the bridge is this app's
# own code and needs to boot Rails, not stay isolated from it).
#
# RbConfig.ruby resolves the interpreter this Rails process is itself
# running under — already past any version-manager shim (verified on this
# box: `which ruby` is an rbenv shim at ~/.rbenv/shims/ruby, but
# RbConfig.ruby and `rbenv which ruby` agree on the real interpreter at
# ~/.rbenv/versions/3.4.2/bin/ruby). Using RbConfig.ruby is simpler than the
# design's illustrative `rbenv which ruby` shell-out and needs no subprocess
# of its own: whatever interpreter is already running this code is
# guaranteed to be the real one, not a shim.
#
# Smoke-tested 2026-07-25 per the design's own flagged open question: a real
# `claude -p` call with a real --mcp-config pointing at this exact
# command/args/env shape (interpreter + bridge script as absolute paths,
# env limited to RAILS_ENV/HOME/BUNDLE_GEMFILE/HAWK_BRIDGE_NOVEL_DIRECTORY_NAME)
# successfully reached Postgres via the bridge and returned real
# BibleSearchService results — confirming this allowlist is sufficient
# without needing to reverse-engineer claude's internal env-merge behavior.
# ---------------------------------------------------------------------------
module Pipeline
  module Ruby
    class TranslateBatch
      module BridgeConfig
        SERVER_NAME = "hawk_skills"

        def self.mcp_config(novel_directory_name:, process_env: ENV)
          {
            "mcpServers" => {
              SERVER_NAME => {
                "command" => RbConfig.ruby,
                "args"    => [ Rails.root.join("bin", "mcp_skill_bridge").to_s ],
                "env"     => allowlisted_env(novel_directory_name, process_env)
              }
            }
          }
        end

        # Built additively from {} — never a deny-list carved out of ENV.to_h.
        # DATABASE_URL, HAWK_DATABASE_PASSWORD, RAILS_MASTER_KEY, and
        # ANTHROPIC_API_KEY are deliberately absent: none are needed to boot
        # Rails and reach Postgres on the current local/dev target (peer-auth
        # Postgres, config/master.key already on disk). Required cleanup,
        # not solved here, the moment a real `kamal deploy` happens.
        def self.allowlisted_env(novel_directory_name, process_env)
          env = {
            "RAILS_ENV"       => Rails.env.to_s,
            "BUNDLE_GEMFILE"  => Bundler.default_gemfile.to_s,
            "HAWK_BRIDGE_NOVEL_DIRECTORY_NAME" => novel_directory_name
          }
          env["HOME"] = process_env["HOME"] if process_env["HOME"]
          env
        end
        private_class_method :allowlisted_env
      end
    end
  end
end
