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
      response.is_a?(Net::HTTPSuccess) ? "ok" : "unavailable"
    end
  rescue
    "unavailable"
  end

  # Ollama has no dedicated /health route — its root endpoint is a
  # lightweight liveness check (200, plain text "Ollama is running", not
  # JSON). Reachability of the server is what matters here, not whether a
  # model happens to be loaded: models load on demand and unload after
  # OLLAMA_KEEP_ALIVE idle, so "no model resident" is the expected steady
  # state, not something to report as unavailable.
  def health_url
    ENV.fetch("LLM_BASE_URL", "http://localhost:11434/v1").sub(%r{/v1/?$}, "")
  end
end
