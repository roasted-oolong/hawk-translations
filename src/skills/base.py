"""
src/skills/base.py
------------------
Defines the Skill protocol — the contract every injectable agent capability
must satisfy.

A Skill bundles three things:
  - tool_definition: the OpenAI-format schema the LLM sees when deciding
    whether to call the skill.
  - execute(tool_args): the Python side that actually runs when the LLM
    decides to use it.
  - bridge_spec(): how to reconstruct this skill in a separate process (see
    below) — used only by the "claude_code" translation backend.

src/agent.py (the "local" backend) accepts a list of Skill instances and
calls tool_definition/execute() directly in-process — it knows nothing about
what any specific skill does.

src/claude_code_agent.py (the "claude_code" backend) can't call execute()
directly — tool execution happens inside a separate MCP server subprocess
(src/mcp_servers/skill_bridge.py) that Claude Code itself invokes. That
subprocess needs to reconstruct each Skill instance from scratch, which is
what bridge_spec() is for. The default assumes a no-argument constructor;
skills with constructor arguments must override it.
"""

from abc import ABC, abstractmethod


class Skill(ABC):
    @property
    @abstractmethod
    def tool_definition(self) -> dict:
        """OpenAI-format tool definition passed to the model."""
        ...

    @abstractmethod
    def execute(self, tool_args: dict) -> str:
        """Run the skill with the given arguments and return a string result."""
        ...

    @property
    def name(self) -> str:
        """Convenience accessor for the tool's function name."""
        return self.tool_definition["function"]["name"]

    def bridge_spec(self) -> dict:
        """
        Describe how to reconstruct this skill in another process:
        {"module": ..., "class": ..., "kwargs": ...}.

        Used by src/mcp_servers/skill_bridge.py to instantiate a fresh copy
        of this skill from HAWK_SKILLS_SPEC. Override when __init__ takes
        arguments — the default assumes it doesn't.
        """
        return {
            "module": type(self).__module__,
            "class": type(self).__qualname__,
            "kwargs": {},
        }
