# ---------------------------------------------------------------------------
# Pipeline::Mcp::ServerContext
#
# The single per-invocation context object every tool this bridge exposes
# receives, per R3 in docs/RAILS_REFACTOR_PLAN.md. Built once per bridge-
# process spawn (one spawn per translation call — see the bridge script),
# never mutated or reused across calls. An immutable value object rather
# than a Hash, matching Pipeline::Subprocess::Result's precedent for
# small, fixed, done-once data.
#
# Grow this deliberately as new skills need more context, not
# opportunistically — it's meant to stay small.
# ---------------------------------------------------------------------------
module Pipeline
  module Mcp
    ServerContext = Data.define(:novel_directory_name)
  end
end
