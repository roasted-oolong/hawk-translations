"""
tests/test_skill_bridge.py
----------------------------
Unit tests for src/mcp_servers/skill_bridge.py — the generic MCP server
that exposes any Skill instance as an MCP tool. No real MCP client/stdio
transport is involved; the server's registered request handlers are
exercised directly.
"""

import asyncio
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

import mcp.types as types

from src.mcp_servers import skill_bridge
from src.skills.base import Skill


class _FixtureSkill(Skill):
    """A minimal Skill for exercising the bridge, independent of any real skill."""

    @property
    def tool_definition(self) -> dict:
        return {
            "type": "function",
            "function": {
                "name": "fixture_tool",
                "description": "A fixture skill for testing the bridge.",
                "parameters": {
                    "type": "object",
                    "properties": {"q": {"type": "string"}},
                    "required": ["q"],
                },
            },
        }

    def execute(self, tool_args: dict) -> str:
        print("progress line to stdout", flush=True)
        return f"executed with q={tool_args['q']}"


def _run(coro):
    return asyncio.run(coro)


def test_load_skills_instantiates_from_spec(monkeypatch):
    spec = [{"module": __name__, "class": "_FixtureSkill", "kwargs": {}}]
    monkeypatch.setenv("HAWK_SKILLS_SPEC", json.dumps(spec))

    skills = skill_bridge._load_skills()

    assert list(skills.keys()) == ["fixture_tool"]
    assert isinstance(skills["fixture_tool"], _FixtureSkill)


def test_load_skills_passes_kwargs(monkeypatch):
    # BibleLookupSkill-shaped: a skill that does take constructor kwargs.
    from src.skills.bible_lookup import BibleLookupSkill

    spec = [{
        "module": "src.skills.bible_lookup",
        "class": "BibleLookupSkill",
        "kwargs": {"novel_dir_name": "some-novel", "rails_url": "http://localhost:3000"},
    }]
    monkeypatch.setenv("HAWK_SKILLS_SPEC", json.dumps(spec))

    skills = skill_bridge._load_skills()

    bible_skill = skills["bible_lookup"]
    assert isinstance(bible_skill, BibleLookupSkill)
    assert bible_skill._novel_dir_name == "some-novel"


def test_load_skills_empty_spec_returns_empty_dict(monkeypatch):
    monkeypatch.setenv("HAWK_SKILLS_SPEC", "[]")
    assert skill_bridge._load_skills() == {}


def test_list_tools_reflects_tool_definition():
    server = skill_bridge._build_server({"fixture_tool": _FixtureSkill()})
    handler = server.request_handlers[types.ListToolsRequest]

    result = _run(handler(types.ListToolsRequest()))

    tools = result.root.tools
    assert len(tools) == 1
    assert tools[0].name == "fixture_tool"
    assert tools[0].description == "A fixture skill for testing the bridge."
    assert tools[0].inputSchema["required"] == ["q"]


def test_call_tool_dispatches_to_skill_execute():
    server = skill_bridge._build_server({"fixture_tool": _FixtureSkill()})
    handler = server.request_handlers[types.CallToolRequest]

    req = types.CallToolRequest(
        params=types.CallToolRequestParams(name="fixture_tool", arguments={"q": "hello"}),
    )
    result = _run(handler(req))

    assert result.root.isError is False
    assert result.root.content[0].text == "executed with q=hello"


def test_call_tool_unknown_name_returns_error_text():
    server = skill_bridge._build_server({})
    handler = server.request_handlers[types.CallToolRequest]

    req = types.CallToolRequest(
        params=types.CallToolRequestParams(name="nonexistent", arguments={}),
    )
    result = _run(handler(req))

    assert "unknown tool" in result.root.content[0].text


def test_call_tool_redirects_skill_stdout_to_stderr(capsys):
    server = skill_bridge._build_server({"fixture_tool": _FixtureSkill()})
    handler = server.request_handlers[types.CallToolRequest]
    stdout_before = sys.stdout

    req = types.CallToolRequest(
        params=types.CallToolRequestParams(name="fixture_tool", arguments={"q": "x"}),
    )
    _run(handler(req))

    captured = capsys.readouterr()
    assert "progress line to stdout" not in captured.out
    assert "progress line to stdout" in captured.err
    # Must be restored afterwards, not left pointed at stderr.
    assert sys.stdout is stdout_before
