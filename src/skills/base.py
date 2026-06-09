"""
src/skills/base.py
------------------
Defines the Skill protocol — the contract every injectable agent capability
must satisfy.

A Skill bundles two things:
  - tool_definition: the OpenAI-format schema the LLM sees when deciding
    whether to call the skill.
  - execute(tool_args): the Python side that actually runs when the LLM
    decides to use it.

agent.py accepts a list of Skill instances. It knows nothing about what any
specific skill does — it only calls tool_definition and execute().
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
