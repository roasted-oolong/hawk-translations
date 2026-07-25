require "rails_helper"

RSpec.describe "PostTranslationReview", type: :request do
  let(:user)      { create(:user) }
  let(:novel_dir) { Dir.mktmpdir }
  let(:novel)     { create(:novel, directory_name: File.basename(novel_dir)) }
  let(:characters_path) { File.join(novel_dir, "bible", "characters.md") }
  let(:story_path)      { File.join(novel_dir, "bible", "story.md") }

  let(:new_entry_card) do
    {
      "id" => "new_entry_0", "card_type" => "new_entry", "decision" => "pending",
      "section_key" => "characters", "heading" => "New Girl — English",
      "content" => "## New Girl — English\n- Role: rival"
    }
  end

  let(:proposed_edit_card) do
    {
      "id" => "proposed_edit_0", "card_type" => "proposed_edit", "decision" => "pending",
      "entry" => "## Existing Char", "section_key" => "characters",
      "current" => "- Role: villager", "proposed" => "- Role: idol trainee", "reason" => "Revealed this chapter."
    }
  end

  let(:story_update_card) do
    {
      "id" => "story_update_0", "card_type" => "story_update", "decision" => "pending",
      "type" => "Main Plot", "update" => "Min-jun decided to audition."
    }
  end

  before do
    sign_in(user)
    FileUtils.mkdir_p(File.join(novel_dir, "bible"))
    File.write(characters_path, "## Existing Char — English\n- Role: villager\n")
    File.write(story_path, "## Open Arcs\n- Debut arc in motion\n")

    @orig_root = ENV["HAWK_PROJECT_ROOT"]
    ENV["HAWK_PROJECT_ROOT"] = File.dirname(novel_dir)
  end

  after do
    ENV["HAWK_PROJECT_ROOT"] = @orig_root
    FileUtils.rm_rf(novel_dir)
  end

  def bible_revision
    {
      "characters"       => Digest::SHA256.hexdigest(File.read(characters_path)),
      "cultural_phrases" => Digest::SHA256.hexdigest(""),
      "locations"        => Digest::SHA256.hexdigest(""),
      "story"            => Digest::SHA256.hexdigest(File.read(story_path)),
      "terminology"      => Digest::SHA256.hexdigest("")
    }
  end

  def create_job!(cards, revision: bible_revision)
    create(:translation_job, :post_translation_review, :completed, novel: novel, user: user,
           chapter_start: 1, chapter_end: 1,
           result_payload: { cards: cards, bible_revision: revision }.to_json)
  end

  describe "GET /novels/:novel_id/post_translation_review" do
    it "renders the cards from the most recent completed job" do
      create_job!([ new_entry_card ])

      get novel_post_translation_review_path(novel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("New Girl")
    end

    it "redirects when there is no completed job with cards" do
      get novel_post_translation_review_path(novel)

      expect(response).to redirect_to(novel_path(novel))
    end

    it "surfaces a staleness warning when a bible file has changed since generation" do
      create_job!([ new_entry_card ], revision: bible_revision.merge("characters" => "stale-sha"))

      get novel_post_translation_review_path(novel)

      expect(response.body).to include("changed since these proposals were generated")
    end

    it "does not surface a staleness warning when the bible is unchanged" do
      create_job!([ new_entry_card ])

      get novel_post_translation_review_path(novel)

      expect(response.body).not_to include("changed since these proposals were generated")
    end
  end

  describe "PATCH /novels/:novel_id/post_translation_review/cards/:card_id" do
    it "persists the decision back into the job's result_payload" do
      job = create_job!([ new_entry_card ])

      patch novel_post_translation_review_card_path(novel, card_id: new_entry_card["id"]), params: { decision: "accepted" }

      job.reload
      card = JSON.parse(job.result_payload)["cards"].first
      expect(card["decision"]).to eq("accepted")
    end

    it "rejects an invalid decision value" do
      job = create_job!([ new_entry_card ])

      patch novel_post_translation_review_card_path(novel, card_id: new_entry_card["id"]), params: { decision: "bogus" }

      job.reload
      card = JSON.parse(job.result_payload)["cards"].first
      expect(card["decision"]).to eq("pending")
    end
  end

  describe "POST /novels/:novel_id/post_translation_review/commit" do
    it "writes an accepted new_entry card to its bible file" do
      job = create_job!([ new_entry_card.merge("decision" => "accepted") ])

      post novel_post_translation_review_commit_path(novel)

      expect(File.read(characters_path)).to include("New Girl")
      job.reload
      expect(JSON.parse(job.result_payload)["cards"].first["outcome"]).to eq("applied")
    end

    it "applies an accepted proposed_edit card" do
      job = create_job!([ proposed_edit_card.merge("decision" => "accepted") ])

      post novel_post_translation_review_commit_path(novel)

      expect(File.read(characters_path)).to include("- Role: idol trainee")
      job.reload
      expect(JSON.parse(job.result_payload)["cards"].first["outcome"]).to eq("applied")
    end

    it "applies an accepted story_update card" do
      job = create_job!([ story_update_card.merge("decision" => "accepted") ])

      post novel_post_translation_review_commit_path(novel)

      expect(File.read(story_path)).to include("Min-jun decided to audition.")
    end

    it "does not write skipped cards" do
      job = create_job!([ new_entry_card.merge("decision" => "skipped") ])

      post novel_post_translation_review_commit_path(novel)

      expect(File.read(characters_path)).not_to include("New Girl")
    end

    it "commits one card's failure without blocking the rest of the batch" do
      stale_edit = proposed_edit_card.merge("decision" => "accepted", "current" => "- Role: no longer present")
      job = create_job!([ stale_edit, new_entry_card.merge("decision" => "accepted") ])

      post novel_post_translation_review_commit_path(novel)

      expect(File.read(characters_path)).to include("New Girl")
      job.reload
      outcomes = JSON.parse(job.result_payload)["cards"].map { |c| c["outcome"] }
      expect(outcomes).to include("skipped_not_found", "applied")
    end
  end
end
