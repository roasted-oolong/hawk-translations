# frozen_string_literal: true

require "rails_helper"

RSpec.describe "BibleSearch", type: :request do
  let(:organization) { create(:organization) }
  let(:novel)        { create(:novel, organization: organization) }
  let(:user)         { create(:user) }
  let(:fake_vector)  { Array.new(1024, 0.01) }
  let(:fake_results) do
    [
      {
        embedding_id:    1,
        embeddable_type: "BibleCharacter",
        embeddable_id:   42,
        novel_id:        novel.id,
        score:           0.91,
        record:          build(:bible_character, novel: novel, name: "Hyuk Kang")
      }
    ]
  end

  before { sign_in(user) }

  describe "GET /novels/:novel_id/bible/search" do
    context "with a valid query" do
      before do
        allow(BibleSearchService).to receive(:new).and_return(
          instance_double(BibleSearchService, call: fake_results)
        )
      end

      it "returns 200 OK" do
        get novel_bible_search_path(novel), params: { q: "grumpy sunbae" }
        expect(response).to have_http_status(:ok)
      end

      it "returns JSON content type" do
        get novel_bible_search_path(novel), params: { q: "grumpy sunbae" }
        expect(response.content_type).to include("application/json")
      end

      it "returns a results array in the response body" do
        get novel_bible_search_path(novel), params: { q: "grumpy sunbae" }
        body = JSON.parse(response.body)
        expect(body).to have_key("results")
        expect(body["results"]).to be_an(Array)
      end

      it "serializes the expected fields for each result" do
        get novel_bible_search_path(novel), params: { q: "grumpy sunbae" }
        result = JSON.parse(response.body)["results"].first
        expect(result).to include(
          "embeddable_type", "embeddable_id", "novel_id", "score", "record"
        )
      end

      it "passes the query and novel scope to BibleSearchService" do
        expect(BibleSearchService).to receive(:new).with(
          hash_including(scope: novel, query: "grumpy sunbae")
        ).and_return(instance_double(BibleSearchService, call: []))

        get novel_bible_search_path(novel), params: { q: "grumpy sunbae" }
      end

      it "passes categories when provided" do
        expect(BibleSearchService).to receive(:new).with(
          hash_including(categories: ["BibleCharacter"])
        ).and_return(instance_double(BibleSearchService, call: []))

        get novel_bible_search_path(novel),
            params: { q: "manager", categories: ["BibleCharacter"] }
      end
    end

    context "with a blank query" do
      it "returns 200 with an empty results array" do
        get novel_bible_search_path(novel), params: { q: "" }
        body = JSON.parse(response.body)
        expect(response).to have_http_status(:ok)
        expect(body["results"]).to eq([])
      end
    end

    context "when unauthenticated" do
      before do
        # Clear the session set by sign_in
        delete logout_path
      end

      it "redirects to login" do
        get novel_bible_search_path(novel), params: { q: "anything" }
        expect(response).to redirect_to(login_path)
      end
    end

    context "when the novel does not exist" do
      it "returns 404" do
        get novel_bible_search_path(novel_id: 0), params: { q: "anything" }
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when BibleSearchService raises VoyageClient::ApiError" do
      before do
        allow(BibleSearchService).to receive(:new).and_return(
          instance_double(BibleSearchService).tap do |svc|
            allow(svc).to receive(:call).and_raise(VoyageClient::ApiError, "rate limited")
          end
        )
      end

      it "returns 503 with an error message" do
        get novel_bible_search_path(novel), params: { q: "anything" }
        expect(response).to have_http_status(:service_unavailable)
        body = JSON.parse(response.body)
        expect(body).to have_key("error")
      end
    end
  end
end
