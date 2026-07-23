require "rails_helper"

RSpec.describe "Chapters", type: :request do
  let!(:user)    { create(:user) }
  let(:novel)    { create(:novel) }
  let!(:chapter) { create(:chapter, novel: novel, number: 1, status: "untranslated") }

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

    context "when translated output is attached" do
      before do
        chapter.translated_output.attach(
          io: StringIO.new("Hello world."),
          filename: "chapter_1.txt",
          content_type: "text/plain"
        )
      end

      it "returns 200 and renders the translated text" do
        get novel_chapter_path(novel, chapter)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Hello world.")
      end
    end

    context "when korean source is attached" do
      before do
        chapter.korean_source.attach(
          io: StringIO.new(KOREAN_CONTENT),
          filename: "chapter_1_ko.txt",
          content_type: "text/plain"
        )
      end

      it "returns 200 without error" do
        get novel_chapter_path(novel, chapter)
        expect(response).to have_http_status(:ok)
      end
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
          .and have_enqueued_job(FormatKoreanChapterJob)

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

      it "does not enqueue a format job" do
        expect {
          post novel_chapters_path(novel), params: {
            chapter: { files: [file], number: 3 }
          }
        }.not_to have_enqueued_job(FormatKoreanChapterJob)
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

      it "surfaces the validation error in the flash instead of failing silently" do
        post novel_chapters_path(novel), params: {
          chapter: { files: [file], number: 1 }
        }

        expect(flash[:alert]).to match(/number.*taken/i)
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
          .and have_enqueued_job(FormatKoreanChapterJob).exactly(:once)

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
  # Photo scan (OCR) upload
  # ---------------------------------------------------------------------------
  describe "POST /novels/:novel_id/chapters/create_from_photos" do
    def image_fixture(name = "cover.jpg", content_type = "image/jpeg")
      fixture_file_upload(Rails.root.join("spec/fixtures/files/#{name}"), content_type)
    end

    context "with valid images and a chapter number" do
      it "creates one chapter and enqueues OcrChapterJob with the ordered image paths" do
        expect {
          post create_from_photos_novel_chapters_path(novel), params: {
            chapter: { number: 4, images: [ image_fixture, image_fixture ] }
          }
        }.to change(Chapter, :count).by(1)
          .and have_enqueued_job(OcrChapterJob)

        ch = Chapter.last
        expect(ch.number).to eq(4)
        expect(ch.status).to eq("ocr_processing")
        job = enqueued_jobs.find { |j| j["job_class"] == "OcrChapterJob" }
        expect(job["arguments"][0]).to eq(ch.id)
        expect(job["arguments"][1].size).to eq(2)
      end

      it "redirects to the new chapter" do
        post create_from_photos_novel_chapters_path(novel), params: {
          chapter: { number: 4, images: [ image_fixture ] }
        }

        expect(response).to redirect_to(novel_chapter_path(novel, Chapter.last))
      end
    end

    context "when the chapter number is missing" do
      it "does not create a chapter and returns unprocessable_entity" do
        expect {
          post create_from_photos_novel_chapters_path(novel), params: {
            chapter: { images: [ image_fixture ] }
          }
        }.not_to change(Chapter, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when the chapter number is a duplicate" do
      it "does not create a chapter and returns unprocessable_entity" do
        expect {
          post create_from_photos_novel_chapters_path(novel), params: {
            chapter: { number: 1, images: [ image_fixture ] }
          }
        }.not_to change(Chapter, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "surfaces the validation error in the flash instead of failing silently" do
        post create_from_photos_novel_chapters_path(novel), params: {
          chapter: { number: 1, images: [ image_fixture ] }
        }

        expect(flash[:alert]).to match(/number.*taken/i)
      end
    end

    context "when no images are given" do
      it "does not create a chapter and returns unprocessable_entity" do
        expect {
          post create_from_photos_novel_chapters_path(novel), params: {
            chapter: { number: 4, images: [] }
          }
        }.not_to change(Chapter, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when an image has a disallowed content type" do
      it "does not create a chapter and returns unprocessable_entity" do
        expect {
          post create_from_photos_novel_chapters_path(novel), params: {
            chapter: { number: 4, images: [ image_fixture("cover.gif", "image/gif") ] }
          }
        }.not_to change(Chapter, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "with a single PDF and a chapter number" do
      def pdf_fixture(name = "sample.pdf")
        fixture_file_upload(Rails.root.join("spec/fixtures/files/#{name}"), "application/pdf")
      end

      it "creates one chapter and enqueues OcrChapterJob with the PDF's staged path" do
        expect {
          post create_from_photos_novel_chapters_path(novel), params: {
            chapter: { number: 4, images: [ pdf_fixture ] }
          }
        }.to change(Chapter, :count).by(1)
          .and have_enqueued_job(OcrChapterJob)

        ch  = Chapter.last
        job = enqueued_jobs.find { |j| j["job_class"] == "OcrChapterJob" }
        expect(job["arguments"][0]).to eq(ch.id)
        expect(job["arguments"][1].size).to eq(1)
        expect(job["arguments"][1].first).to end_with(".pdf")
      end

      it "redirects to the new chapter" do
        post create_from_photos_novel_chapters_path(novel), params: {
          chapter: { number: 4, images: [ pdf_fixture ] }
        }

        expect(response).to redirect_to(novel_chapter_path(novel, Chapter.last))
      end

      it "rejects a PDF over the size cap" do
        stub_const("ChaptersController::PDF_MAX_BYTES", 100)

        expect {
          post create_from_photos_novel_chapters_path(novel), params: {
            chapter: { number: 4, images: [ pdf_fixture ] }
          }
        }.not_to change(Chapter, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when a PDF is submitted alongside other files" do
      def pdf_fixture(name = "sample.pdf")
        fixture_file_upload(Rails.root.join("spec/fixtures/files/#{name}"), "application/pdf")
      end

      it "rejects the whole batch rather than guessing what was meant" do
        expect {
          post create_from_photos_novel_chapters_path(novel), params: {
            chapter: { number: 4, images: [ pdf_fixture, image_fixture ] }
          }
        }.not_to change(Chapter, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "rejects two PDFs in the same batch" do
        expect {
          post create_from_photos_novel_chapters_path(novel), params: {
            chapter: { number: 4, images: [ pdf_fixture, pdf_fixture ] }
          }
        }.not_to change(Chapter, :count)

        expect(response).to have_http_status(:unprocessable_entity)
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

  # ---------------------------------------------------------------------------
  # Bulk destroy
  # ---------------------------------------------------------------------------
  describe "DELETE /novels/:novel_id/chapters/bulk_destroy" do
    let!(:chapter2) { create(:chapter, novel: novel, number: 2) }
    let!(:chapter3) { create(:chapter, novel: novel, number: 3) }

    it "destroys selected chapters and redirects to chapter list" do
      expect {
        delete bulk_destroy_novel_chapters_path(novel), params: { chapter_ids: [chapter2.id, chapter3.id] }
      }.to change(Chapter, :count).by(-2)

      expect(response).to redirect_to(novel_chapters_path(novel))
    end

    it "destroys only the selected chapters, leaving others intact" do
      expect {
        delete bulk_destroy_novel_chapters_path(novel), params: { chapter_ids: [chapter2.id] }
      }.to change(Chapter, :count).by(-1)

      expect(chapter.reload).to be_persisted
    end

    it "does not destroy chapters belonging to another novel" do
      other = create(:chapter, novel: create(:novel), number: 99)

      expect {
        delete bulk_destroy_novel_chapters_path(novel), params: { chapter_ids: [other.id] }
      }.not_to change(Chapter, :count)

      expect(flash[:alert]).to be_present
    end

    it "redirects with alert when no chapter_ids are given" do
      delete bulk_destroy_novel_chapters_path(novel), params: { chapter_ids: [] }

      expect(response).to redirect_to(novel_chapters_path(novel))
      expect(flash[:alert]).to be_present
    end
  end

  # ---------------------------------------------------------------------------
  # Bulk update status
  # ---------------------------------------------------------------------------
  describe "PATCH /novels/:novel_id/chapters/bulk_update" do
    let!(:chapter2) { create(:chapter, novel: novel, number: 2, status: "untranslated") }
    let!(:chapter3) { create(:chapter, novel: novel, number: 3, status: "untranslated") }

    it "updates status for all selected chapters and redirects" do
      patch bulk_update_novel_chapters_path(novel), params: {
        chapter_ids: [chapter2.id, chapter3.id],
        status: "translated"
      }

      expect(chapter2.reload.status).to eq("translated")
      expect(chapter3.reload.status).to eq("translated")
      expect(response).to redirect_to(novel_chapters_path(novel))
    end

    it "does not update chapters that were not selected" do
      patch bulk_update_novel_chapters_path(novel), params: {
        chapter_ids: [chapter2.id],
        status: "translated"
      }

      expect(chapter3.reload.status).to eq("untranslated")
    end

    it "redirects with alert for an unrecognised status value" do
      patch bulk_update_novel_chapters_path(novel), params: {
        chapter_ids: [chapter2.id],
        status: "published"
      }

      expect(response).to redirect_to(novel_chapters_path(novel))
      expect(flash[:alert]).to be_present
      expect(chapter2.reload.status).to eq("untranslated")
    end

    it "redirects with alert when no chapter_ids are given" do
      patch bulk_update_novel_chapters_path(novel), params: { chapter_ids: [], status: "translated" }

      expect(response).to redirect_to(novel_chapters_path(novel))
      expect(flash[:alert]).to be_present
    end
  end

  # ---------------------------------------------------------------------------
  # Bulk download
  # ---------------------------------------------------------------------------
  describe "POST /novels/:novel_id/chapters/bulk_download" do
    let!(:chapter2) { create(:chapter, novel: novel, number: 2) }

    it "streams a zip file when chapters have attachments" do
      chapter2.korean_source.attach(
        io:           StringIO.new(KOREAN_CONTENT),
        filename:     "2화.txt",
        content_type: "text/plain"
      )

      post bulk_download_novel_chapters_path(novel), params: { chapter_ids: [chapter2.id] }

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq("application/zip")
      expect(response.headers["Content-Disposition"]).to include("attachment")
    end

    it "streams an empty zip when selected chapters have no attachments" do
      post bulk_download_novel_chapters_path(novel), params: { chapter_ids: [chapter2.id] }

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq("application/zip")
    end

    it "redirects with alert when no chapter_ids are given" do
      post bulk_download_novel_chapters_path(novel), params: { chapter_ids: [] }

      expect(response).to redirect_to(novel_chapters_path(novel))
      expect(flash[:alert]).to be_present
    end
  end
end
