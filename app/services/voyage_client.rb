# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

# =============================================================================
# VoyageClient
#
# Thin wrapper around the Voyage AI embeddings API.
# Responsible for one thing: take a string, return a 1024-dimension vector.
#
# Model: voyage-3-lite — Anthropic's recommended embedding partner model.
# Dimensions: 1024 (matches vector(1024) column in bible_embeddings).
#
# API key read from Rails credentials under :voyage_api_key.
# Raises typed errors so callers can handle API and config failures cleanly.
#
# Usage:
#   vector = VoyageClient.embed("Hyuk Kang 강혁 former talent manager")
#   # => [0.023, -0.041, ...] (1024 floats)
#
# Design: mirrors PipelineDispatcher's pattern — thin wrapper, no knowledge
# of models or jobs, typed errors, easy to stub in specs via WebMock.
# =============================================================================
class VoyageClient
  API_URL = "https://api.voyageai.com/v1/embeddings"
  MODEL   = "voyage-3-lite"

  # ---------------------------------------------------------------------------
  # Errors
  # ---------------------------------------------------------------------------

  # Raised when the Voyage AI API returns a non-2xx response or a network
  # error occurs. Message includes HTTP status when available.
  class ApiError < StandardError; end

  # Raised at call time when voyage_api_key is absent from credentials.
  # Fail loudly rather than sending an unauthenticated request.
  class ConfigurationError < StandardError; end

  # ---------------------------------------------------------------------------
  # Public interface
  # ---------------------------------------------------------------------------

  def self.embed(text)
    new.embed(text)
  end

  def embed(text)
    validate_config!

    response = post_request(text)
    handle_response(response)
  end

  private

  # ---------------------------------------------------------------------------
  # HTTP
  # ---------------------------------------------------------------------------

  def post_request(text)
    uri  = URI(API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.path)
    request["Content-Type"]  = "application/json"
    request["Authorization"] = "Bearer #{api_key}"
    request.body = JSON.generate({ model: MODEL, input: [ text ] })

    http.request(request)
  rescue => e
    raise ApiError, "Network error calling Voyage AI: #{e.class}: #{e.message}"
  end

  def handle_response(response)
    unless response.is_a?(Net::HTTPSuccess)
      raise ApiError,
            "Voyage AI API returned #{response.code}: #{response.body.truncate(200)}"
    end

    parsed = JSON.parse(response.body)
    parsed.dig("data", 0, "embedding") or
      raise ApiError, "Voyage AI response missing embedding data: #{response.body.truncate(200)}"
  end

  # ---------------------------------------------------------------------------
  # Config
  # ---------------------------------------------------------------------------

  def validate_config!
    return if api_key.present?

    raise ConfigurationError,
          "voyage_api_key is not set in Rails credentials. " \
          "Add it with: rails credentials:edit"
  end

  def api_key
    Rails.application.credentials.voyage_api_key
  end
end
