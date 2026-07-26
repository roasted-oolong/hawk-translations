require "rails_helper"

RSpec.describe Pipeline::LocalLlmChat do
  def call(base_url: "http://localhost:11434/v1", api_key: "local", model: "qwen2.5:7b",
           max_tokens: 64_000, timeout: 5, **overrides)
    described_class.call(
      system_prompt: overrides.fetch(:system_prompt, "format this"),
      user_message:  overrides.fetch(:user_message, "raw text"),
      base_url:      base_url, api_key: api_key, model: model, max_tokens: max_tokens, timeout: timeout
    )
  end

  describe "a successful call" do
    it "posts the messages/model/max_tokens body and returns the completion content" do
      stub_request(:post, "http://localhost:11434/v1/chat/completions")
        .to_return(status: 200, body: {
          choices: [ { message: { content: "cleaned text" } } ]
        }.to_json, headers: { "Content-Type" => "application/json" })

      result = call(system_prompt: "sys", user_message: "usr")

      expect(result.success?).to eq(true)
      expect(result.output).to eq("cleaned text")

      expect(WebMock).to have_requested(:post, "http://localhost:11434/v1/chat/completions")
        .with(
          headers: { "Authorization" => "Bearer local" },
          body: hash_including(
            "model"      => "qwen2.5:7b",
            "max_tokens" => 64_000,
            "messages"   => [
              { "role" => "system", "content" => "sys" },
              { "role" => "user",   "content" => "usr" }
            ]
          )
        )
    end
  end

  describe "a non-2xx response" do
    it "categorizes as :http_error" do
      stub_request(:post, "http://localhost:11434/v1/chat/completions")
        .to_return(status: 500, body: "internal error")

      result = call

      expect(result.success?).to eq(false)
      expect(result.error_category).to eq(:http_error)
      expect(result.error_message).to include("500")
    end
  end

  describe "an unreachable endpoint" do
    it "categorizes a connection failure as :connection_failed" do
      stub_request(:post, "http://localhost:11434/v1/chat/completions")
        .to_raise(Errno::ECONNREFUSED)

      result = call

      expect(result.success?).to eq(false)
      expect(result.error_category).to eq(:connection_failed)
    end

    it "categorizes a read timeout as :connection_failed" do
      stub_request(:post, "http://localhost:11434/v1/chat/completions")
        .to_raise(Net::ReadTimeout)

      result = call

      expect(result.success?).to eq(false)
      expect(result.error_category).to eq(:connection_failed)
    end
  end

  describe "unparseable output" do
    it "categorizes a non-JSON body as :unparseable_output" do
      stub_request(:post, "http://localhost:11434/v1/chat/completions")
        .to_return(status: 200, body: "not json")

      result = call

      expect(result.success?).to eq(false)
      expect(result.error_category).to eq(:unparseable_output)
    end

    it "categorizes a JSON body missing choices[0].message.content as :unparseable_output" do
      stub_request(:post, "http://localhost:11434/v1/chat/completions")
        .to_return(status: 200, body: { choices: [] }.to_json)

      result = call

      expect(result.success?).to eq(false)
      expect(result.error_category).to eq(:unparseable_output)
    end
  end
end
