require "rails_helper"

RSpec.describe "GET /ai_status", type: :request do
  # Ollama has no dedicated /health route — its root endpoint is a
  # lightweight liveness check (200, plain-text "Ollama is running").
  # Whether a model happens to be loaded isn't a fault: models load on
  # demand and unload after OLLAMA_KEEP_ALIVE idle, so "no model resident"
  # is the expected steady state, not a problem to report as unavailable.
  # Net::HTTP.start(...) { |http| ... } returns the block's own return value —
  # stubbing must preserve that (rather than RSpec's and_yield/and_return,
  # which return whatever and_return says regardless of the block's result),
  # so the stub actually invokes the block like the real method does.
  def stub_http_start(response)
    http = instance_double(Net::HTTP, get: response)
    allow(Net::HTTP).to receive(:start) { |&block| block.call(http) }
  end

  it "returns ok when the LLM root endpoint responds successfully" do
    response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(response).to receive(:body).and_return("Ollama is running")
    stub_http_start(response)

    get ai_status_path, headers: { "Accept" => "application/json" }

    expect(response_json["status"]).to eq("ok")
  end

  it "returns unavailable when the LLM endpoint is unreachable" do
    allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)

    get ai_status_path, headers: { "Accept" => "application/json" }

    expect(response_json["status"]).to eq("unavailable")
  end

  it "returns unavailable when the LLM endpoint responds with a non-success status" do
    stub_http_start(Net::HTTPServiceUnavailable.new("1.1", "503", "Service Unavailable"))

    get ai_status_path, headers: { "Accept" => "application/json" }

    expect(response_json["status"]).to eq("unavailable")
  end

  def response_json
    JSON.parse(response.body)
  end
end
