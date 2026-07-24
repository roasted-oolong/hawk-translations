# ---------------------------------------------------------------------------
# Pipeline::Mcp::BibleLookupTool
#
# Thin MCP::Tool adapter wrapping R2's Pipeline::Skills::BibleLookup, per
# R3 in docs/RAILS_REFACTOR_PLAN.md. Exists solely because the mcp gem
# models tools as class-level objects (self.call, one server_context per
# bridge-process lifetime — see lib/mcp/tool.rb, lib/mcp/server.rb), while
# this app's skill classes stay instance-based on purpose: consistency with
# R1's "local" tool loop (which calls skill instances directly, no adapter
# involved) and easier testing (a skill instance can be built and exercised
# without any MCP machinery at all, as R2 already established).
# Pipeline::Skills::BibleLookup does not, and should not, inherit from
# MCP::Tool.
#
# Carries no business logic — exactly four things: read server_context,
# construct a skill instance, delegate to #execute, wrap the result. No
# formatting, no argument validation (the gem's own dispatch layer already
# validates against input_schema before this ever runs), no error-message
# shaping. No skill instance is memoized across calls — the bridge
# process's whole lifecycle is one translation call, so a fresh
# Pipeline::Skills::BibleLookup built inside #call and discarded when it
# returns is the entire point, not an inefficiency to optimize away.
# ---------------------------------------------------------------------------
module Pipeline
  module Mcp
    class BibleLookupTool < MCP::Tool
      tool_name "bible_lookup"

      description(
        "Look up entries in the translation bible to check established " \
        "character names, locations, terminology, cultural phrases, and " \
        "story context. Use this when you encounter a name, term, or " \
        "reference in the source text and want to check how it has been " \
        "translated or documented."
      )

      input_schema(
        type: "object",
        properties: {
          query: {
            type: "string",
            description: "The name, term, or phrase to look up. Can be in English or Korean."
          },
          categories: {
            type: "array",
            items: { type: "string", enum: Pipeline::Skills::BibleLookup::CATEGORY_LABELS.keys },
            description: "Optional — narrow results to specific entry types."
          }
        },
        required: [ "query" ]
      )

      def self.call(server_context:, **tool_args)
        skill = Pipeline::Skills::BibleLookup.new(novel_directory_name: server_context.novel_directory_name)
        result = protect_stdout { skill.execute(tool_args) }

        # error: left at its default (false) — the existing
        # "[bible_lookup error: ...]"-shaped string returned as ordinary
        # text content is a deliberate parity decision with
        # skill_bridge.py, which never used MCP's native isError channel
        # either. Don't drift into using it without discussing that change.
        MCP::Tool::Response.new([ { type: "text", text: result } ])
      end

      # StdioTransport reads/writes $stdin/$stdout directly as the JSON-RPC
      # protocol stream — a stray write from inside a tool call would
      # corrupt it, same risk skill_bridge.py's own stdout-to-stderr
      # redirect exists to prevent. Protocol-stream plumbing, not business
      # logic — the call above still does exactly the four things the class
      # comment describes.
      def self.protect_stdout
        real_stdout = $stdout
        $stdout = $stderr
        yield
      ensure
        $stdout = real_stdout
      end
      private_class_method :protect_stdout
    end
  end
end
