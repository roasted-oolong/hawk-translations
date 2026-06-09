"""
src/skills/web_search.py
------------------------
Skill that lets the translation agent search the web via Tavily when it
encounters an unfamiliar term, cultural reference, or proper noun.

Requires:
  - TAVILY_API_KEY in the environment
  - tavily-python installed (pip install tavily-python)
"""

import os

from src.skills.base import Skill


class WebSearchSkill(Skill):
    @property
    def tool_definition(self) -> dict:
        return {
            "type": "function",
            "function": {
                "name": "web_search",
                "description": (
                    "Search the web for information needed to translate accurately. "
                    "Use this when you encounter an unfamiliar Korean term, proper "
                    "noun, cultural reference, historical event, or place name that "
                    "needs additional context for an accurate English translation."
                ),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "query": {
                            "type": "string",
                            "description": "The search query, in English or Korean.",
                        }
                    },
                    "required": ["query"],
                },
            },
        }

    def execute(self, tool_args: dict) -> str:
        query = tool_args.get("query", "").strip()
        if not query:
            return "[web_search error: empty query]"

        try:
            from tavily import TavilyClient
        except ImportError:
            return "[web_search error: tavily-python not installed — run: pip install tavily-python]"

        api_key = os.environ.get("TAVILY_API_KEY")
        if not api_key:
            return "[web_search error: TAVILY_API_KEY not set in environment]"

        print(f"  [web search] {query}", flush=True)

        client = TavilyClient(api_key=api_key)
        response = client.search(query=query, max_results=3, include_answer=True)

        parts = []

        answer = response.get("answer")
        if answer:
            parts.append(f"Summary: {answer}")

        for result in response.get("results", []):
            title = result.get("title", "").strip()
            content = result.get("content", "").strip()
            if title and content:
                parts.append(f"**{title}**\n{content}")
            elif content:
                parts.append(content)

        return "\n\n---\n\n".join(parts) if parts else "No results found."
