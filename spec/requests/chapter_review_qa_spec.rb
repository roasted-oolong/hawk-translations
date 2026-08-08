require "rails_helper"
require "json"

RSpec.describe "ChapterReview QA", type: :request do
  let(:user)    { create(:user) }
  let(:novel)   { create(:novel) }
  let(:chapter) { create(:chapter, novel: novel, number: 1, status: "translated") }

  before { sign_in(user) }

  describe "GET /novels/:novel_id/chapter_review/chapters/:id/qa" do
    it "returns status: none when no chapter_qa job has ever run for this chapter" do
      chapter
      get novel_chapter_review_qa_path(novel, chapter)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq({ "status" => "none" })
    end

    it "returns the running job's status and progress without exposing suggestions yet" do
      job = create(:translation_job, :chapter_qa, novel: novel, user: user,
             chapter_start: chapter.number, chapter_end: chapter.number,
             status: "running", progress_pct: 50)

      get novel_chapter_review_qa_path(novel, chapter)

      body = JSON.parse(response.body)
      expect(body["id"]).to eq(job.id)
      expect(body["status"]).to eq("running")
      expect(body["progress_pct"]).to eq(50)
      expect(body["suggestions"]).to eq([])
    end

    it "returns parsed suggestions once the job has completed" do
      suggestions = [ { "id" => "s1", "source" => "editor", "quote" => "x", "status" => "pending" } ]
      job = create(:translation_job, :chapter_qa, :completed, novel: novel, user: user,
             chapter_start: chapter.number, chapter_end: chapter.number,
             result_payload: { suggestions: suggestions }.to_json)

      get novel_chapter_review_qa_path(novel, chapter)

      body = JSON.parse(response.body)
      expect(body["id"]).to eq(job.id)
      expect(body["status"]).to eq("completed")
      expect(body["suggestions"]).to eq(suggestions)
    end

    it "scopes to this chapter only — a chapter_qa job for a different chapter in the same novel doesn't leak in" do
      other_chapter = create(:chapter, novel: novel, number: 2, status: "translated")
      create(:translation_job, :chapter_qa, :completed, novel: novel, user: user,
             chapter_start: other_chapter.number, chapter_end: other_chapter.number,
             result_payload: { suggestions: [ { "id" => "s1" } ] }.to_json)

      get novel_chapter_review_qa_path(novel, chapter)

      expect(JSON.parse(response.body)).to eq({ "status" => "none" })
    end

    it "returns the most recent job when more than one chapter_qa run exists for this chapter" do
      create(:translation_job, :chapter_qa, :completed, novel: novel, user: user,
             chapter_start: chapter.number, chapter_end: chapter.number,
             result_payload: { suggestions: [ { "id" => "old" } ] }.to_json, created_at: 1.hour.ago)
      create(:translation_job, :chapter_qa, :completed, novel: novel, user: user,
             chapter_start: chapter.number, chapter_end: chapter.number,
             result_payload: { suggestions: [ { "id" => "new" } ] }.to_json, created_at: Time.current)

      get novel_chapter_review_qa_path(novel, chapter)

      expect(JSON.parse(response.body)["suggestions"].first["id"]).to eq("new")
    end
  end

  describe "PATCH /novels/:novel_id/chapter_review/chapters/:id/qa/suggestions/:suggestion_id" do
    let!(:job) do
      create(:translation_job, :chapter_qa, :completed, novel: novel, user: user,
             chapter_start: chapter.number, chapter_end: chapter.number,
             result_payload: {
               suggestions: [
                 { "id" => "s1", "source" => "editor", "quote" => "x", "status" => "pending" },
                 { "id" => "s2", "source" => "factcheck", "quote" => "y", "status" => "pending" }
               ]
             }.to_json)
    end

    it "records an accepted decision on the targeted suggestion only" do
      patch novel_update_chapter_review_qa_suggestion_path(novel, chapter, "s1"), params: { status: "accepted" }

      expect(response).to have_http_status(:ok)
      payload = JSON.parse(job.reload.result_payload)["suggestions"]
      expect(payload.find { |s| s["id"] == "s1" }["status"]).to eq("accepted")
      expect(payload.find { |s| s["id"] == "s2" }["status"]).to eq("pending")
    end

    it "records a rejected decision" do
      patch novel_update_chapter_review_qa_suggestion_path(novel, chapter, "s2"), params: { status: "rejected" }

      payload = JSON.parse(job.reload.result_payload)["suggestions"]
      expect(payload.find { |s| s["id"] == "s2" }["status"]).to eq("rejected")
    end

    it "rejects an invalid status value without mutating the suggestion" do
      patch novel_update_chapter_review_qa_suggestion_path(novel, chapter, "s1"), params: { status: "maybe" }

      expect(response).to have_http_status(:unprocessable_entity)
      payload = JSON.parse(job.reload.result_payload)["suggestions"]
      expect(payload.find { |s| s["id"] == "s1" }["status"]).to eq("pending")
    end

    it "404s for an unknown suggestion id" do
      patch novel_update_chapter_review_qa_suggestion_path(novel, chapter, "does-not-exist"), params: { status: "accepted" }

      expect(response).to have_http_status(:not_found)
    end

    it "404s when no completed chapter_qa job exists for this chapter" do
      other_chapter = create(:chapter, novel: novel, number: 2, status: "translated")

      patch novel_update_chapter_review_qa_suggestion_path(novel, other_chapter, "s1"), params: { status: "accepted" }

      expect(response).to have_http_status(:not_found)
    end
  end
end
