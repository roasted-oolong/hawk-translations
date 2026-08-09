# frozen_string_literal: true

# =============================================================================
# BibleSearchService
#
# Hybrid semantic + keyword search across bible embedding records.
# Accepts a novel or organization as the scope, embeds the query via Voyage AI,
# runs pgvector cosine similarity search and tsvector keyword search, merges
# and deduplicates results, and returns a ranked array of result hashes.
#
# Usage:
#   results = BibleSearchService.new(scope: novel, query: "grumpy sunbae mentor").call
#   results = BibleSearchService.new(scope: org,   query: "강혁",
#                                    categories: ["BibleCharacter"], limit: 5).call
#
# Each result hash:
#   {
#     embedding_id:    Integer,
#     embeddable_type: String,
#     embeddable_id:   Integer,
#     novel_id:        Integer,
#     score:           Float,   # combined rank (higher is better)
#     record:          ActiveRecord instance (the actual bible entry)
#   }
#
# Scope:
#   Novel        — searches within that novel only
#   Organization — searches across all novels in the organization
#
# Mode is always hybrid (semantic + keyword). Results from both passes are
# merged on embedding_id; semantic score drives ranking; keyword hits that
# have no semantic match are appended at the end.
#
# Design mirrors PipelineDispatcher / BibleSearchService pattern:
# knows nothing about controllers or HTTP, just data in and results out.
# =============================================================================
class BibleSearchService
  DEFAULT_LIMIT = 10

  # Semantic similarity threshold — embeddings with cosine distance greater
  # than this are excluded. 0.7 is permissive enough for vague queries while
  # filtering truly irrelevant results.
  SIMILARITY_THRESHOLD = 0.7

  # Per-type config for the name-match supplemental query: which table to JOIN
  # and which columns hold the primary name (English + Korean where applicable).
  NAME_ENTRY_CONFIG = {
    "BibleCharacter"      => { table: "bible_characters",       name_cols: %w[name korean_name] },
    "BibleLocation"       => { table: "bible_locations",        name_cols: %w[name korean_name] },
    "BibleTerminology"    => { table: "bible_terminologies",    name_cols: %w[term korean_term] },
    # No English name column — korean_phrase is the whole identity (2026-08-08).
    "BibleCulturalPhrase" => { table: "bible_cultural_phrases", name_cols: %w[korean_phrase]    },
    "BibleStoryEntry"     => { table: "bible_story_entries",    name_cols: %w[title]            },
  }.freeze

  def initialize(scope:, query:, categories: nil, limit: DEFAULT_LIMIT)
    @scope      = scope
    @query      = query.to_s.strip
    @categories = categories
    @limit      = limit.to_i
  end

  def call
    return [] if @query.blank?

    begin
      query_vector     = VoyageClient.embed(@query)
      semantic_results = run_semantic_search(query_vector)
      keyword_results  = run_keyword_search
      merged           = merge_results(semantic_results, keyword_results)
    rescue VoyageClient::ApiError, VoyageClient::ConfigurationError
      # Voyage AI unavailable — fall back to keyword-only search so the
      # feature still works in environments without the API key configured.
      merged = run_keyword_results_only
    end

    prioritize_name_matches(load_records(merged))
  end

  private

  # ---------------------------------------------------------------------------
  # Semantic search — pgvector cosine similarity
  #
  # Uses the <=> operator (cosine distance). Lower distance = more similar.
  # We convert to a similarity score (1 - distance) so higher is better,
  # consistent with the keyword score direction.
  # ---------------------------------------------------------------------------
  def run_semantic_search(query_vector)
    base_scope
      .where("embedding IS NOT NULL")
      .where("1 - (embedding <=> ?) >= ?", query_vector.to_s, SIMILARITY_THRESHOLD)
      .order(Arel.sql("embedding <=> #{ActiveRecord::Base.connection.quote(query_vector.to_s)}"))
      .limit(@limit * 2) # fetch extra before merge dedup
      .pluck(:id, :embeddable_type, :embeddable_id, :novel_id,
             Arel.sql("1 - (embedding <=> #{ActiveRecord::Base.connection.quote(query_vector.to_s)})"))
      .map { |id, type, emb_id, novel_id, score|
        { embedding_id: id, embeddable_type: type, embeddable_id: emb_id,
          novel_id: novel_id, score: score.to_f, source: :semantic }
      }
  end

  # ---------------------------------------------------------------------------
  # Keyword search — tsvector plainto_tsquery
  #
  # Uses 'simple' dictionary so Korean text is matched without stemming.
  # Ranks with ts_rank. Results that also appear in semantic are merged;
  # keyword-only results are appended with a lower base score.
  # ---------------------------------------------------------------------------
  def run_keyword_search
    quoted_query = ActiveRecord::Base.connection.quote(@query)

    base_scope
      .where("search_text IS NOT NULL")
      .where("search_text @@ plainto_tsquery('simple', ?)", @query)
      .order(Arel.sql("ts_rank(search_text, plainto_tsquery('simple', #{quoted_query})) DESC"))
      .limit(@limit * 2)
      .pluck(:id, :embeddable_type, :embeddable_id, :novel_id,
             Arel.sql("ts_rank(search_text, plainto_tsquery('simple', #{quoted_query}))"))
      .map { |id, type, emb_id, novel_id, rank|
        { embedding_id: id, embeddable_type: type, embeddable_id: emb_id,
          novel_id: novel_id, score: rank.to_f, source: :keyword }
      }
  end

  # Keyword-only path used when Voyage AI is unavailable.
  # Returns results in the same shape as merge_results so load_records works.
  def run_keyword_results_only
    run_keyword_search
  end

  # ---------------------------------------------------------------------------
  # Merge semantic + keyword results
  #
  # Records that appear in both lists get their scores summed (semantic score
  # dominates since it's on a 0–1 scale; keyword ts_rank is 0–1 as well but
  # typically lower). Semantic-only and merged results are sorted by score
  # descending. Keyword-only results are appended at the end, also sorted.
  # Final list is trimmed to @limit.
  # ---------------------------------------------------------------------------
  def merge_results(semantic, keyword)
    by_id = {}

    semantic.each do |r|
      by_id[r[:embedding_id]] = r.dup
    end

    keyword.each do |r|
      if by_id.key?(r[:embedding_id])
        by_id[r[:embedding_id]][:score] += r[:score]
        by_id[r[:embedding_id]][:source] = :hybrid
      else
        by_id[r[:embedding_id]] = r.merge(source: :keyword_only)
      end
    end

    primary   = by_id.values.reject { |r| r[:source] == :keyword_only }
                             .sort_by { |r| -r[:score] }
    secondary = by_id.values.select { |r| r[:source] == :keyword_only }
                             .sort_by { |r| -r[:score] }

    (primary + secondary).first(@limit)
  end

  # ---------------------------------------------------------------------------
  # Load the actual bible entry records for each result.
  # Groups by embeddable_type to do one query per model class.
  # ---------------------------------------------------------------------------
  def load_records(merged)
    return [] if merged.empty?

    # Group result entries by their model class name
    by_type = merged.group_by { |r| r[:embeddable_type] }

    # Build a lookup: "ClassName:id" => record
    record_lookup = {}
    by_type.each do |type, results|
      klass = type.constantize
      ids   = results.map { |r| r[:embeddable_id] }
      klass.where(id: ids).each do |rec|
        record_lookup["#{type}:#{rec.id}"] = rec
      end
    end

    # Attach records to result hashes; drop any whose record was deleted
    merged.filter_map do |r|
      record = record_lookup["#{r[:embeddable_type]}:#{r[:embeddable_id]}"]
      next if record.nil?
      r.merge(record: record).except(:source)
    end
  end

  # ---------------------------------------------------------------------------
  # Name-match prioritisation
  #
  # Two-stage process:
  #
  # 1. Supplemental fetch — runs a LIKE query against each bible entry table to
  #    find records whose primary name/term/phrase contains the query string.
  #    Any such records not already in the result pool are loaded and added.
  #    This is necessary because long profiles have low ts_rank even when the
  #    query matches the entry's own name exactly.
  #
  # 2. Word-aware boost — re-scores the combined set using whitespace-tokenised
  #    name matching so that an entry NAMED "Yumi" ranks above one whose title
  #    merely starts with "Yumi" (e.g. "Yumi's F.M.P.").
  #
  # Boost tiers (applied on top of existing score):
  #   +3.0  all query words are exact whitespace tokens in the name AND the full
  #          query phrase appears as a substring — strongest signal
  #   +2.5  all query words are exact tokens (word-order variant, e.g. Korean)
  #   +1.5  any query word is an exact token in the name
  #   +1.0  any query word is a prefix of a name token ("Yumi" → "Yumi's …")
  #   +0.5  any query word appears anywhere as a substring (fallback)
  # ---------------------------------------------------------------------------
  def prioritize_name_matches(results)
    query_lower = @query.downcase
    query_words = query_lower.split.select { |w| w.length >= 2 }
    return results if query_words.empty?

    # Stage 1 — add any name-matching entries missing from the pool
    existing_ids = results.map { |r| r[:embedding_id] }.to_set
    extras       = load_records(
      fetch_name_match_embeddings.reject { |r| existing_ids.include?(r[:embedding_id]) }
    )

    # Stage 2 — apply word-aware boost to the full combined set and re-rank
    (results + extras)
      .map { |r|
        boost = name_boost(entry_name(r[:record], r[:embeddable_type]).downcase,
                           query_lower, query_words)
        boost > 0 ? r.merge(score: r[:score] + boost) : r
      }
      .sort_by { |r| -r[:score] }
      .first(@limit)
  end

  def name_boost(name, query_lower, query_words)
    name_tokens = name.split
    if query_words.all? { |w| name_tokens.include?(w) }
      name.include?(query_lower) ? 3.0 : 2.5
    elsif query_words.any? { |w| name_tokens.include?(w) }
      1.5
    elsif query_words.any? { |w| name_tokens.any? { |t| t.start_with?(w) } }
      1.0
    elsif query_words.any? { |w| name.include?(w) }
      0.5
    else
      0.0
    end
  end

  # Runs a LIKE query against each bible entry table for the current query.
  # Returns embedding-shaped hashes (score 0.0) ready for load_records.
  def fetch_name_match_embeddings
    pattern = "%#{@query.downcase.gsub(/[%_\\]/) { |c| "\\#{c}" }}%"

    NAME_ENTRY_CONFIG.flat_map do |type, cfg|
      next [] if @categories.present? && !@categories.include?(type)

      table = cfg[:table]
      cond  = cfg[:name_cols].map { |c| "LOWER(#{table}.#{c}) LIKE ?" }.join(" OR ")

      base_scope
        .where(embeddable_type: type)
        .joins("INNER JOIN #{table} ON #{table}.id = bible_embeddings.embeddable_id")
        .where(cond, *Array.new(cfg[:name_cols].size, pattern))
        .limit(@limit)
        .pluck("bible_embeddings.id", "bible_embeddings.embeddable_type",
               "bible_embeddings.embeddable_id", "bible_embeddings.novel_id")
        .map { |id, t, emb_id, nid|
          { embedding_id: id, embeddable_type: t, embeddable_id: emb_id,
            novel_id: nid, score: 0.0, source: :name_match }
        }
    end
  end

  def entry_name(record, type)
    case type
    when "BibleCharacter", "BibleLocation" then "#{record.name} #{record.korean_name}"
    when "BibleTerminology"                then "#{record.term} #{record.korean_term}"
    when "BibleCulturalPhrase"             then record.korean_phrase.to_s
    when "BibleStoryEntry"                 then record.title.to_s
    else ""
    end
  end

  # ---------------------------------------------------------------------------
  # Base scope — applies novel or org scoping and optional category filter
  # ---------------------------------------------------------------------------
  def base_scope
    scope = case @scope
            when Novel        then BibleEmbedding.for_novel(@scope)
            when Organization then BibleEmbedding.for_organization(@scope)
            else
              raise ArgumentError,
                    "scope must be a Novel or Organization, got #{@scope.class}"
            end

    scope = scope.for_categories(@categories) if @categories.present?
    scope
  end
end
