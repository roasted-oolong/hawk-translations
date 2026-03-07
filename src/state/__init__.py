"""
Translation state — session state container for the REPL.

TranslationState is a plain dict for now. create_initial_state builds
the starting shape expected by translate.py and any nodes that run.
"""

from pathlib import Path


# Type alias — state is a plain dict throughout the codebase.
TranslationState = dict


def create_initial_state(novel_dir: str, korean_file: str) -> TranslationState:
    """
    Build the initial session state for a novel + chapter.

    Keys set here are the minimum required by translate.py on startup.
    Pipeline nodes (format, extract, translate, etc.) will add their own
    keys as they run.
    """
    return {
        "novel_dir":      novel_dir,
        "korean_file":    korean_file,
        "output_path":    None,
        "korean_text":    "",
        "translated_text": "",
        "current_stage":  "init",
        "errors":         [],
        # Bible contents — populated by init_node when it runs
        "bible": {
            "characters":       "",
            "cultural_phrases": "",
            "locations":        "",
            "story":            "",
            "terminology":      "",
        },
        # Reference files — populated by init_node when it runs
        "novel_info":             "",
        "translation_guidelines": "",
        "series_info":            "",
    }
