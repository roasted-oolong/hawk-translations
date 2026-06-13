# frozen_string_literal: true

require "rails_helper"

RSpec.describe VoyageClient do
  # ---------------------------------------------------------------------------
  # Shared test data
  # ---------------------------------------------------------------------------
  let(:api_key)   { "test-voyage-key" }
  let(:input_text) { "Hyuk Kang 강혁 Protagonist former top-tier talent manager" }
  let(:fake_vector) { Array.new(512) { rand } }

  let(:success_response_body) do
    {
      "object" => "list",
      "data"   => [ { "object" => "embedding", "embedding" => fake_vector, "index" => 0 } ],
      "model"  => "voyage-3-lite",
      "usage"  => { "total_tokens" => 42 }
    }.to_json
  end

  before do
    allow(Rails.application.credentials).to receive(:voyage_api_key).and_return(api_key)
  end

  describe ".embed" do
    context "on success" do
      before do
        stub_request(:post, "https://api.voyageai.com/v1/embeddings")
          .to_return(status: 200, body: success_response_body,
                     headers: { "Content-Type" => "application/json" })
      end

      it "returns an array of floats with 512 dimensions" do
        result = VoyageClient.embed(input_text)
        expect(result).to be_an(Array)
        expect(result.length).to eq(512)
        expect(result).to all(be_a(Numeric))
      end

      it "sends the correct model and input in the request body" do
        VoyageClient.embed(input_text)
        expect(WebMock).to have_requested(:post, "https://api.voyageai.com/v1/embeddings")
          .with { |req|
            body = JSON.parse(req.body)
            body["model"] == "voyage-3-lite" && body["input"] == [ input_text ]
          }
      end

      it "sends the Authorization header with the API key" do
        VoyageClient.embed(input_text)
        expect(WebMock).to have_requested(:post, "https://api.voyageai.com/v1/embeddings")
          .with(headers: { "Authorization" => "Bearer #{api_key}" })
      end
    end

    context "on API error (non-2xx response)" do
      before do
        stub_request(:post, "https://api.voyageai.com/v1/embeddings")
          .to_return(status: 429, body: { "detail" => "Rate limit exceeded" }.to_json,
                     headers: { "Content-Type" => "application/json" })
      end

      it "raises VoyageClient::ApiError" do
        expect { VoyageClient.embed(input_text) }.to raise_error(VoyageClient::ApiError, /429/)
      end
    end

    context "on network error" do
      before do
        stub_request(:post, "https://api.voyageai.com/v1/embeddings")
          .to_raise(Net::OpenTimeout)
      end

      it "raises VoyageClient::ApiError wrapping the network error" do
        expect { VoyageClient.embed(input_text) }.to raise_error(VoyageClient::ApiError, /Net::OpenTimeout/)
      end
    end

    context "when API key is missing" do
      before do
        allow(Rails.application.credentials).to receive(:voyage_api_key).and_return(nil)
      end

      it "raises VoyageClient::ConfigurationError" do
        expect { VoyageClient.embed(input_text) }.to raise_error(VoyageClient::ConfigurationError, /voyage_api_key/)
      end
    end
  end
end
