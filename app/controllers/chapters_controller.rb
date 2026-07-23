class ChaptersController < ApplicationController
  before_action :set_novel
  before_action :set_chapter, only: [ :show, :edit, :update, :destroy,
                                      :download_korean_source, :download_translated_output,
                                      :approve ]

  PHOTO_ALLOWED_CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze
  PDF_CONTENT_TYPE            = "application/pdf"
  PDF_MAX_BYTES               = 25.megabytes

  def index
    redirect_to novel_path(@novel) and return unless turbo_frame_request?
    @chapters         = @novel.chapters.order(number: :desc)
    @cancellable_jobs = cancellable_job_map
  end

  def show
    @chapter_text = @chapter.translated_output.attached? ?
      @chapter.translated_output.download.force_encoding("UTF-8") : ""
  end

  def new
    @chapter = @novel.chapters.build
  end

  # Unified upload: one or many files through a single `chapter[files][]` input.
  # Language is detected from file content by ChapterFileClassifier.
  #
  # Routing:
  #   - If the request omits chapter[number] (the scalar field), use the bulk
  #     path. The review table never sends chapter[number]; it sends
  #     chapter[numbers][filename] instead — but Rack drops empty hashes, so
  #     the absence of the scalar key is the only reliable discriminator.
  #   - If chapter[number] is present, use the legacy single-file path.
  def create
    files = Array(params.dig(:chapter, :files)).compact_blank

    if bulk_upload?
      create_bulk(files)
    else
      create_single(files.first)
    end
  end

  def edit; end

  def update
    if @chapter.update(chapter_update_params)
      redirect_to novel_chapter_path(@novel, @chapter), notice: "Chapter updated."
    else
      render :edit, status: :unprocessable_entity
    end
  rescue ArgumentError
    render :edit, status: :unprocessable_entity
  end

  def destroy
    @chapter.destroy
    redirect_to novel_path(@novel), notice: "Chapter removed."
  end

  def approve
    @chapter.update!(status: :reviewed)
    head :ok
  end

  def approve_all
    ids   = params[:chapter_ids].to_a.map(&:to_i)
    count = @novel.chapters.where(id: ids).update_all(status: "reviewed")
    redirect_to novel_path(@novel), notice: "#{count} chapter(s) marked as reviewed."
  end

  def download_korean_source
    if @chapter.korean_source.attached?
      redirect_to rails_blob_path(@chapter.korean_source, disposition: "attachment")
    else
      redirect_to novel_chapter_path(@novel, @chapter), alert: "No Korean source file attached."
    end
  end

  def download_translated_output
    if @chapter.translated_output.attached?
      redirect_to rails_blob_path(@chapter.translated_output, disposition: "attachment")
    else
      redirect_to novel_chapter_path(@novel, @chapter), alert: "No translated output file attached."
    end
  end

  # Photo scan (OCR) upload: either N ordered photos, or a single PDF, become
  # one chapter's Korean source, via OcrChapterJob. Kept separate from
  # create/create_single/create_bulk — one batch always maps to exactly one
  # chapter, so the single/bulk discriminator used there doesn't apply here.
  #
  # A PDF's pages don't need separate rasterization: PaddleOCR (via PaddleX's
  # PDFReader) reads a multi-page PDF path directly and yields one result per
  # page, the same shape ocr_chapter.py already expects from a list of image
  # paths — so a validated PDF is staged and handed to OcrChapterJob exactly
  # like a batch of photos would be.
  def create_from_photos
    images = Array(params.dig(:chapter, :images)).compact_blank

    return render_photo_error("No images provided.") if images.empty?

    batch_error = validate_photo_batch(images)
    return render_photo_error(batch_error) if batch_error

    @chapter = @novel.chapters.build(
      number: params.dig(:chapter, :number).presence&.to_i,
      title:  params.dig(:chapter, :title).presence,
      status: "ocr_processing"
    )

    if @chapter.save
      image_paths = stage_images_for_ocr(images)
      source_label = images.size == 1 && images.first.content_type == PDF_CONTENT_TYPE ? "PDF" : "#{images.size} photo(s)"
      OcrChapterJob.perform_later(@chapter.id, image_paths)
      redirect_to novel_chapter_path(@novel, @chapter),
        notice: "Chapter created. Extracting text from #{source_label}…"
    else
      flash.now[:alert] = @chapter.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  def bulk_destroy
    chapters = @novel.chapters.where(id: bulk_chapter_ids)
    count = chapters.count
    return redirect_to novel_chapters_path(@novel), alert: "No chapters selected." if count.zero?

    chapters.destroy_all
    redirect_to novel_chapters_path(@novel), notice: "#{count} chapter(s) removed."
  end

  def bulk_update
    status = params[:status].to_s
    unless Chapter.statuses.key?(status)
      return redirect_to novel_chapters_path(@novel), alert: "Invalid status."
    end

    chapters = @novel.chapters.where(id: bulk_chapter_ids)
    count = chapters.count
    return redirect_to novel_chapters_path(@novel), alert: "No chapters selected." if count.zero?

    chapters.update_all(status: status)
    redirect_to novel_chapters_path(@novel), notice: "#{count} chapter(s) updated to #{status.humanize}."
  end

  def bulk_download
    chapters = @novel.chapters.where(id: bulk_chapter_ids).order(:number).to_a
    return redirect_to novel_chapters_path(@novel), alert: "No chapters selected." if chapters.empty?

    zip_data = Zip::OutputStream.write_buffer do |zip|
      chapters.each do |chapter|
        append_attachment(zip, chapter, chapter.korean_source, "korean")
        append_attachment(zip, chapter, chapter.translated_output, "translated")
      end
    end

    send_data zip_data.string,
      type: "application/zip",
      filename: "#{@novel.title.parameterize}-chapters.zip",
      disposition: "attachment"
  end

  private

  def cancellable_job_map
    @novel.translation_jobs.where(status: %w[queued running]).each_with_object({}) do |job, map|
      (job.chapter_start..job.chapter_end).each { |n| map[n] ||= job }
    end
  end

  def set_novel
    @novel = Novel.find(params[:novel_id])
  end

  def set_chapter
    @chapter = @novel.chapters.find(params[:id])
  end

  # Params for updating an existing chapter (status only — files attached separately)
  def chapter_update_params
    params.require(:chapter).permit(:title, :status, :korean_source, :translated_output)
  end

  # Distinguish bulk (review-table) submissions from legacy single-file uploads.
  #
  # The legacy single-file form sends chapter[number] (a scalar integer field).
  # The review table sends chapter[numbers] (a per-filename hash), but Rack
  # silently drops empty hashes during form encoding — so chapter[numbers] is
  # absent from params whenever every number was resolved from the filename
  # and the user overrode nothing.
  #
  # The only reliable discriminator is therefore the *absence* of the scalar
  # chapter[number] key: single-file always sends it; bulk never does.
  def bulk_upload?
    !params[:chapter]&.key?(:number)
  end

  # Resolves the chapter number for one file in a bulk upload.
  # Priority: classifier result (from filename) → per-file param → nil.
  def resolve_number(filename:, classified_number:)
    return classified_number if classified_number

    raw = params.dig(:chapter, :numbers, filename).presence
    raw&.to_i
  end

  def create_single(file)
    return render_single_error("No file provided.") if file.nil?

    classification = ChapterFileClassifier.new(file, file.original_filename).classify
    number         = params.dig(:chapter, :number).presence&.to_i

    @chapter = @novel.chapters.build(
      number: number,
      title:  params.dig(:chapter, :title).presence
    )

    attach_file(@chapter, file, classification[:language])

    if @chapter.save
      if classification[:language] == :korean
        KoreanSourceDiskWriter.new(@novel).write(@chapter)
        FormatKoreanChapterJob.perform_later(@chapter.id)
      end
      redirect_to novel_chapter_path(@novel, @chapter), notice: "Chapter created."
    else
      flash.now[:alert] = @chapter.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  def create_bulk(files)
    created  = []
    failures = []

    files.each do |file|
      classification = ChapterFileClassifier.new(file, file.original_filename).classify
      number         = resolve_number(
        filename:          file.original_filename,
        classified_number: classification[:chapter_number]
      )

      if number.nil?
        failures << "#{file.original_filename} — could not determine chapter number"
        next
      end

      chapter = @novel.chapters.find_or_initialize_by(number: number)
      attach_file(chapter, file, classification[:language])

      if chapter.save
        created << chapter
        if classification[:language] == :korean
          KoreanSourceDiskWriter.new(@novel).write(chapter)
          FormatKoreanChapterJob.perform_later(chapter.id)
        end
      else
        failures << "#{file.original_filename} — #{chapter.errors.full_messages.to_sentence}"
      end
    end

    notice = "#{created.size} chapter(s) uploaded."
    alert  = failures.any? ? "Some files were skipped: #{failures.join('; ')}" : nil

    redirect_to novel_path(@novel), notice: notice, alert: alert
  end

  # Attaches `file` to the correct Active Storage slot and sets chapter status
  # based on detected language. Language is the sole authority — no status param.
  def attach_file(chapter, file, language)
    case language
    when :korean
      chapter.korean_source.attach(file)
      chapter.status = "untranslated"
    when :english
      chapter.translated_output.attach(file)
      chapter.status = "translated"
    end
  end

  def render_single_error(message)
    @chapter = @novel.chapters.build
    flash.now[:alert] = message
    render :new, status: :unprocessable_entity
  end

  def render_photo_error(message)
    @chapter = @novel.chapters.build
    flash.now[:alert] = message
    render :new, status: :unprocessable_entity
  end

  # A batch is either: a single PDF, or one-or-more photos (JPEG/PNG/WebP).
  # Mixing a PDF with anything else — or submitting more than one PDF — is
  # rejected outright rather than guessing which the user meant; they can
  # resubmit as separate uploads. Returns an error message, or nil if valid.
  def validate_photo_batch(images)
    pdf_count = images.count { |image| image.content_type == PDF_CONTENT_TYPE }

    if pdf_count.positive? && images.size > 1
      return "Upload a single PDF, or one or more photos — not both in the same upload."
    end

    if pdf_count == 1
      pdf = images.first
      if pdf.size > PDF_MAX_BYTES
        return "#{pdf.original_filename} is too large (max #{PDF_MAX_BYTES / 1.megabyte}MB) — this box runs on limited memory."
      end
      return nil
    end

    bad_image = images.find { |image| !PHOTO_ALLOWED_CONTENT_TYPES.include?(image.content_type) }
    return "#{bad_image.original_filename} is not a supported file type (JPEG, PNG, WebP, or PDF)." if bad_image

    nil
  end

  # Copies each uploaded image's bytes to a scratch directory under tmp/ so
  # OcrChapterJob can receive plain path strings (ActiveJob arguments must be
  # serializable, and the request's tempfiles are deleted once it ends).
  # OcrChapterJob deletes this directory once OCR finishes, regardless of
  # outcome — originals are never persisted to Active Storage.
  def stage_images_for_ocr(images)
    dir = Dir.mktmpdir("chapter_#{@chapter.id}_photos", Rails.root.join("tmp"))

    images.each_with_index.map do |image, index|
      ext  = File.extname(image.original_filename.to_s)
      path = File.join(dir, format("%03d%s", index, ext))
      File.binwrite(path, image.read)
      path
    end
  end

  def bulk_chapter_ids
    Array(params[:chapter_ids]).map(&:to_i)
  end

  def append_attachment(zip, chapter, attachment, label)
    return unless attachment.attached?

    ext = attachment.blob.filename.extension_without_delimiter
    entry_name = "ch#{chapter.number.to_s.rjust(3, '0')}_#{label}.#{ext}"
    zip.put_next_entry(entry_name)
    zip.write(attachment.download)
  end
end
