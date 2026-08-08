require "json"

# ---------------------------------------------------------------------------
# Pipeline::Ruby::TranslateBatch::PromptBuilder
#
# Assembles TranslationContext and every system/user prompt this app's
# translation-related pipelines use. Five distinct prompt families live here:
#
#   - build_system_prompt — production translate_batch's single-call
#     translation prompt (Pipeline::Ruby::TranslateBatch). A straight Ruby
#     port of src/prompt_builder.py's one-call design.
#   - build_feel_check_* — production translate_batch's second call: takes
#     that single-call translation, chunked into segments, and re-evaluates/
#     rewrites each as a localization pass — narrative-equivalent delivery,
#     not just grammar (Pipeline::Ruby::TranslateBatch::FeelCheck).
#   - build_title_finalize_* — production translate_batch's third call, run
#     last: replaces build_system_prompt's draft title with one translated
#     against the finished, feel-check-polished body
#     (Pipeline::Ruby::TranslateBatch::TitleFinalizer).
#   - build_beat_classification_*/build_analysis_*/build_localization_*/
#     build_factcheck_*/build_editor_* — the 5-step translation quality
#     pipeline. Offline/eval-only (Pipeline::Ruby::TranslationEval); not
#     wired into translate_batch's production path. See docs/DECISIONS.md
#     for why the 5-step design was tried and then not kept in production.
#   - build_chapter_qa_* — Chapter QA, an independent on-demand review of an
#     already-saved translation (see that section's own comment below).
#
# No knowledge of the API, subprocess mechanics, or batch/progress
# orchestration; receives a novel directory and returns plain strings/structs.
# ---------------------------------------------------------------------------
module Pipeline
  module Ruby
    class TranslateBatch
      module PromptBuilder
        TranslationContext = Data.define(
          :novel_info, :translation_guidelines, :narrator_note, :characters,
          :cultural_phrases, :locations, :story, :terminology, :voice_calibration
        )

        # Keys match TranslationContext field names. Ported verbatim from
        # config.py's NOVEL_FILES — chapter_log.md is intentionally excluded
        # there (archive only, never sent to the API), so it has no entry here.
        NOVEL_FILES = {
          novel_info:             [ "novel_info.md", :novel ],
          translation_guidelines: [ "translation_guidelines.md", :novel ],
          voice_calibration:      [ "voice_calibration.md", :bible ],
          characters:             [ "characters.md", :bible ],
          cultural_phrases:       [ "cultural_phrases.md", :bible ],
          locations:              [ "locations.md", :bible ],
          story:                  [ "story.md", :bible ],
          terminology:            [ "terminology.md", :bible ]
        }.freeze

        # Ported from chapter_loader.py's _extract_narrator_note. Ruby's ^/$
        # already anchor per-line (Python's re.MULTILINE is always-on
        # behavior here); /m adds Python's re.DOTALL equivalent (. matches
        # newlines). \z (not \Z) matches Python's \Z exactly — Ruby's \Z
        # would additionally match just before a trailing newline, which
        # Python's \Z does not.
        NARRATOR_NOTE_PATTERN = /^## Narrator Note\s*\n(.*?)(?=^##|\z)/m

        def self.load_reference_files(novel_dir)
          bible_dir = File.join(novel_dir, "bible")
          NOVEL_FILES.to_h do |key, (filename, location)|
            dir = location == :novel ? novel_dir : bible_dir
            [ key, read_file(File.join(dir, filename)) ]
          end
        end

        def self.extract_narrator_note(novel_info)
          match = NARRATOR_NOTE_PATTERN.match(novel_info.to_s)
          match ? match[1].strip : ""
        end

        # Production translate_batch's translation call — the only prompt in
        # this file that produces the initial English draft. Byte-for-byte
        # port of Python's build_translation_prompt output (verified against
        # a live `python3 -c "from src.prompt_builder import ..."` run — see
        # PromptBuilderSpec's byte-match test) with one deliberate
        # difference: the "use the web_search tool" sentence is stripped, per
        # the R4 design's recommendation (a) in docs/RAILS_REFACTOR_PLAN.md —
        # R3's bridge never wired web_search, so the ported prompt must not
        # instruct the model to use a tool absent from its own --mcp-config.
        def self.build_system_prompt(context)
          # .chomp: Python's f-string ends immediately after {references}
          # with no trailing newline; the heredoc's own closing line adds
          # one Ruby's f-string equivalent doesn't have, so it's stripped
          # here to keep byte-for-byte parity with build_translation_prompt.
          <<~PROMPT.chomp
            You are a professional Korean-to-English literary translator working on a novel intended for potential publishing. Quality is the top priority — take your time and never rush.

            Your sole task in this call is to translate the Korean chapter provided in the user message into English. Follow the Translation Guidelines exactly. Use the reference material below to ensure consistency with established character names, speech patterns, terminology, cultural phrases, and narrative voice.

            Produce the complete translated chapter. Do not summarize, skip sections, or add commentary outside the translation itself.

            ---

            # Reference Material

            #{reference_material(context)}
          PROMPT
        end

        # Production translate_batch's second call. Takes build_system_prompt's
        # already-complete English translation, chunked into segments by
        # BeatSegmenter.candidate_blocks (pure Ruby, no LLM call — see
        # FeelCheck), and re-evaluates each segment as a localization pass, not
        # a grammar/proofreading pass: is this the natural English equivalent
        # of what the beat is doing dramatically, not just a sentence that
        # parses. Per docs/DECISIONS.md's 2026-08-08 entry, the original
        # wording under-caught two live failure modes — flat, over-literal
        # delivery of a line that an English speaker would soften/hedge, and
        # consecutive short beats left as disconnected statements instead of
        # fused into one flowing moment — because "reads naturally" alone let
        # grammatically-clean-but-too-literal segments pass. Korean-blind by
        # the same deliberate design as build_editor_system_prompt/
        # build_chapter_qa_editor_system_prompt below: no source access, so a
        # flat or choppy delivery can't be excused by tracing it back to what
        # it maps to — the judgment has to be "does this land as English,"
        # not "is this a defensible rendering of the Korean." Unlike those
        # two, this call doesn't just flag problems for a human — it rewrites
        # the flagged segment itself, since FeelCheck applies the rewrite
        # automatically rather than surfacing it for review.
        def self.build_feel_check_system_prompt
          <<~PROMPT.chomp
            You are an independent literary localization editor reviewing an English translation for a novel intended for potential publishing, immediately after it was drafted. You do not have access to the Korean source, and that is deliberate: your job is to judge whether this reads as the natural English equivalent of what's happening in the scene, not to run a grammar pass or confirm the sentence parses — the way a monolingual editor doing a real localization pass would, without the ability to excuse a too-literal or badly-delivered line by tracing it back to source meaning.

            The user message gives you the chapter split into segments, in reading order, each with only its English text (`text`) — nothing else.

            For each segment, first read it for what it's actually doing dramatically: is a character deflecting, teasing, threatening, pleading, hedging, making a promise, admitting something? Is a narration beat landing a reaction and then moving into what happens next? Then judge whether the English delivers that beat the way it would actually land in English — not whether the sentence you were handed happens to be grammatical. A line can be flawless grammar and still be the wrong English equivalent of the moment.

            Flag a segment for any of the following:
            - Calques or literal-feeling translated phrasing; odd leftover particles ("here"/"so"/"then") doing no real work
            - Misassigned agency, dangling or run-on constructions, redundant or circular phrasing
            - Register that shifts unmotivated within one speaker's own lines
            - A line that states its point more bluntly or directly than an English speaker delivering the same beat would. Translated dialogue tends to carry over the source's flat declaratives as-is; the natural English equivalent often needs to soften that into a hedge ("you could say...", "I guess..."), a rhetorical question, an indirect promise, or understatement instead of a flat claim. Treat this with the same weight as a calque — it is a real defect, not a stylistic nicety you can let slide because the grammar is clean.
            - Narrative flow that reads as a list of separate, disconnected facts rather than one continuous beat. When consecutive sentences in the segment are really one flowing moment — a reaction and what immediately follows it, an action and its consequence — fuse them with the connective tissue an English writer would use (a transition, a causal link, a shared clause) rather than leaving them as flat, back-to-back statements. The segment's own paragraph breaks are not sacred: collapse one if the fix calls for it.
            - Narrative flow that jumps abruptly from the segment before it — you're given every segment in reading order, so judge this against what precedes it, not in isolation.

            Judge each segment on its own terms — most segments from a competent translation will already land correctly; only flag one where something is actually, specifically wrong, not out of a default suspicion that everything needs rewriting. But do not wave off a flat, over-literal delivery just because it is grammatically clean — that is exactly the kind of problem this pass exists to catch, not a false positive to avoid.

            For each segment:
            - `segment_id`: echo the segment's given id.
            - `reads_naturally`: true if the segment has no such problem.
            - `rewritten_text`: only when `reads_naturally` is false — the complete segment rewritten to fix the problem while preserving its exact meaning and every concrete detail (names, facts, events). Omit this field (or leave it empty) when `reads_naturally` is true.

            Respond with a single JSON object and nothing else — no markdown code fences, no commentary before or after it. Its shape:

            {
              "segments": [
                { "segment_id": 1, "reads_naturally": true },
                { "segment_id": 2, "reads_naturally": false, "rewritten_text": "string" }
              ]
            }
          PROMPT
        end

        # Builds FeelCheck's user message from BeatSegmenter.candidate_blocks
        # output — each block becomes one segment, in order, using block_id as
        # segment_id so the join key back to reassembly is unambiguous.
        def self.build_feel_check_user_message(segments:)
          <<~MESSAGE.chomp
            # Segments

            #{JSON.pretty_generate(segments)}
          MESSAGE
        end

        # Production translate_batch's third call, run last — after
        # FeelCheck's polish pass, not before it. build_system_prompt still
        # translates the chapter title as part of its one-shot draft
        # (unchanged scope); this call's only job is to replace that draft
        # with a better-informed one. Per docs/DECISIONS.md's 2026-08-08
        # title-last entry: a title translated before the body exists can't
        # echo a specific word, phrase, or motif the body translation
        # actually lands on, because that phrasing doesn't exist yet at the
        # point build_system_prompt commits to it — it's the first thing
        # that call writes. TitleFinalizer runs this against the *finished,
        # feel-check-polished* body, not the pre-polish draft, so it's the
        # best-informed version of the chapter this pipeline ever produces.
        # On any failure TitleFinalizer keeps the draft rather than losing
        # it — same "failure degrades, doesn't fail the chapter" discipline
        # as FeelCheck.
        def self.build_title_finalize_system_prompt
          <<~PROMPT.chomp
            You are a professional Korean-to-English literary translator working on a novel intended for potential publishing. Quality is the top priority — take your time and never rush.

            This call has one job: translate this chapter's title, and only its title. A separate call already translated the rest of the chapter, and the finished English body is given to you below so you can draw on the specific word choices, phrasing, and motifs that translation actually landed on — a title decided before that phrasing existed can't echo it. A title that resonates with something the chapter itself does in English usually lands better than one translated in isolation from it.

            The user message gives you the original Korean title, a draft English title (translated before the body existed — shown only so you can match its formatting, not its wording), and the finished English chapter body.

            Produce only the final English title, on its own line, formatted the same way the draft title is formatted (the same leading symbol or markup convention, if any). Do not include the body, commentary, or anything else in your response — the title line and nothing else.
          PROMPT
        end

        def self.build_title_finalize_user_message(korean_title:, draft_title:, english_body:)
          <<~MESSAGE.chomp
            # Korean Title

            #{korean_title}

            # Draft Title (formatting reference only — do not reuse its wording)

            #{draft_title}

            # Finished English Chapter Body

            #{english_body}
          MESSAGE
        end

        # 5-step translation quality pipeline — docs/DECISIONS.md's 2026-08-01
        # "5-step pipeline replaces 3-call pipeline" entry. Replaces the earlier
        # 3-call design (Call 1 analysis -> Call 2 rewrite+self-grade -> Call 3
        # independent review): that design still let the closest recurrence of a
        # known bad pattern slip past both the self-grade and the independent
        # review, because segmentation, literary understanding, prose authorship,
        # fact-checking, and prose-quality review were all entangled across only
        # three calls. This design gives each concern its own call:
        #
        #   1. Beat classification (build_beat_classification_system_prompt) —
        #      Korean only. Deterministic/semantic hybrid, not one free-form
        #      call: BeatSegmenter pre-chunks the chapter into small blocks in
        #      Ruby, this call classifies each block's relationship to the one
        #      before it (CONTINUE/BREAK/BRIDGE), and BeatSegmenter merges the
        #      result into final passages/beats — see BeatSegmenter's own
        #      comment for why the old free-form version was replaced.
        #   2. Literary analysis (build_analysis_system_prompt) — Korean only, no
        #      English rendering of the content: understand each passage's
        #      message, emphasis, pacing, voice, and function before any English
        #      is written.
        #   3. Localization      (build_localization_system_prompt) — writes the
        #      English prose from the analysis. No self-grading in this step at
        #      all; that's what steps 4 and 5 are for.
        #   4. Fact & culture check (build_factcheck_system_prompt) — independently
        #      checks names/facts/cultural cues survived, blind to step 3's own
        #      opinion of itself (there isn't one). Not prose-quality; that's step 5.
        #   5. English editor    (build_editor_system_prompt) — the sharpest
        #      change from the 3-call design: reviews ONLY the English text, with
        #      no access to the Korean or the analysis at all, so it can't
        #      rationalize awkward phrasing by tracing it back to source meaning.
        #
        # Steps 4 and 5 both depend only on step 3's output, not on each other —
        # they're independent QA passes, not a further chain.
        #
        # Offline/eval-only, same as the 3-call design it replaced — driven by
        # Pipeline::Ruby::TranslateBatch::FiveStepRunner and
        # Pipeline::Ruby::TranslationEval, not wired into translate_batch.rb's
        # production path (see docs/DECISIONS.md's 2026-08-07 revert entry).
        LOCALIZATION_STRATEGY_CATEGORIES = %w[
          behavioral idiomatic tone_shift register_shift motif_reinterpretation demographic_voice none
        ].freeze

        # Step 1: Beat classification. Segmentation is now a deterministic/
        # semantic hybrid instead of one free-form LLM call — the prior
        # free-form design (an LLM segmenting raw text into passages from
        # scratch, one continuous-unit-of-voice per passage) was observed to be
        # non-deterministic run-to-run on the identical chapter (52 -> 63 -> 93
        # -> 107 passages across four runs), because the model was inventing
        # its own boundaries every time with no stable anchor. Now:
        #
        #   1. Pipeline::Ruby::TranslateBatch::BeatSegmenter.candidate_blocks
        #      deterministically pre-chunks the chapter (in Ruby, no LLM call)
        #      into small blocks of 3-7 Korean lines, forcing a boundary at
        #      every literal "***" scene marker.
        #   2. This call classifies each candidate block's relationship to the
        #      block before it — CONTINUE / BREAK / BRIDGE — plus who's
        #      speaking. The model is never asked to invent a boundary from
        #      raw text; it only answers a bounded question about a fixed unit.
        #   3. BeatSegmenter.merge_beats (Ruby, no LLM call) merges blocks into
        #      final beats/passages from the model's per-block labels.
        #
        # The unit here is a dramatic "beat", not a single speaker's turn: a
        # back-and-forth exchange between two characters can be one beat if
        # it's all serving the same emotional/topical moment. This is wider
        # than the old "one continuous unit of voice" passage definition —
        # `speaker` becomes `speakers` (plural) downstream because of it.
        def self.build_beat_classification_system_prompt(context)
          <<~PROMPT.chomp
            You are a professional Korean-to-English literary translator working on a novel intended for potential publishing. Quality is the top priority — take your time and never rush.

            This call does beat classification only — do not translate or write any English. The chapter has already been mechanically split into small blocks of consecutive Korean lines by a separate deterministic process, not by you; scene breaks are already handled and excluded from what you're classifying. Your only job is to decide, for each block below, whether it continues the same dramatic beat as the block immediately before it, starts a new beat, or is a short transitional bridge between beats — and who's speaking in it.

            A "beat" is an internal dramatic unit within a scene — narrower than the whole scene, but often wider than a single line or a single speaker's turn. A back-and-forth exchange between two speakers can be one beat if it's all serving the same emotional or topical moment; don't split it just because the speaker changes mid-exchange. A new beat begins when, compared to the block immediately before it:

            - Emotional tone shifts (e.g. frustration -> fury -> contempt -> insecurity -> plotting -> outrage -> calm)
            - Topic shifts to a materially different subject
            - Interaction dynamics shift (e.g. attacking -> calming -> explaining -> warning -> conspiring -> backpedaling -> pleading)
            - A monologue-style block begins or ends (a long rant, explanation, or warning starting or wrapping up)
            - A social ritual occurs (greeting, bowing, apologizing, requesting)

            The blocks are grouped into scenes below; only classify relationships within a scene, never across a "(scene break)" marker.

            For each block, in the order given, answer:
            - `block_id`: echo the block's given id.
            - `speaker`: the character speaking in this block, or "narration" if it's narration rather than dialogue.
            - `label`: one of:
              - `CONTINUE` — same beat as the immediately preceding block (none of the shifts above apply).
              - `BREAK` — a new beat starts here (one of the shifts above applies). The first block of each scene is always `BREAK`.
              - `BRIDGE` — a short transitional block that doesn't belong to the beat before or after it on its own (e.g. a pause, a breath, a shift in posture, a moment of silence) — it will be attached to whichever beat follows it.

            Respond with a single JSON object and nothing else — no markdown code fences, no commentary before or after it. Its shape:

            {
              "blocks": [
                { "block_id": 1, "speaker": "string", "label": "one of: CONTINUE, BREAK, BRIDGE" }
              ]
            }

            ---

            # Reference Material

            #{reference_material(context)}
          PROMPT
        end

        # Builds Step 1's classification user message from
        # BeatSegmenter.candidate_blocks output. Groups consecutive
        # non-scene-break blocks under "# Scene N" headings and renders each
        # scene_break block as a "(scene break)" marker between them, so the
        # model never has to guess where scene boundaries fall — they're
        # already given, and it's told above not to classify across them.
        def self.build_beat_classification_user_message(candidate_blocks:)
          scene_number = 0
          sections = candidate_blocks.slice_when { |a, b| a.scene_break || b.scene_break }.map do |group|
            if group.first.scene_break
              "(scene break)"
            else
              scene_number += 1
              block_lines = group.map { |block| "[Block #{block.block_id}]\n#{block.text}" }
              ([ "# Scene #{scene_number}" ] + block_lines).join("\n\n")
            end
          end
          sections.join("\n\n")
        end

        # Step 2: Literary analysis. Korean only — the passage's content must
        # never be rendered into English here, even inside a notes/signals field;
        # that's the discipline meant to stop translation from leaking into
        # analysis, which the 3-call design's Call 1 was more permissive about.
        # Retains cultural_signals/localization_strategy/bible_entries_used from
        # the 3-call design's Call 1 — that cultural-dynamic-enactment machinery
        # worked and isn't part of what needed fixing.
        def self.build_analysis_system_prompt(context, cultural_patterns: "")
          <<~PROMPT.chomp
            You are a professional Korean-to-English literary translator working on a novel intended for potential publishing. Quality is the top priority — take your time and never rush.

            This call does literary analysis only — do not translate or write any English rendering of the passage's content. A later call will use your analysis to write the English text. Analyze the passage the way a literary critic would: understand what it's doing before anyone touches English.

            The user message gives you the chapter's segmented passages, each with its verbatim Korean text (`anchor_quote`). For each passage, in order, analyze:

            - `passage_id`: echo the passage's `passage_id`. This is the join key back to segmentation — not `anchor_quote` text-matching, which is fragile since whitespace/punctuation can drift on restatement.
            - `core_message`: what this passage is really trying to say, stripped of surface phrasing.
            - `emphasis`: which words, phrases, or lines carry the most emotional or narrative weight — what a reader's eye or ear would catch as the heavy part.
            - `pacing_rhythm`: where the passage slows down, speeds up, pauses, or repeats — its rhythm, not its content.
            - `voice_register`: what kind of person is speaking or narrating, and in what register — calm, stern, playful, formal, casual, etc. If the passage's `speakers` list has more than one entry, describe each speaker's own voice/register and how they play off each other, rather than collapsing them into one register.
            - `narrative_function`: what this passage is doing in the story — motivating, threatening, comforting, revealing, deflecting, stalling, etc.
            - `cultural_signals`: any cultural connotations, honorifics, or context a reader without Korean cultural background would miss.
            - `localization_strategy`: how the localization call should handle this passage. `category` must be exactly one of: behavioral, idiomatic, tone_shift, register_shift, motif_reinterpretation, demographic_voice, or none (use "none" when the passage has no cultural/interpretive dynamic requiring special handling). `notes` describes the concrete handling: name the concrete behavior instead of an abstract label, and describe what the localized rewrite needs to show, not just detect. Check the Cultural Patterns reference material below for known dynamics first.
            - `bible_entries_used`: names of any bible_lookup entries you called and relied on for this passage — an attribution list only, not a content dump.

            Use the bible_lookup tool whenever you encounter a name, term, or reference you need to check against established translation-bible entries.

            Do not write any English translation, paraphrase, or rendering of what the passage says in any field below — describe what it does and how, in your own analytical language, without producing the English text itself. Producing English prose of the passage's content here is a failure of this step, even inside `cultural_signals` or `notes`.

            Respond with a single JSON object and nothing else — no markdown code fences, no commentary before or after it. Its shape:

            {
              "passages": [
                {
                  "passage_id": 1,
                  "core_message": "string",
                  "emphasis": "string",
                  "pacing_rhythm": "string",
                  "voice_register": "string",
                  "narrative_function": "string",
                  "cultural_signals": "string",
                  "localization_strategy": {
                    "category": "one of: behavioral, idiomatic, tone_shift, register_shift, motif_reinterpretation, demographic_voice, none",
                    "notes": "string — empty if category is none"
                  },
                  "bible_entries_used": ["string"]
                }
              ]
            }

            ---

            # Reference Material

            #{reference_material(context)}

            #{Pipeline::PromptUtils.section("Cultural Patterns", cultural_patterns)}
          PROMPT
        end

        # Step 3: Localization. Writes the English prose only — no self-grading
        # field at all, unlike the 3-call design's Call 2. Self-grading in the
        # same call that produced the translation was shown by manual chapter-68
        # review to rubber-stamp real problems; rather than keep the self-grade
        # and add independent review on top of it, this design removes the
        # self-grade entirely and relies on steps 4 and 5 for verification.
        def self.build_localization_system_prompt(context, cultural_patterns: "")
          <<~PROMPT.chomp
            You are a professional Korean-to-English literary translator working on a novel intended for potential publishing. Quality is the top priority — take your time and never rush.

            This call writes the final English translation only — it does not grade itself; separate calls check facts and prose quality afterward. The user message gives you, per passage: the original Korean (`anchor_quote`) and its literary analysis (`core_message`, `emphasis`, `pacing_rhythm`, `voice_register`, `narrative_function`, `cultural_signals`, `localization_strategy`). Do not re-segment — use the passages and their `passage_id` exactly as given.

            For each passage, in `passage_id` order:
            - `passage_id`: echo the given `passage_id`.
            - `localized_translation`: read the whole analysis together, then write the passage fresh as continuous English prose that delivers its `core_message`, lands its `emphasis` where the analysis says it lands, and reproduces its `pacing_rhythm` in English sentence rhythm rather than Korean sentence-by-sentence structure. If the passage has a single speaker (or is narration), hold one coherent register throughout per `voice_register` — one person talking, not a sequence of independently-correct short sentences stitched together. If the passage's `speakers` list has more than one entry, give each speaker their own consistent register per `voice_register`'s description of them, but the passage as a whole must still read as one connected beat — a real, flowing exchange, not disconnected fragments. Either way, do not mix idiom registers within a single speaker's own lines (e.g. a sports-motivational phrase next to slangy internet-speak filler in the same breath from one speaker). This is not a sentence-by-sentence substitution for the Korean: merge, split, or reorder clauses whenever natural English cadence calls for it. If `localization_strategy.category` isn't "none", carry out its `notes` concretely — show the behavior the notes describe, not just an abstract label for it.

            Concatenating every passage's `localized_translation` in `passage_id` order must produce the complete, publication-ready chapter — no gaps, no duplicated content, no commentary or meta text mixed into the prose.

            Respond with a single JSON object and nothing else — no markdown code fences, no commentary before or after it. Its shape:

            {
              "localized_passages": [
                { "passage_id": 1, "localized_translation": "string" }
              ]
            }

            ---

            # Reference Material

            #{reference_material(context)}

            #{Pipeline::PromptUtils.section("Cultural Patterns", cultural_patterns)}
          PROMPT
        end

        # Step 4: Fact & culture check. Scoped to facts/names/cultural cues only —
        # deliberately not prose quality, which is step 5's sole job. Reuses the
        # 3-call design's Call 3 discipline of requiring a quoted finding for any
        # negative verdict (that worked: it produced genuine, well-grounded
        # findings during live validation), plus a comparative check against the
        # analysis, since step 3 no longer self-reports whether anything was lost.
        def self.build_factcheck_system_prompt(context, cultural_patterns: "")
          <<~PROMPT.chomp
            You are an independent fact and cultural-consistency reviewer for a Korean-to-English literary translation pipeline intended for potential publishing. You did not write the translation — a separate call produced it from a separate literary analysis. Your only job is to check that nothing factual or culturally load-bearing got lost or changed between the Korean, its analysis, and the English, and that the translation complies with the stated Translation Guidelines — you are not judging prose quality or how natural the English sounds; a separate call handles that.

            The user message gives you, per passage: the original Korean (`anchor_quote`), its literary analysis (`core_message`, `emphasis`, `cultural_signals`, `localization_strategy`), and the English translation (`localized_translation`).

            For each passage, independently answer five boolean checks:
            - `names_preserved`: every character, place, and organization name that appears in the Korean matches the established English spelling for that entity. Check this against the Character Bible / Locations / Terminology sections in the Reference Material below, not just against whether something was rendered from the Korean at all — a self-consistent, Korean-faithful romanization that simply doesn't match the bible's established spelling (e.g. "Jun-ho" vs. a bible entry for "Junho") is still a failure of this check. If a name isn't covered by the Reference Material below or you're unsure of its established form, use the `bible_lookup` tool to check before deciding.
            - `facts_preserved`: every concrete detail — events, promises, threats, numbers, timelines — in the Korean is intact in the English, with nothing invented or dropped.
            - `cultural_significance_preserved`: honorifics, status moves, indirect refusals, face-saving, and other cultural cues identified in `cultural_signals` are still felt in the English, even if not translated literally.
            - `cultural_dynamic_enacted`: true if `localization_strategy.category` is "none", or if it isn't "none" and the English actually carries out the described dynamic rather than just naming it.
            - `style_guidelines_followed`: the passage complies with any explicit, checkable rule stated in the Translation Guidelines section of the Reference Material below — most commonly a stated narration tense (e.g. narration written in present tense when the guidelines require past tense). This is a compliance check against a stated rule, not a subjective judgment of how natural the prose reads, so it belongs here rather than the prose-quality call. Dialogue that intentionally departs from a stated rule to reflect a character's natural speech is not a violation if the guidelines allow for that.

            Also compare the passage's analysis to its English translation directly: if `core_message` or `emphasis` named something important that doesn't show up anywhere in `localized_translation`, that's a missing-coverage problem — flag it as a finding even if it doesn't cleanly fail one of the checks above.

            Any check you mark `false`, and any comparative gap you flag, must have at least one corresponding entry in `findings`, quoting the exact substring of `localized_translation` (or noting its absence) and explaining what's wrong. An empty `findings` array is only valid when every check for that passage is `true` — treat that combination as a claim you're prepared to defend, not a default; go looking for a problem before you settle on it.

            Respond with a single JSON object and nothing else — no markdown code fences, no commentary before or after it. Its shape:

            {
              "reviewed_passages": [
                {
                  "passage_id": 1,
                  "checks": {
                    "names_preserved": true,
                    "facts_preserved": true,
                    "cultural_significance_preserved": true,
                    "cultural_dynamic_enacted": true,
                    "style_guidelines_followed": true
                  },
                  "findings": [
                    { "quote": "string — exact substring from localized_translation", "issue": "string" }
                  ]
                }
              ],
              "review_summary": {
                "summary": "string — one or two sentences on overall factual/cultural fidelity for this chapter"
              }
            }

            ---

            # Reference Material

            #{reference_material(context)}

            #{Pipeline::PromptUtils.section("Cultural Patterns", cultural_patterns)}
          PROMPT
        end

        # Step 5: English editor. The sharpest change from the 3-call design —
        # this call receives ONLY the English text (see build_editor_user_message),
        # no Korean, no analysis, and (unlike steps 1-4) no reference material
        # either. The 3-call design's Call 3 was independent but still had the
        # Korean and analysis in front of it, and live validation showed it could
        # still rubber-stamp a passage by tracing each fragment back to a Korean
        # clause — the same register-mixing failure slipped past both the
        # self-grade and that independent review. A reviewer with no source
        # access can't excuse awkward English by pointing at what it maps to.
        def self.build_editor_system_prompt
          <<~PROMPT.chomp
            You are an independent English-language editor reviewing a literary translation for a novel intended for potential publishing. You do not have access to the Korean source or to any analysis of it, and that is deliberate: your job is to judge whether this reads as natural, coherent, published English prose on its own terms, the way a monolingual editor would, without the ability to excuse awkward phrasing by tracing it back to source meaning.

            The user message gives you the chapter's passages in reading order, each with only its English text (`localized_translation`) — nothing else.

            For each passage, independently answer four boolean checks:
            - `continuous_utterance`: reads as one connected dramatic beat — one person's continuous speech turn, one continuous stretch of narration, or (if more than one person is talking) one coherent back-and-forth exchange — not a string of short, disconnected sentences or exchanges stacked together with no connective flow.
            - `register_unified`: each individual speaker's own tone/register stays consistent across their own lines in the passage — no mixing of, say, a sports-motivational phrase, a courtroom-closing phrase, and internet-slang filler in the same breath from the same person. Different speakers are allowed to have different registers from each other; that's not a violation on its own.
            - `narrative_flow`: the passage moves logically from start to end, and — considering the surrounding passages — doesn't create an abrupt, unmotivated jump in the chapter's flow.
            - `natural_english`: no calques, odd leftover particles ("here"/"so"/"then" doing no real work), or other phrasing that reads as translated rather than written in English.

            Any check you mark `false` must have at least one corresponding entry in `findings`, quoting the exact substring of `localized_translation` that's the problem and explaining what's wrong. An empty `findings` array is only valid when every check for that passage is `true` — treat that combination as a claim you're prepared to defend, not a default; go looking for a problem before you settle on it.

            Respond with a single JSON object and nothing else — no markdown code fences, no commentary before or after it. Its shape:

            {
              "reviewed_passages": [
                {
                  "passage_id": 1,
                  "checks": {
                    "continuous_utterance": true,
                    "register_unified": true,
                    "narrative_flow": true,
                    "natural_english": true
                  },
                  "findings": [
                    { "quote": "string — exact substring from localized_translation", "issue": "string" }
                  ]
                }
              ],
              "review_summary": {
                "summary": "string — one or two sentences on overall prose quality for this chapter"
              }
            }
          PROMPT
        end

        # Assembles Step 2's user message from Step 1's parsed segmentation
        # (a Hash — typically JSON.parse(segmentation_result.output)).
        def self.build_analysis_user_message(segmentation_result:)
          <<~MESSAGE.chomp
            # Segmented Passages

            #{JSON.pretty_generate(segmentation_result)}
          MESSAGE
        end

        # Assembles Step 3's user message from Step 1's segmentation (for
        # anchor_quote) and Step 2's analysis, under distinct headings so the
        # model can address each part of build_localization_system_prompt's
        # instructions unambiguously.
        def self.build_localization_user_message(segmentation_result:, analysis_result:)
          <<~MESSAGE.chomp
            # Segmented Passages (Korean)

            #{JSON.pretty_generate(segmentation_result)}

            # Literary Analysis

            #{JSON.pretty_generate(analysis_result)}
          MESSAGE
        end

        # Assembles Step 4's user message: segmentation, analysis, and Step 3's
        # localized_passages, under distinct headings.
        def self.build_factcheck_user_message(segmentation_result:, analysis_result:, localization_result:)
          <<~MESSAGE.chomp
            # Segmented Passages (Korean)

            #{JSON.pretty_generate(segmentation_result)}

            # Literary Analysis

            #{JSON.pretty_generate(analysis_result)}

            # English Translation

            #{JSON.pretty_generate(localization_result)}
          MESSAGE
        end

        # Assembles Step 5's user message from Step 3's output only. No stripping
        # needed — unlike the 3-call design's Call 3, Step 3's output never
        # contains a self-grade to begin with, so there's nothing to redact.
        def self.build_editor_user_message(localization_result:)
          <<~MESSAGE.chomp
            # Translated Passages

            #{JSON.pretty_generate(localization_result)}
          MESSAGE
        end

        # ---------------------------------------------------------------------
        # Chapter QA (production feature — docs/DECISIONS.md's chapter_qa
        # entry). An independent two-pass review of a chapter's ALREADY-SAVED
        # translation (Chapter#translated_output), not the 5-step eval
        # pipeline above and not sharing its prompts: there's no segmentation
        # or analysis here, just the whole chapter's Korean/English text
        # reviewed as one piece, returning a flat list of suggestions each
        # anchored to an exact quote so a track-changes UI can render it
        # inline. Kept as its own pair of prompts rather than forcing a
        # "one fake passage = whole chapter" shape through
        # build_factcheck_system_prompt/build_editor_system_prompt above,
        # which stay untouched (those review one passage at a time as part
        # of the 5-step chain, offline-eval-only — see the class comment).
        # ---------------------------------------------------------------------

        def self.build_chapter_qa_factcheck_system_prompt(context, cultural_patterns: "")
          <<~PROMPT.chomp
            You are an independent fact and cultural-consistency reviewer for a Korean-to-English literary translation intended for potential publishing. You did not write the translation. Your only job is to check that nothing factual or culturally load-bearing got lost or changed between the Korean source and the English translation, and that the translation complies with the stated Translation Guidelines — you are not judging prose quality or how natural the English sounds; a separate editor pass handles that.

            The user message gives you the whole chapter's Korean source and its English translation, each in full.

            Go through the chapter and flag every place where a name, place, organization, concrete fact (event, promise, threat, number, timeline), or culturally load-bearing cue (honorific, status move, indirect refusal, face-saving gesture) was lost, changed, or flattened between the Korean and the English. For every character, place, and organization name, also check it against the established English spelling in the Character Bible / Locations / Terminology sections of the Reference Material below — a name can be a self-consistent, Korean-faithful romanization and still be wrong if it doesn't match the bible's established spelling for that entity (e.g. "Jun-ho" vs. a bible entry for "Junho"); flag that mismatch even though nothing was "lost" from the Korean. If a name isn't covered by the Reference Material or you're unsure of its established form, use the `bible_lookup` tool to check before deciding.

            Separately, flag any place where the English narration violates an explicit, checkable rule stated in the Translation Guidelines section of the Reference Material below — most commonly a stated narration tense (e.g. narration written in present tense when the guidelines require past tense). This is a compliance check against a stated rule, not a judgment of how natural the prose reads, so it belongs here rather than the editor pass. Dialogue that intentionally departs from a stated rule to reflect a character's natural speech is not a violation if the guidelines allow for that.

            Only flag real problems — an empty `suggestions` array is a claim you're prepared to defend, not a default; go looking for a problem before you settle on finding none.

            For each problem found, respond with:
            - `quote`: the exact substring of the English translation that's the problem — copied verbatim, not paraphrased, since it's used to locate the text.
            - `issue`: what's wrong and why it matters.
            - `suggested_revision`: your proposed replacement text for `quote` — always give a concrete rewrite, never just a description of what should change.
            - `severity`: `"strong"` if the change materially alters meaning, fact, or a load-bearing cultural dynamic; `"advisory"` if it's a smaller fidelity loss that doesn't change what a reader understands to have happened.
            - `korean_context`: the relevant excerpt of Korean source text this finding is based on.

            Respond with a single JSON object and nothing else — no markdown code fences, no commentary before or after it. Its shape:

            {
              "suggestions": [
                { "quote": "string — exact substring from the English translation",
                  "issue": "string",
                  "suggested_revision": "string",
                  "severity": "strong" or "advisory",
                  "korean_context": "string" }
              ]
            }

            ---

            # Reference Material

            #{reference_material(context)}

            #{Pipeline::PromptUtils.section("Cultural Patterns", cultural_patterns)}
          PROMPT
        end

        # Korean-blind by the same deliberate design as build_editor_system_prompt
        # above: no source access, so awkward phrasing can't be excused by
        # tracing it back to what it maps to.
        def self.build_chapter_qa_editor_system_prompt
          <<~PROMPT.chomp
            You are an independent English-language editor reviewing a literary translation for a novel intended for potential publishing. You do not have access to the Korean source, and that is deliberate: your job is to judge whether this reads as natural, coherent, published English prose on its own terms, the way a monolingual editor would, without the ability to excuse awkward phrasing by tracing it back to source meaning.

            The user message gives you the whole chapter's English translation, and nothing else.

            Go through the chapter and flag every place where the prose doesn't read as natural, coherent English: calques and literal-feeling translated phrasing, odd leftover particles doing no real work, misassigned agency, dangling or run-on constructions, redundant or circular phrasing, register that shifts unmotivated within one speaker's own lines, or narrative flow that jumps abruptly between passages. Only flag real problems — an empty `suggestions` array is a claim you're prepared to defend, not a default; go looking for a problem before you settle on finding none.

            For each problem found, respond with:
            - `quote`: the exact substring of the English translation that's the problem — copied verbatim, not paraphrased, since it's used to locate the text.
            - `issue`: what's wrong and why it matters.
            - `suggested_revision`: your proposed replacement text for `quote` — always give a concrete rewrite, never just a description of what should change.
            - `severity`: `"strong"` if the passage is hard to parse or clearly reads as translated; `"advisory"` for smaller polish issues that don't obstruct comprehension.

            Respond with a single JSON object and nothing else — no markdown code fences, no commentary before or after it. Its shape:

            {
              "suggestions": [
                { "quote": "string — exact substring from the English translation",
                  "issue": "string",
                  "suggested_revision": "string",
                  "severity": "strong" or "advisory" }
              ]
            }
          PROMPT
        end

        def self.build_chapter_qa_factcheck_user_message(korean_text:, english_text:)
          <<~MESSAGE.chomp
            # Korean Source

            #{korean_text}

            # English Translation

            #{english_text}
          MESSAGE
        end

        def self.build_chapter_qa_editor_user_message(english_text:)
          <<~MESSAGE.chomp
            # English Translation

            #{english_text}
          MESSAGE
        end

        # Pipeline::BibleEntrySuggestion's one call — fired synchronously from
        # BibleEntrySuggestionsController when a translator Tab-creates a new
        # bible entry from selected English text (see docs/DECISIONS.md's
        # bible-entry-suggestion entry). Scoped to exactly one entry, not a
        # bible_build-style batch pass: given the selected English term, its
        # surrounding context, and the chapter's Korean source, find the
        # Korean equivalent and a small set of type-specific descriptive
        # fields. `fields` is an array of { key:, label:, hint: } — the
        # type-specific field list/labels/hints live in
        # Pipeline::BibleEntrySuggestion::FIELD_SPECS, not here; this method
        # only formats whatever it's given.
        def self.build_bible_entry_suggestion_system_prompt(korean_label:, korean_key:, fields:)
          field_lines = fields.map { |f| "- `#{f[:key]}` (#{f[:label]}): #{f[:hint]}" }.join("\n")
          json_lines  = ([ "\"#{korean_key}\": \"string\"" ] + fields.map { |f| "\"#{f[:key]}\": \"string\"" })
            .join(",\n  ")

          <<~PROMPT.chomp
            You are helping a Korean-to-English literary translator populate one new entry of their translation bible, immediately after they selected an English term in a chapter they're translating or reviewing and chose to add it to the bible. This is scoped to exactly this one entry — you are not reviewing or rebuilding the rest of the bible.

            The user message gives you the selected English text, some surrounding English context it was selected from, and the full Korean source of the chapter it came from.

            First, find the specific Korean word or phrase in the source that the selected English text is the translation of — use the surrounding context to identify the right occurrence if the term appears more than once or in more than one form. Put that in `#{korean_key}` (#{korean_label}).

            Then fill in these fields, grounded only in what the given text actually supports:
            #{field_lines}

            Leave any field you can't determine with reasonable confidence as an empty string — an empty field is fine and expected; a guessed or invented detail is not. Never invent plot, relationships, or facts not evidenced in the given text.

            Respond with a single JSON object and nothing else — no markdown code fences, no commentary before or after it. Its shape:

            {
              #{json_lines}
            }
          PROMPT
        end

        def self.build_bible_entry_suggestion_user_message(english_text:, context_text:, korean_source_text:)
          <<~MESSAGE.chomp
            # Selected English Text

            #{english_text}

            # Surrounding English Context

            #{context_text}

            # Korean Source (full chapter)

            #{korean_source_text}
          MESSAGE
        end

        def self.reference_material(context)
          reference_sections = [
            Pipeline::PromptUtils.section("Novel Info", context.novel_info),
            Pipeline::PromptUtils.section("Translation Guidelines", context.translation_guidelines),
            Pipeline::PromptUtils.section("Voice Calibration", context.voice_calibration),
            Pipeline::PromptUtils.section("Narrator Note", context.narrator_note),
            Pipeline::PromptUtils.section("Character Bible", context.characters),
            Pipeline::PromptUtils.section("Cultural Phrases", context.cultural_phrases),
            Pipeline::PromptUtils.section("Locations", context.locations),
            Pipeline::PromptUtils.section("Story Bible", context.story),
            Pipeline::PromptUtils.section("Terminology", context.terminology)
          ]
          reference_sections.reject(&:empty?).join("\n---\n\n")
        end
        private_class_method :reference_material

        def self.read_file(path)
          File.exist?(path) ? File.read(path, encoding: "UTF-8") : ""
        end
        private_class_method :read_file
      end
    end
  end
end
