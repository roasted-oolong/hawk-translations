# frozen_string_literal: true

# =============================================================================
# BibleSearchController
#
# API-first search endpoint. Returns JSON only — no HTML views.
# Authentication is enforced via ApplicationController's before_action.
#
# Routes:
#   GET /novels/:novel_id/bible/search
#
# Query parameters:
#   q          String  — search query (required; blank returns empty results)
#   categories Array   — optional filter e.g. categories[]=BibleCharacter
#   limit      Integer — max results to return (default: 10, max: 50)
#
# Response shape:
#   200 { "results": [ { embeddable_type, embeddable_id, novel_id, score,
#                        record: { ...fields } } ] }
#   503 { "error": "..." }  — on VoyageClient::ApiError
#   404                     — novel not found
# =============================================================================
class BibleSearchController < ApplicationController
  before_action :set_novel

  MAX_LIMIT = 50

  def show
    results = BibleSearchService.new(
      scope:      @novel,
      query:      params[:q].to_s,
      categories: categories_param,
      limit:      limit_param
    ).call

    render json: { results: serialize_results(results) }
  rescue VoyageClient::ApiError, VoyageClient::ConfigurationError => e
    render json: { error: "Search unavailable: #{e.message}" },
           status: :service_unavailable
  end

  private

  def set_novel
    @novel = Novel.find(params[:novel_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Novel not found" }, status: :not_found
  end

  def categories_param
    raw = params[:categories]
    return nil if raw.blank?
    Array(raw).map(&:to_s).presence
  end

  def limit_param
    requested = params[:limit].to_i
    return BibleSearchService::DEFAULT_LIMIT if requested <= 0
    [ requested, MAX_LIMIT ].min
  end

  # Serialize each result to a plain hash safe for JSON rendering.
  # The record is serialized via #attributes so all fields are included
  # without needing a separate serializer class for each bible type.
  def serialize_results(results)
    results.map do |r|
      {
        embeddable_type: r[:embeddable_type],
        embeddable_id:   r[:embeddable_id],
        novel_id:        r[:novel_id],
        score:           r[:score].round(4),
        record:          r[:record].attributes.except("search_text")
      }
    end
  end
end
