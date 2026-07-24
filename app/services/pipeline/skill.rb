# ---------------------------------------------------------------------------
# Pipeline::Skill
#
# Shared contract every injectable agent capability satisfies — Ruby
# equivalent of src/skills/base.py::Skill. A joint dependency of R1's
# "local" tool loop and R3's MCP bridge adapter, not owned by either.
#
# tool_definition: a provider-neutral tool schema (name + description +
# JSON-schema parameters) — adapted per provider by whoever calls it, not
# owned by one (see R3's MCP::Tool adapter, which extracts these fields
# rather than forwarding this hash verbatim).
# execute(tool_args): runs the skill, always returns a String, never raises.
# ---------------------------------------------------------------------------
module Pipeline
  module Skill
    def tool_definition
      raise NotImplementedError, "#{self.class} must implement #tool_definition"
    end

    def execute(_tool_args)
      raise NotImplementedError, "#{self.class} must implement #execute"
    end

    # Convenience accessor, mirroring Python's Skill#name.
    def name
      tool_definition[:function][:name]
    end
  end
end
