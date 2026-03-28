class ChaptersController < ApplicationController
  before_action :set_novel
  before_action :set_chapter, only: [ :show, :edit, :update, :destroy,
                                      :download_korean_source, :download_translated_output ]

  def index
    @chapters = @novel.chapters.by_number
  end

  def show; end

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
    redirect_to novel_chapters_path(@novel), notice: "Chapter removed."
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

  private

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
      redirect_to novel_chapter_path(@novel, @chapter), notice: "Chapter created."
    else
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

      chapter = @novel.chapters.build(number: number)
      attach_file(chapter, file, classification[:language])

      if chapter.save
        created << chapter
      else
        failures << "#{file.original_filename} — #{chapter.errors.full_messages.to_sentence}"
      end
    end

    notice = "#{created.size} chapter(s) uploaded."
    alert  = failures.any? ? "Some files were skipped: #{failures.join('; ')}" : nil

    redirect_to novel_chapters_path(@novel), notice: notice, alert: alert
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
end
