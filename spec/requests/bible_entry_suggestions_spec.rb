# frozen_string_literal: true

require "rails_helper"

RSpec.describe "BibleEntrySuggestions", type: :request do
  let(:organization) { create(:organization) }
  let(:novel_dir)     { Dir.mktmpdir }
  let(:novel)         { create(:novel, organization: organization, directory_name: File.basename(novel_dir)) }
  let(:chapter)       { create(:chapter, novel: novel, number: 3) }
  let(:user)          { create(:user) }

  before do
    sign_in(user)
    @orig_root = ENV["HAWK_PROJECT_ROOT"]
    ENV["HAWK_PROJECT_ROOT"] = File.dirname(novel_dir)
  end

  after do
    ENV["HAWK_PROJECT_ROOT"] = @orig_root
    FileUtils.rm_rf(novel_dir)
  end

  def write_korean_source(text)
    path = File.join(novel_dir, "chapters", "Chapter #{chapter.number} (Korean).txt")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  describe "POST /novels/:novel_id/bible_entry_suggestion" do
    context "with a Korean source on disk" do
      before do
        write_korean_source("최민재가 마당으로 들어서며 칼을 뽑았다.")
        allow(Pipeline::BibleEntrySuggestion).to receive(:call).and_return(
          Pipeline::BibleEntrySuggestion::Result.new(fields: { "korean_name" => "최민재", "role" => "Rival swordsman" })
        )
      end

      it "returns 200 with the suggested fields" do
        post novel_bible_entry_suggestion_path(novel),
             params: { type: "bible_character", english: "Choi Min-jae", context: "context", chapter_id: chapter.id }

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["fields"]).to eq("korean_name" => "최민재", "role" => "Rival swordsman")
      end

      it "passes the chapter's Korean source text and params through to the service" do
        expect(Pipeline::BibleEntrySuggestion).to receive(:call).with(
          hash_including(
            entry_type:         "bible_character",
            english_text:       "Choi Min-jae",
            context_text:       "context",
            korean_source_text: "최민재가 마당으로 들어서며 칼을 뽑았다."
          )
        ).and_return(Pipeline::BibleEntrySuggestion::Result.new(fields: {}))

        post novel_bible_entry_suggestion_path(novel),
             params: { type: "bible_character", english: "Choi Min-jae", context: "context", chapter_id: chapter.id }
      end
    end

    context "without a Korean source on disk" do
      it "returns 200 with empty fields rather than an error" do
        post novel_bible_entry_suggestion_path(novel),
             params: { type: "bible_character", english: "Choi Min-jae", context: "context", chapter_id: chapter.id }

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["fields"]).to eq({})
      end
    end

    context "when the suggestion service degrades (CLI failure, bad JSON, etc.)" do
      before do
        write_korean_source("최민재가 마당으로 들어서며 칼을 뽑았다.")
        allow(Pipeline::BibleEntrySuggestion).to receive(:call).and_return(
          Pipeline::BibleEntrySuggestion::Result.new(fields: {}, error_category: :cli_failure, error_message: "boom")
        )
      end

      it "still returns 200 with empty fields, never surfacing the failure as an error" do
        post novel_bible_entry_suggestion_path(novel),
             params: { type: "bible_character", english: "Choi Min-jae", context: "context", chapter_id: chapter.id }

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["fields"]).to eq({})
      end
    end

    context "when the novel does not exist" do
      it "returns 404" do
        post novel_bible_entry_suggestion_path(novel_id: 0),
             params: { type: "bible_character", english: "x", chapter_id: chapter.id }
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when the chapter does not exist on the novel" do
      it "returns 404" do
        post novel_bible_entry_suggestion_path(novel),
             params: { type: "bible_character", english: "x", chapter_id: 0 }
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
