# frozen_string_literal: true

# =============================================================================
# Idols Rewind — Bible Import Script
# =============================================================================
#
# One-time import of idols-rewind markdown bible files into the database.
#
# Run with:
#   rails runner db/import/idols_rewind_bible.rb
#
# Idempotent: uses find_or_create_by! for the novel/org records, and skips
# any bible entry whose primary key field already exists for this novel.
# Safe to re-run — it will not create duplicates, but it will not overwrite
# manually edited records either.
#
# =============================================================================

BIBLE_DIR = Rails.root.join("idols-rewind", "bible")

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

def log(msg)
  puts "[import] #{msg}"
end

# Strip surrounding whitespace; return nil if blank.
# Named presence_str to avoid collision with ActiveSupport's Object#presence.
def presence_str(str)
  val = str&.strip
  val&.empty? ? nil : val
end

# Parse an integer from a string; return nil if not a valid positive integer.
def parse_chapter(str)
  return nil unless str
  int = str.strip.to_i
  int > 0 ? int : nil
end

# Given a raw block of "- Key: Value\n- Key: Value\n..." lines,
# return a hash keyed by normalised field name.
def parse_fields(block)
  fields = {}
  current_key = nil

  block.each_line do |line|
    # Field line: "- Key: Value" or "- Key:"
    if (m = line.match(/^- ([^:]+):\s*(.*)/))
      current_key = m[1].strip.downcase.gsub(/[\s\/]+/, "_")
      fields[current_key] = m[2].strip
    elsif current_key && line.match(/^\s{2,}/)
      # Continuation of a multi-line value (indented)
      fields[current_key] = "#{fields[current_key]}\n#{line.rstrip}"
    end
  end

  fields
end

# -----------------------------------------------------------------------------
# Seed: Organization + Novel
# -----------------------------------------------------------------------------

log "Setting up organization and novel..."

org = Organization.find_or_create_by!(name: "Hawk Translations") do |o|
  log "  Created organization: #{o.name}"
end

novel = Novel.find_or_create_by!(
  organization: org,
  title: "Idols Rewind"
) do |n|
  n.directory_name = "idols-rewind"
  n.korean_title   = "다시 키우는 걸그룹"
  n.genre          = "Idol industry / regression / music & performance"
  n.summary        = "A former top-tier talent manager who lost everything gets a second chance " \
                     "when he wakes up back in the past. Hyuk Kang had the sharpest eye in the " \
                     "industry — he could read talent, character, and potential better than anyone — " \
                     "but integrity alone couldn't protect him from the people with real power. His " \
                     "independent agency failed, his artists scattered, and years later he's living " \
                     "in a rooftop room with nothing to show for it. Then the full moon shimmers " \
                     "strangely overhead, and he wakes up with everything to do over. This time, he " \
                     "knows exactly what mistakes not to make."
  n.tone           = "Dry, introspective, and bittersweet. The internal monologue is sharp and " \
                     "self-deprecating with quiet humor. Confident pacing — emotional without being " \
                     "melodramatic."
  n.visibility     = "discoverable"
  log "  Created novel: #{n.title}"
end

# Backfill directory_name for records created before this column existed.
# Safe to re-run — no-op if already set.
if novel.directory_name.blank?
  novel.update!(directory_name: "idols-rewind")
  log "  Backfilled directory_name: idols-rewind"
end

log "Novel: #{novel.title} (id: #{novel.id})"

# -----------------------------------------------------------------------------
# Characters
# -----------------------------------------------------------------------------

log "\nImporting characters..."

characters_md = File.read(BIBLE_DIR.join("characters.md"))

# Each character block starts at "## Name" and runs until the next "---" or
# end of file. We split on the horizontal rule separator.
character_blocks = characters_md.split(/^---+\s*$/).map(&:strip).reject(&:empty?)

imported = 0
skipped  = 0

character_blocks.each do |block|
  # Must start with a ## heading
  next unless (heading_match = block.match(/^##\s+(.+)/))

  heading      = heading_match[1].strip
  fields_block = block.sub(/^##\s+.+\n/, "")
  fields       = parse_fields(fields_block)

  # Derive the English name from the heading — strip the Korean parenthetical.
  # e.g. "Hyuk Kang (강혁)" → "Hyuk Kang"
  english_name = heading.sub(/\s*\([^)]+\)\s*$/, "").strip
  korean_name  = presence_str(fields["korean_name"])

  next if english_name.empty?

  if novel.bible_characters.exists?(name: english_name)
    log "  SKIP character already exists: #{english_name}"
    skipped += 1
    next
  end

  # Map markdown field names → column names
  # Markdown uses "honorifics used toward them" and "honorifics they use toward others"
  honorifics_toward = presence_str(
    fields["honorifics_used_toward_them"] ||
    fields["honorifics_used_toward"]
  )
  honorifics_use = presence_str(
    fields["honorifics_they_use_toward_others"] ||
    fields["honorifics_they_use"]
  )

  # Merge "dialogue cues" into speech_pattern notes (no separate column)
  speech = [ presence_str(fields["speech_pattern"]), presence_str(fields["dialogue_cues"]) ]
            .compact.join("\n\nDialogue cues: ")
  speech = presence_str(speech)

  novel.bible_characters.create!(
    name:                     english_name,
    korean_name:              korean_name,
    aliases:                  presence_str(fields["aliases_titles"] || fields["aliases"]),
    role:                     presence_str(fields["role"]),
    significance:             presence_str(fields["significance"]),
    physical_description:     presence_str(fields["physical_description"]),
    speech_pattern:           speech,
    honorifics_used_toward:   honorifics_toward,
    honorifics_they_use:      honorifics_use,
    relationships:            presence_str(fields["relationships"]),
    first_appearance_chapter: parse_chapter(fields["first_appearance"]),
    notes:                    presence_str(fields["notes"])
  )

  log "  + #{english_name}"
  imported += 1
end

log "Characters: #{imported} imported, #{skipped} skipped."

# -----------------------------------------------------------------------------
# Locations
# -----------------------------------------------------------------------------

log "\nImporting locations..."

locations_md = File.read(BIBLE_DIR.join("locations.md"))
location_blocks = locations_md.split(/^---+\s*$/).map(&:strip).reject(&:empty?)

imported = 0
skipped  = 0

location_blocks.each do |block|
  next unless (heading_match = block.match(/^##\s+(.+)/))

  heading      = heading_match[1].strip
  fields_block = block.sub(/^##\s+.+\n/, "")
  fields       = parse_fields(fields_block)

  # Strip any trailing Korean parenthetical from the heading for the English name
  english_name = heading.sub(/\s*\([^)]+\)\s*$/, "").strip

  next if english_name.empty?

  if novel.bible_locations.exists?(name: english_name)
    log "  SKIP location already exists: #{english_name}"
    skipped += 1
    next
  end

  novel.bible_locations.create!(
    name:                     english_name,
    korean_name:              presence_str(fields["korean_name"]),
    location_type:            presence_str(fields["type"]),
    description:              presence_str(fields["description"]),
    significance:             presence_str(fields["significance"]),
    first_appearance_chapter: parse_chapter(fields["first_appearance"]),
    notes:                    presence_str(fields["notes"])
  )

  log "  + #{english_name}"
  imported += 1
end

log "Locations: #{imported} imported, #{skipped} skipped."

# -----------------------------------------------------------------------------
# Terminology
# -----------------------------------------------------------------------------

log "\nImporting terminology..."

terminology_md = File.read(BIBLE_DIR.join("terminology.md"))
term_blocks = terminology_md.split(/^---+\s*$/).map(&:strip).reject(&:empty?)

imported = 0
skipped  = 0

term_blocks.each do |block|
  next unless (heading_match = block.match(/^##\s+(.+)/))

  heading      = heading_match[1].strip
  fields_block = block.sub(/^##\s+.+\n/, "")
  fields       = parse_fields(fields_block)

  # Heading is the English term name. Strip Korean parenthetical if present.
  term_name = heading.sub(/\s*\([^)]+\)\s*$/, "").strip
  # Also strip trailing " — English [New]" or " [Edited]" editorial markers
  term_name = term_name.sub(/\s+—\s+English\s+\[.+?\]\s*$/, "")
                       .sub(/\s+\[.+?\]\s*$/, "")
                       .strip

  next if term_name.empty?
  # Skip the template placeholder block
  next if term_name == "[Term]"

  if novel.bible_terminologies.exists?(term: term_name)
    log "  SKIP term already exists: #{term_name}"
    skipped += 1
    next
  end

  novel.bible_terminologies.create!(
    term:                     term_name,
    korean_term:              presence_str(fields["korean_term"]),
    definition:               presence_str(fields["definition"]),
    usage_notes:              presence_str(fields["usage_notes"]),
    first_appearance_chapter: parse_chapter(fields["first_appearance"]),
    notes:                    presence_str(fields["notes"])
  )

  log "  + #{term_name}"
  imported += 1
end

log "Terminology: #{imported} imported, #{skipped} skipped."

# -----------------------------------------------------------------------------
# Cultural Phrases
# -----------------------------------------------------------------------------

log "\nImporting cultural phrases..."

phrases_md = File.read(BIBLE_DIR.join("cultural_phrases.md"))
phrase_blocks = phrases_md.split(/^---+\s*$/).map(&:strip).reject(&:empty?)

imported = 0
skipped  = 0

phrase_blocks.each do |block|
  next unless (heading_match = block.match(/^##\s+(.+)/))

  heading      = heading_match[1].strip
  fields_block = block.sub(/^##\s+.+\n/, "")
  fields       = parse_fields(fields_block)

  # Strip editorial markers (" — English [New]", " [Edited]", etc.)
  phrase_name = heading.sub(/\s+—\s+English\s+\[.+?\]\s*$/, "")
                       .sub(/\s+\[.+?\]\s*$/, "")
                       .strip

  next if phrase_name.empty?
  # Skip the template placeholder block
  next if phrase_name == "[Phrase]"

  if novel.bible_cultural_phrases.exists?(phrase: phrase_name)
    log "  SKIP phrase already exists: #{phrase_name}"
    skipped += 1
    next
  end

  novel.bible_cultural_phrases.create!(
    phrase:                   phrase_name,
    korean_phrase:            presence_str(fields["korean_phrase"]),
    literal_translation:      presence_str(fields["literal_translation"]),
    intended_meaning:         presence_str(fields["intended_meaning"]),
    context:                  presence_str(fields["context"]),
    established_translation:  presence_str(fields["established_translation"]),
    first_appearance_chapter: parse_chapter(fields["first_appearance"]),
    notes:                    presence_str(fields["notes"])
  )

  log "  + #{phrase_name}"
  imported += 1
end

log "Cultural phrases: #{imported} imported, #{skipped} skipped."

# -----------------------------------------------------------------------------
# Story Entries
# -----------------------------------------------------------------------------
#
# story.md uses a different pattern from the other files. Actual content entries
# are freeform bold-labelled blocks like:
#
#   **Main Plot** — Chapter 1 establishes...
#   **Subplot** — Hee-yeon's visit thread...
#   **Watch List** — Director Park's threat...
#   **Themes & Motifs** — Regret and second chances...
#
# Each is a single paragraph. We also parse the structured "Open arcs",
# "Watch list:", and "Translation-relevant context:" sections near the top.
#
# Category mapping:
#   **Main Plot**        → main_plot
#   **Subplot**          → subplot
#   **Watch List**       → watch_list
#   **Themes & Motifs**  → theme
#   World Building       → world_building (template only, no content to import)
# -----------------------------------------------------------------------------

log "\nImporting story entries..."

story_md = File.read(BIBLE_DIR.join("story.md"))

imported = 0
skipped  = 0

STORY_CATEGORY_MAP = {
  /^main\s+plot$/i            => "main_plot",
  /^subplot$/i                => "subplot",
  /^watch\s+list$/i           => "watch_list",
  /^themes?\s*&?\s*motifs?$/i => "theme",
  /^world\s+building$/i       => "world_building"
}.freeze

def map_story_category(label)
  STORY_CATEGORY_MAP.each do |pattern, cat|
    return cat if label.match?(pattern)
  end
  nil
end

# --- Parse the "Open arcs" bullet list as a single main_plot entry ---
if (arcs_match = story_md.match(/\*\*Open arcs:\*\*\s*\n((?:- .+\n?)+)/))
  arcs_content = arcs_match[1].strip
  title = "Open Arcs"

  if novel.bible_story_entries.exists?(category: "main_plot", title: title)
    log "  SKIP story entry already exists: #{title}"
    skipped += 1
  else
    novel.bible_story_entries.create!(
      category: "main_plot",
      title:    title,
      content:  arcs_content
    )
    log "  + main_plot: #{title}"
    imported += 1
  end
end

# --- Parse the "Watch list:" bullet list as watch_list entries (one entry) ---
if (wl_match = story_md.match(/\*\*Watch list:\*\*\s*\n((?:- .+\n?)+)/))
  wl_content = wl_match[1].strip
  title = "Watch List Notes"

  if novel.bible_story_entries.exists?(category: "watch_list", title: title)
    log "  SKIP story entry already exists: #{title}"
    skipped += 1
  else
    novel.bible_story_entries.create!(
      category: "watch_list",
      title:    title,
      content:  wl_content
    )
    log "  + watch_list: #{title}"
    imported += 1
  end
end

# --- Parse the "Translation-relevant context:" bullet list as a main_plot note ---
if (ctx_match = story_md.match(/\*\*Translation-relevant context:\*\*\s*\n((?:- .+\n?)+)/))
  ctx_content = ctx_match[1].strip
  title = "Translation-Relevant Context"

  if novel.bible_story_entries.exists?(category: "main_plot", title: title)
    log "  SKIP story entry already exists: #{title}"
    skipped += 1
  else
    novel.bible_story_entries.create!(
      category: "main_plot",
      title:    title,
      content:  ctx_content
    )
    log "  + main_plot: #{title}"
    imported += 1
  end
end

# --- Parse the freeform bold-labelled paragraph entries ---
# Pattern: **Category Label** — Content paragraph
# These appear after the horizontal rules in the lower portion of the file.
story_md.scan(/^\*\*([^*]+)\*\*\s+[—–-]\s+(.+?)(?=\n\n|\n---|\z)/m) do |label, content|
  label   = label.strip
  content = content.strip.gsub(/\s+/, " ")

  category = map_story_category(label)
  next unless category

  # Build a short title from the first sentence or first ~60 chars of content
  first_sentence = content.split(/[.!?]/).first.to_s.strip
  title = first_sentence.length <= 80 ? first_sentence : "#{first_sentence[0, 77]}..."
  # Fallback: use label + a counter if title is still empty
  title = label if title.empty?

  if novel.bible_story_entries.exists?(category: category, title: title)
    log "  SKIP story entry already exists: #{title}"
    skipped += 1
    next
  end

  novel.bible_story_entries.create!(
    category: category,
    title:    title,
    content:  content
  )
  log "  + #{category}: #{title[0, 60]}"
  imported += 1
end

log "Story entries: #{imported} imported, #{skipped} skipped."

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

log "\n== Import complete =="
log "  Bible characters:    #{novel.bible_characters.count}"
log "  Bible locations:     #{novel.bible_locations.count}"
log "  Bible terminologies: #{novel.bible_terminologies.count}"
log "  Bible phrases:       #{novel.bible_cultural_phrases.count}"
log "  Bible story entries: #{novel.bible_story_entries.count}"
