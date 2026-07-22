"""
src/mcp_servers/skill_bridge.py
--------------------------------
Generic MCP stdio server that exposes any Skill instance (src/skills/) as
an MCP tool, without any per-skill server code.

Launched by src/claude_code_agent.py as an MCP server subprocess for the
"claude_code" translation backend. Configured entirely via the
HAWK_SKILLS_SPEC environment variable — a JSON array of
{"module": ..., "class": ..., "kwargs": ...} entries (see Skill.bridge_spec()
in src/skills/base.py), one per skill to expose.

This file has no knowledge of what any specific skill does — it only
imports the class named in each spec, instantiates it, and wires its
existing tool_definition/execute() into the MCP protocol. Adding a new
Skill subclass later does not require touching this file.
"""

import asyncio
import importlib
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent))

import mcp.types as types
from mcp.server import Server
from mcp.server.stdio import stdio_server

from src.skills.base import Skill


def _load_skills() -> dict[str, Skill]:
    """Instantiate every skill named in HAWK_SKILLS_SPEC, keyed by tool name."""
    raw = os.environ.get("HAWK_SKILLS_SPEC", "[]")
    specs = json.loads(raw)

    skills: dict[str, Skill] = {}
    for spec in specs:
        module = importlib.import_module(spec["module"])
        skill_cls = getattr(module, spec["class"])
        skill: Skill = skill_cls(**spec["kwargs"])
        skills[skill.name] = skill
    return skills


def _build_server(skills: dict[str, Skill]) -> Server:
    server = Server("hawk-skills")

    @server.list_tools()
    async def list_tools() -> list[types.Tool]:
        return [
            types.Tool(
                name=skill.name,
                description=skill.tool_definition["function"]["description"],
                inputSchema=skill.tool_definition["function"]["parameters"],
            )
            for skill in skills.values()
        ]

    @server.call_tool()
    async def call_tool(name: str, arguments: dict) -> list[types.TextContent]:
        skill = skills.get(name)
        if skill is None:
            return [types.TextContent(type="text", text=f"[error: unknown tool {name!r}]")]

        # skill.execute() is synchronous and some skills print progress to
        # stdout (e.g. BibleLookupSkill's "[bible lookup] ..." line).
        # stdout here is the MCP protocol channel, not a console — redirect
        # any such output to stderr for the call so it can't corrupt the
        # stream.
        real_stdout = sys.stdout
        sys.stdout = sys.stderr
        try:
            result = skill.execute(arguments)
        finally:
            sys.stdout = real_stdout

        return [types.TextContent(type="text", text=result)]

    return server


async def _main() -> None:
    skills = _load_skills()
    server = _build_server(skills)
    async with stdio_server() as (read_stream, write_stream):
        await server.run(read_stream, write_stream, server.create_initialization_options())


if __name__ == "__main__":
    asyncio.run(_main())
