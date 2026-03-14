require "rails_helper"

RSpec.describe "Chapters", type: :request do
  let(:user)    { create(:user) }
  let(:novel)   { create(:novel) }
  let!(:chapter) { create(:chapter, novel: novel, number: 1, status: "untranslated") }

  before { sign_in(user) }

  # ---------------------------------------------------------------------------
  # Chapter list (story #12)
  # ---------------------------------------------------------------------------
  describe "GET /novels/:novel_id/chapters" do
    it "returns 200 and lists chapters" do
      get novel_chapters_path(novel)
      expect(response).to have_http_status(:ok)
    end
  end

  # ---------------------------------------------------------------------------
  # Chapter show
  # ---------------------------------------------------------------------------
  describe "GET /novels/:novel_id/chapters/:id" do
    it "returns 200 and shows the chapter" do
      get novel_chapter_path(novel, chapter)
      expect(response).to have_http_status(:ok)
    end
  end

  # ---------------------------------------------------------------------------
  # Upload form
  # ---------------------------------------------------------------------------
  describe "GET /novels/:novel_id/chapters/new" do
    it "returns 200" do
      get new_novel_chapter_path(novel)
      expect(response).to have_http_status(:ok)
    end
  end

  # ---------------------------------------------------------------------------
  # Single upload (story #10)
  # ---------------------------------------------------------------------------
  describe "POST /novels/:novel_id/chapters — single file" do
    let(:korean_file) do
      Rack::Test::UploadedFile.new(
        StringIO.new("Korean source content"),
        "text/plain",
        original_filename: "ch5_korean"
      )
    end

    context "with valid params" do
      it "creates a chapter record and attaches the file" do
        expect {
          post novel_chapters_path(novel), params: {
            chapter: {
              number:        5,
              status:        "untranslated",
              korean_source: [ korean_file ]
            }
          }
        }.to change(Chapter, :count).by(1)

        ch = Chapter.last
        expect(ch.number).to eq(5)
        expect(ch.korean_source).to be_attached
        expect(response).to redirect_to(novel_chapter_path(novel, ch))
      end
    end

    context "with missing chapter number" do
      it "does not create a chapter and re-renders new" do
        expect {
          post novel_chapters_path(novel), params: {
            chapter: { number: nil, korean_source: [ korean_file ] }
          }
        }.not_to change(Chapter, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "with a duplicate chapter number" do
      it "does not create a chapter and re-renders new" do
        expect {
          post novel_chapters_path(novel), params: {
            chapter: { number: 1, korean_source: [ korean_file ] }  # chapter 1 already exists
          }
        }.not_to change(Chapter, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Bulk upload (story #11)
  # ---------------------------------------------------------------------------
  describe "POST /novels/:novel_id/chapters — bulk upload" do
    let(:file_ch10) do
      Rack::Test::UploadedFile.new(
        StringIO.new("ch10 content"),
        "text/plain",
        original_filename: "ch10_korean"
      )
    end

    let(:file_ch11) do
      Rack::Test::UploadedFile.new(
        StringIO.new("ch11 content"),
        "text/plain",
        original_filename: "ch11_korean"
      )
    end

    it "creates one chapter per file and redirects to chapter list" do
      expect {
        post novel_chapters_path(novel), params: {
          chapter: { korean_source: [ file_ch10, file_ch11 ] }
        }
      }.to change(Chapter, :count).by(2)

      expect(response).to redirect_to(novel_chapters_path(novel))
    end

    context "when a filename cannot be parsed" do
      let(:bad_file) do
        Rack::Test::UploadedFile.new(
          StringIO.new("bad"),
          "text/plain",
          original_filename: "not_a_chapter.txt"
        )
      end

      it "skips the unparseable file and still creates the valid ones" do
        expect {
          post novel_chapters_path(novel), params: {
            chapter: { korean_source: [ file_ch10, bad_file ] }
          }
        }.to change(Chapter, :count).by(1)

        expect(response).to redirect_to(novel_chapters_path(novel))
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Edit / update status (story #14)
  # ---------------------------------------------------------------------------
  describe "GET /novels/:novel_id/chapters/:id/edit" do
    it "returns 200" do
      get edit_novel_chapter_path(novel, chapter)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /novels/:novel_id/chapters/:id — status update" do
    it "updates the status and redirects" do
      patch novel_chapter_path(novel, chapter), params: {
        chapter: { status: "translated" }
      }
      expect(response).to redirect_to(novel_chapter_path(novel, chapter))
      expect(chapter.reload.status).to eq("translated")
    end

    it "rejects an invalid status" do
      patch novel_chapter_path(novel, chapter), params: {
        chapter: { status: "published" }
      }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # ---------------------------------------------------------------------------
  # Destroy
  # ---------------------------------------------------------------------------
  describe "DELETE /novels/:novel_id/chapters/:id" do
    it "destroys the chapter and redirects to chapter list" do
      expect {
        delete novel_chapter_path(novel, chapter)
      }.to change(Chapter, :count).by(-1)

      expect(response).to redirect_to(novel_chapters_path(novel))
    end
  end

  # ---------------------------------------------------------------------------
  # Downloads (stories #13)
  # ---------------------------------------------------------------------------
  describe "GET download_korean_source" do
    context "when file is attached" do
      before do
        chapter.korean_source.attach(
          io: StringIO.new("korean"),
          filename: "ch1_korean",
          content_type: "text/plain"
        )
      end

      it "redirects to the blob download URL" do
        get download_korean_source_novel_chapter_path(novel, chapter)
        expect(response).to have_http_status(:redirect)
      end
    end

    context "when no file is attached" do
      it "redirects back to the chapter with an alert" do
        get download_korean_source_novel_chapter_path(novel, chapter)
        expect(response).to redirect_to(novel_chapter_path(novel, chapter))
      end
    end
  end

  describe "GET download_translated_output" do
    context "when file is attached" do
      before do
        chapter.translated_output.attach(
          io: StringIO.new("translated"),
          filename: "Chapter_1.txt",
          content_type: "text/plain"
        )
      end

      it "redirects to the blob download URL" do
        get download_translated_output_novel_chapter_path(novel, chapter)
        expect(response).to have_http_status(:redirect)
      end
    end

    context "when no file is attached" do
      it "redirects back to the chapter with an alert" do
        get download_translated_output_novel_chapter_path(novel, chapter)
        expect(response).to redirect_to(novel_chapter_path(novel, chapter))
      end
    end
  end
end
