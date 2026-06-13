require "net/http"

class AiStatusController < ApplicationController
  def show
    render json: { status: ping_llm }
  end

  private

  def ping_llm
    uri = URI(health_url)
    Net::HTTP.start(uri.host, uri.port, open_timeout: 3, read_timeout: 3) do |http|
      response = http.get(uri.path.presence || "/")
      return "unavailable" unless response.is_a?(Net::HTTPSuccess)

      body = JSON.parse(response.body)
      body["status"] == "ok" ? "ok" : "loading"
    end
  rescue
    "unavailable"
  end

  # Strip the /v1 path suffix from LLM_BASE_URL to reach the server root,
  # then append /health. llama-server serves /health at the root, not under /v1.
  def health_url
    base = ENV.fetch("LLM_BASE_URL", "http://localhost:11434/v1")
    base.sub(%r{/v1/?$}, "") + "/health"
  end
end
