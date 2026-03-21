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

  def initialize(scope:, query:, categories: nil, limit: DEFAULT_LIMIT)
    @scope      = scope
    @query      = query.to_s.strip
    @categories = categories
    @limit      = limit.to_i
  end

  def call
    return [] if @query.blank?

    query_vector = VoyageClient.embed(@query)

    semantic_results = run_semantic_search(query_vector)
    keyword_results  = run_keyword_search

    merged = merge_results(semantic_results, keyword_results)
    load_records(merged)
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
