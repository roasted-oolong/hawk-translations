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

  # Handles both single-file and bulk uploads.
  # Bulk: multiple korean_source files → creates one chapter record per file.
  # Single: one korean_source file → standard create.
  def create
    files = Array(chapter_params[:korean_source]).compact_blank

    if files.many?
      create_bulk(files)
    else
      create_single
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

  # Params for creating a new chapter (includes file uploads)
  def chapter_params
    params.require(:chapter).permit(:number, :title, :status, korean_source: [])
  end

  # Params for updating an existing chapter (status only — files attached separately)
  def chapter_update_params
    params.require(:chapter).permit(:title, :status, :korean_source, :translated_output)
  end

  def create_single
    @chapter = @novel.chapters.build(
      number: chapter_params[:number],
      title:  chapter_params[:title],
      status: chapter_params[:status].presence || "untranslated"
    )

    file = Array(chapter_params[:korean_source]).first
    @chapter.korean_source.attach(file) if file.present?

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
      number = extract_chapter_number(file.original_filename)

      if number.nil?
        failures << "#{file.original_filename} — could not parse chapter number"
        next
      end

      chapter = @novel.chapters.build(number: number, status: "untranslated")
      chapter.korean_source.attach(file)

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

  # Parses chapter number from filenames like:
  #   ch1_korean, ch74_korean
  #   Chapter_1 - The Super Manager's Regression.txt
  #   Chapter_68 - Script Reading(1).txt
  #   Chapter_10.txt
  def extract_chapter_number(filename)
    base = File.basename(filename, ".*")

    # ch1_korean, ch74_korean
    if base =~ /\Ach(\d+)_korean\z/i
      return $1.to_i
    end

    # Chapter_1, Chapter_68 - Script Reading(1), Chapter_10
    if base =~ /\AChapter_(\d+)/i
      return $1.to_i
    end

    nil
  end
end
