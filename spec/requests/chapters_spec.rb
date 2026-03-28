require "rails_helper"

RSpec.describe "Chapters", type: :request do
  let(:user)     { create(:user) }
  let(:novel)    { create(:novel) }
  let!(:chapter) { create(:chapter, novel: novel, number: 1, status: "untranslated") }

  before { sign_in(user) }

  # ---------------------------------------------------------------------------
  # Helpers — build uploaded files whose *content* drives language detection
  # ---------------------------------------------------------------------------
  # Enough Hangul to be unambiguously >50% of non-ASCII, non-whitespace chars.
  KOREAN_CONTENT  = ("가나다라마바사아자차" * 40).freeze
  # Pure ASCII — no non-ASCII chars at all → :english
  ENGLISH_CONTENT = ("The manager stepped into the boardroom. " * 40).freeze

  def uploaded_file(content:, filename:)
    Rack::Test::UploadedFile.new(
      StringIO.new(content),
      "text/plain",
      original_filename: filename
    )
  end

  # ---------------------------------------------------------------------------
  # Chapter list
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
  # Single upload
  # ---------------------------------------------------------------------------
  describe "POST /novels/:novel_id/chapters — single file" do
    context "when file content is Korean" do
      let(:file) { uploaded_file(content: KOREAN_CONTENT, filename: "3화.txt") }

      it "creates a chapter, attaches to korean_source, status untranslated" do
        expect {
          post novel_chapters_path(novel), params: {
            chapter: { files: [file], number: 3 }
          }
        }.to change(Chapter, :count).by(1)

        ch = Chapter.last
        expect(ch.number).to eq(3)
        expect(ch.status).to eq("untranslated")
        expect(ch.korean_source).to be_attached
        expect(ch.translated_output).not_to be_attached
        expect(response).to redirect_to(novel_chapter_path(novel, ch))
      end
    end

    context "when file content is English" do
      let(:file) { uploaded_file(content: ENGLISH_CONTENT, filename: "Chapter 3.txt") }

      it "creates a chapter, attaches to translated_output, status translated" do
        expect {
          post novel_chapters_path(novel), params: {
            chapter: { files: [file], number: 3 }
          }
        }.to change(Chapter, :count).by(1)

        ch = Chapter.last
        expect(ch.number).to eq(3)
        expect(ch.status).to eq("translated")
        expect(ch.translated_output).to be_attached
        expect(ch.korean_source).not_to be_attached
        expect(response).to redirect_to(novel_chapter_path(novel, ch))
      end
    end

    context "when the chapter number param is missing" do
      let(:file) { uploaded_file(content: KOREAN_CONTENT, filename: "notes.txt") }

      it "does not create a chapter and returns unprocessable_entity" do
        expect {
          post novel_chapters_path(novel), params: {
            chapter: { files: [file], number: nil }
          }
        }.not_to change(Chapter, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when the chapter number is a duplicate" do
      # chapter 1 already exists (created in outer let!)
      let(:file) { uploaded_file(content: KOREAN_CONTENT, filename: "1화.txt") }

      it "does not create a chapter and returns unprocessable_entity" do
        expect {
          post novel_chapters_path(novel), params: {
            chapter: { files: [file], number: 1 }
          }
        }.not_to change(Chapter, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Bulk upload
  # ---------------------------------------------------------------------------
  describe "POST /novels/:novel_id/chapters — bulk upload" do
    context "with one Korean-content file and one English-content file" do
      let(:korean_file)  { uploaded_file(content: KOREAN_CONTENT,  filename: "5화.txt") }
      let(:english_file) { uploaded_file(content: ENGLISH_CONTENT, filename: "Chapter 6.txt") }

      it "creates two chapters with correct attachment slots and statuses" do
        expect {
          post novel_chapters_path(novel), params: {
            chapter: {
              files: [korean_file, english_file],
              numbers: {
                "5화.txt"       => 5,
                "Chapter 6.txt" => 6
              }
            }
          }
        }.to change(Chapter, :count).by(2)

        korean_ch  = Chapter.find_by(number: 5)
        english_ch = Chapter.find_by(number: 6)

        expect(korean_ch.korean_source).to be_attached
        expect(korean_ch.translated_output).not_to be_attached
        expect(korean_ch.status).to eq("untranslated")

        expect(english_ch.translated_output).to be_attached
        expect(english_ch.korean_source).not_to be_attached
        expect(english_ch.status).to eq("translated")

        expect(response).to redirect_to(novel_chapters_path(novel))
      end
    end

    context "when a filename is parseable" do
      let(:file) { uploaded_file(content: KOREAN_CONTENT, filename: "10화.txt") }

      it "uses the number parsed from the filename when no per-file number param is given" do
        expect {
          post novel_chapters_path(novel), params: {
            chapter: { files: [file], numbers: {} }
          }
        }.to change(Chapter, :count).by(1)

        expect(Chapter.last.number).to eq(10)
      end
    end

    context "when a filename is unparseable and a per-file number param is provided" do
      let(:file) { uploaded_file(content: KOREAN_CONTENT, filename: "notes.txt") }

      it "uses the number from the param" do
        expect {
          post novel_chapters_path(novel), params: {
            chapter: {
              files: [file],
              numbers: { "notes.txt" => 7 }
            }
          }
        }.to change(Chapter, :count).by(1)

        expect(Chapter.last.number).to eq(7)
      end
    end

    context "when a filename is unparseable and no per-file number param is provided" do
      let(:good_file) { uploaded_file(content: KOREAN_CONTENT,  filename: "5화.txt") }
      let(:bad_file)  { uploaded_file(content: ENGLISH_CONTENT, filename: "notes.txt") }

      it "skips the file with no resolvable number and creates the valid ones" do
        expect {
          post novel_chapters_path(novel), params: {
            chapter: {
              files: [good_file, bad_file],
              numbers: {}
            }
          }
        }.to change(Chapter, :count).by(1)

        expect(response).to redirect_to(novel_chapters_path(novel))
      end
    end

    context "when a chapter number would duplicate an existing record" do
      let(:dup_file)  { uploaded_file(content: KOREAN_CONTENT, filename: "1화.txt") }
      let(:good_file) { uploaded_file(content: KOREAN_CONTENT, filename: "9화.txt") }

      it "skips the duplicate and still creates the valid file" do
        expect {
          post novel_chapters_path(novel), params: {
            chapter: { files: [dup_file, good_file], numbers: {} }
          }
        }.to change(Chapter, :count).by(1)

        expect(Chapter.find_by(number: 9)).to be_present
        expect(response).to redirect_to(novel_chapters_path(novel))
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Edit / update status
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
  # Downloads
  # ---------------------------------------------------------------------------
  describe "GET download_korean_source" do
    context "when file is attached" do
      before do
        chapter.korean_source.attach(
          io:           StringIO.new("korean"),
          filename:     "3화.txt",
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
          io:           StringIO.new("translated"),
          filename:     "Chapter 1.txt",
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
