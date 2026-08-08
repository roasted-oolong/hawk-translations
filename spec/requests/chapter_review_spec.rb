require "rails_helper"

RSpec.describe "ChapterReview show", type: :request do
  let(:user)    { create(:user) }
  let(:novel)   { create(:novel) }
  let!(:chapter) { create(:chapter, novel: novel, number: 1, status: "translated") }

  before { sign_in(user) }

  describe "GET /novels/:novel_id/chapter_review" do
    it "renders successfully with a contenteditable QA pane wired for direct editing" do
      chapter.translated_output.attach(
        io: StringIO.new("Some translated text."),
        filename: "chapter_1.txt",
        content_type: "text/plain"
      )

      get novel_chapter_review_path(novel)

      expect(response).to have_http_status(:ok)

      # Both the single-column and compare-mode tracked-changes panes must
      # stay contenteditable and wired to the same three handlers, or a
      # completed QA run silently reverts to a locked, unreachable pane —
      # exactly the regression this spec exists to catch.
      expect(response.body).to include('data-testid="qa-pane-1"')
      expect(response.body).to include('data-testid="qa-pane-compare-1"')
      qa_pane_action = 'data-action="input->chapter-review#syncQaPaneEdit keydown.enter->chapter-review#qaPaneKeydown paste->chapter-review#qaPanePaste"'
      expect(response.body.scan(qa_pane_action).size).to eq(2)
      expect(response.body.scan('contenteditable="true"').size).to be >= 2
    end
  end
end
