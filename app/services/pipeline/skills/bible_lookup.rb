# ---------------------------------------------------------------------------
# Pipeline::Skills::BibleLookup
#
# Ruby port of src/skills/bible_lookup.py, per R2 in
# docs/RAILS_REFACTOR_PLAN.md. Replaces the two HTTP round trips the Python
# skill made against this same Rails app (find_by_directory, bible/search)
# with direct Ruby calls — Novel.find_by! and BibleSearchService's public
# API — so there is no HTTP hop at all, not even to this app's own routes.
#
# Instance-based, one fresh instance per call site (mirrors
# translate.py/translate_batch.py instantiating the Python skill inline,
# never as a shared singleton). Never shared across concurrent jobs. Novel
# resolution is memoized on this instance only (@novel), not a class
# variable or any process-wide cache.
# ---------------------------------------------------------------------------
module Pipeline
  module Skills
    class BibleLookup
      include Pipeline::Skill

      CATEGORY_LABELS = {
        "BibleCharacter"      => "Character",
        "BibleLocation"       => "Location",
        "BibleTerminology"    => "Terminology",
        "BibleCulturalPhrase" => "Cultural Phrase",
        "BibleStoryEntry"     => "Story Entry"
      }.freeze

      SEARCH_LIMIT = 5

      def initialize(novel_directory_name:)
        @novel_directory_name = novel_directory_name
        @novel = nil
      end

      def tool_definition
        {
          type: "function",
          function: {
            name: "bible_lookup",
            description: (
              "Look up entries in the translation bible to check established " \
              "character names, locations, terminology, cultural phrases, and " \
              "story context. Use this when you encounter a name, term, or " \
              "reference in the source text and want to check how it has been " \
              "translated or documented."
            ),
            parameters: {
              type: "object",
              properties: {
                query: {
                  type: "string",
                  description: "The name, term, or phrase to look up. Can be in English or Korean."
                },
                categories: {
                  type: "array",
                  items: { type: "string", enum: CATEGORY_LABELS.keys },
                  description: "Optional — narrow results to specific entry types."
                }
              },
              required: [ "query" ]
            }
          }
        }
      end

      # Always returns a String, never raises — the string is the model-
      # facing compatibility layer, not an implementation afterthought.
      def execute(tool_args)
        args = tool_args.with_indifferent_access
        query = args[:query].to_s.strip
        return "[bible_lookup error: empty query]" if query.blank?

        novel = begin
          resolve_novel
        rescue ActiveRecord::RecordNotFound => e
          return "[bible_lookup error: could not resolve novel — #{e.message}]"
        end

        categories = Array(args[:categories]).map(&:to_s).presence

        results = begin
          BibleSearchService.new(scope: novel, query: query, categories: categories, limit: SEARCH_LIMIT).call
        rescue StandardError => e
          return "[bible_lookup error: #{e.message}]"
        end

        return "No bible entries found for: #{query}" if results.empty?

        format_results(results)
      end

      private

      def resolve_novel
        @novel ||= Novel.find_by!(directory_name: @novel_directory_name)
      end

      # One formatter per category (a future per-category class extraction
      # stays available without this comment implying it's owed now — the
      # current single method is perfectly reasonable at this size). Output
      # here is part of the model-facing interface: it's the exact text the
      # translation prompt sees when the model calls this tool.
      def format_results(results)
        results.map { |r|
          label = CATEGORY_LABELS.fetch(r[:embeddable_type], r[:embeddable_type])
          "[#{label}]\n#{format_record(r[:embeddable_type], r[:record])}"
        }.join("\n\n")
      end

      def format_record(type, record)
        case type
        when "BibleCharacter"
          lines(
            [ "Name", record.name ],
            [ "Korean name", record.korean_name ],
            [ "Aliases", record.aliases ],
            [ "Role", record.role ],
            [ "Significance", record.significance ],
            [ "Physical description", record.physical_description ],
            [ "Speech pattern", record.speech_pattern ],
            [ "Honorifics used toward", record.honorifics_used_toward ],
            [ "Honorifics they use", record.honorifics_they_use ],
            [ "Relationships", record.relationships ],
            [ "Notes", record.notes ]
          )
        when "BibleLocation"
          lines(
            [ "Name", record.name ],
            [ "Korean name", record.korean_name ],
            [ "Type", record.location_type ],
            [ "Description", record.description ],
            [ "Significance", record.significance ],
            [ "Notes", record.notes ]
          )
        when "BibleTerminology"
          lines(
            [ "Term", record.term ],
            [ "Korean term", record.korean_term ],
            [ "Definition", record.definition ],
            [ "Usage notes", record.usage_notes ],
            [ "Notes", record.notes ]
          )
        when "BibleCulturalPhrase"
          lines(
            [ "Phrase", record.phrase ],
            [ "Korean phrase", record.korean_phrase ],
            [ "Literal translation", record.literal_translation ],
            [ "Intended meaning", record.intended_meaning ],
            [ "Context", record.context ],
            [ "Established translation", record.established_translation ],
            [ "Notes", record.notes ]
          )
        when "BibleStoryEntry"
          lines(
            [ "Title", record.title ],
            [ "Category", record.category ],
            [ "Content", record.content ],
            [ "Notes", record.notes ]
          )
        else
          # Unreachable given the category enum is closed to the five above
          # (R2 acceptance criteria) — never raises even so.
          ""
        end
      end

      def lines(*pairs)
        pairs.reject { |_, value| value.blank? }
             .map { |label, value| "#{label}: #{value}" }
             .join("\n")
      end
    end
  end
end
