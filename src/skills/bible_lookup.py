"""
src/skills/bible_lookup.py
--------------------------
Skill that lets the translation agent query the Hawk bible database
mid-translation to check established character names, locations, terminology,
cultural phrases, and story context.

Requires the Rails server to be running and reachable at HAWK_RAILS_URL
(defaults to http://localhost:3000). The novel ID is resolved lazily on first
use by calling GET /novels/find_by_directory?directory_name=<dir>.
"""

import json
import urllib.parse
import urllib.request

from src.skills.base import Skill

_CATEGORY_LABELS = {
    "BibleCharacter":      "Character",
    "BibleLocation":       "Location",
    "BibleTerminology":    "Terminology",
    "BibleCulturalPhrase": "Cultural Phrase",
    "BibleStoryEntry":     "Story Entry",
}


class BibleLookupSkill(Skill):
    def __init__(self, novel_dir_name: str, rails_url: str):
        self._novel_dir_name = novel_dir_name
        self._rails_url = rails_url.rstrip("/")
        self._novel_id: int | None = None

    @property
    def tool_definition(self) -> dict:
        return {
            "type": "function",
            "function": {
                "name": "bible_lookup",
                "description": (
                    "Look up entries in the translation bible to check established "
                    "character names, locations, terminology, cultural phrases, and "
                    "story context. Use this when you encounter a name, term, or "
                    "reference in the source text and want to check how it has been "
                    "translated or documented."
                ),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "query": {
                            "type": "string",
                            "description": (
                                "The name, term, or phrase to look up. "
                                "Can be in English or Korean."
                            ),
                        },
                        "categories": {
                            "type": "array",
                            "items": {
                                "type": "string",
                                "enum": list(_CATEGORY_LABELS.keys()),
                            },
                            "description": (
                                "Optional — narrow results to specific entry types."
                            ),
                        },
                    },
                    "required": ["query"],
                },
            },
        }

    def bridge_spec(self) -> dict:
        return {
            "module": type(self).__module__,
            "class": type(self).__qualname__,
            "kwargs": {
                "novel_dir_name": self._novel_dir_name,
                "rails_url": self._rails_url,
            },
        }

    def execute(self, tool_args: dict) -> str:
        query = tool_args.get("query", "").strip()
        if not query:
            return "[bible_lookup error: empty query]"

        try:
            novel_id = self._resolve_novel_id()
        except Exception as exc:
            return f"[bible_lookup error: could not resolve novel — {exc}]"

        categories = tool_args.get("categories") or []
        pairs = [("q", query), ("limit", "5")]
        pairs += [(f"categories[]", c) for c in categories]
        qs = urllib.parse.urlencode(pairs)

        url = f"{self._rails_url}/novels/{novel_id}/bible/search?{qs}"
        print(f"  [bible lookup] {query}", flush=True)

        try:
            with urllib.request.urlopen(url, timeout=10) as resp:
                data = json.loads(resp.read())
        except Exception as exc:
            return f"[bible_lookup error: {exc}]"

        results = data.get("results", [])
        if not results:
            return f"No bible entries found for: {query}"

        return self._format_results(results)

    # -------------------------------------------------------------------------

    def _resolve_novel_id(self) -> int:
        if self._novel_id is not None:
            return self._novel_id

        qs = urllib.parse.urlencode({"directory_name": self._novel_dir_name})
        url = f"{self._rails_url}/novels/find_by_directory?{qs}"

        with urllib.request.urlopen(url, timeout=10) as resp:
            data = json.loads(resp.read())

        novel_id = data.get("id")
        if not novel_id:
            raise RuntimeError(
                f"No novel found with directory_name={self._novel_dir_name!r}"
            )

        self._novel_id = int(novel_id)
        return self._novel_id

    def _format_results(self, results: list[dict]) -> str:
        parts = []
        for r in results:
            entry_type = r.get("embeddable_type", "")
            label = _CATEGORY_LABELS.get(entry_type, entry_type)
            rec = r.get("record", {})
            body = _format_record(entry_type, rec)
            parts.append(f"[{label}]\n{body}")
        return "\n\n".join(parts)


# -----------------------------------------------------------------------------
# Record formatters — one branch per bible entry type
# -----------------------------------------------------------------------------

def _format_record(entry_type: str, rec: dict) -> str:
    if entry_type == "BibleCharacter":
        return _lines(
            ("Name",                   rec.get("name")),
            ("Korean name",            rec.get("korean_name")),
            ("Aliases",                rec.get("aliases")),
            ("Role",                   rec.get("role")),
            ("Significance",           rec.get("significance")),
            ("Physical description",   rec.get("physical_description")),
            ("Speech pattern",         rec.get("speech_pattern")),
            ("Honorifics used toward", rec.get("honorifics_used_toward")),
            ("Honorifics they use",    rec.get("honorifics_they_use")),
            ("Relationships",          rec.get("relationships")),
            ("Notes",                  rec.get("notes")),
        )
    if entry_type == "BibleLocation":
        return _lines(
            ("Name",        rec.get("name")),
            ("Korean name", rec.get("korean_name")),
            ("Type",        rec.get("location_type")),
            ("Description", rec.get("description")),
            ("Significance", rec.get("significance")),
            ("Notes",       rec.get("notes")),
        )
    if entry_type == "BibleTerminology":
        return _lines(
            ("Term",         rec.get("term")),
            ("Korean term",  rec.get("korean_term")),
            ("Definition",   rec.get("definition")),
            ("Usage notes",  rec.get("usage_notes")),
            ("Notes",        rec.get("notes")),
        )
    if entry_type == "BibleCulturalPhrase":
        return _lines(
            ("Phrase",                 rec.get("phrase")),
            ("Korean phrase",          rec.get("korean_phrase")),
            ("Literal translation",    rec.get("literal_translation")),
            ("Intended meaning",       rec.get("intended_meaning")),
            ("Context",                rec.get("context")),
            ("Established translation", rec.get("established_translation")),
            ("Notes",                  rec.get("notes")),
        )
    if entry_type == "BibleStoryEntry":
        return _lines(
            ("Title",    rec.get("title")),
            ("Category", rec.get("category")),
            ("Content",  rec.get("content")),
            ("Notes",    rec.get("notes")),
        )
    # Fallback for any future entry types
    return "\n".join(
        f"{k}: {v}"
        for k, v in rec.items()
        if k not in ("id", "novel_id", "organization_id", "created_at", "updated_at")
        and v
    )


def _lines(*pairs: tuple[str, object]) -> str:
    return "\n".join(f"{label}: {value}" for label, value in pairs if value)
