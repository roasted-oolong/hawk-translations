class BibleImportController < ApplicationController
  before_action :set_novel

  def create
    approved = JSON.parse(params[:approved_entries].to_s)
    skipped  = JSON.parse(params[:skipped_entries].to_s)
    count    = 0

    approved.each do |item|
      if item.is_a?(Hash)
        # "bible_category" (characters/locations/.../story) is the section selector set
        # by the JS payload — kept distinct from "category", which story entries use as
        # their own field (main_plot/subplot/etc). Stripping "category" here would have
        # silently dropped that field from every story entry's attrs.
        category = item["bible_category"]
        attrs    = item.except("bible_category", "korean_key").transform_keys(&:to_sym)
        count += 1 if import_entry(category, attrs)
      else
        pending  = @pending ||= BibleMarkdownParser.new(@novel).pending_entries
        category, key = item.split(":", 2)
        entry = pending[category.to_sym]&.find { |e| e[:korean_key] == key }
        next unless entry
        count += 1 if import_entry(category, entry.except(:korean_key))
      end
    end

    @novel.append_preread_dismissed_key!(*skipped) if skipped.any?

    redirect_to novel_path(@novel),
      notice: "#{count} #{"entry".pluralize(count)} imported into the bible."
  rescue JSON::ParserError
    redirect_to novel_preread_review_path(@novel), alert: "Invalid import data."
  end

  private

  def set_novel
    @novel = Novel.find(params[:novel_id])
  end

  def import_entry(category, attrs)
    existing_id = attrs.delete(:existing_id)
    attrs.delete(:is_existing)
    attrs.delete(:field_changes)

    record = if existing_id
      find_record(category, existing_id)&.tap { |r| r.assign_attributes(attrs) }
    else
      build_record(category, attrs)
    end
    record&.save
  rescue ArgumentError
    false
  end

  def find_record(category, id)
    case category
    when "characters"       then @novel.bible_characters.find_by(id: id)
    when "locations"        then @novel.bible_locations.find_by(id: id)
    when "terminology"      then @novel.bible_terminologies.find_by(id: id)
    when "cultural_phrases" then @novel.bible_cultural_phrases.find_by(id: id)
    when "story"            then @novel.bible_story_entries.find_by(id: id)
    end
  end

  def build_record(category, attrs)
    case category
    when "characters"       then @novel.bible_characters.build(attrs)
    when "locations"        then @novel.bible_locations.build(attrs)
    when "terminology"      then @novel.bible_terminologies.build(attrs)
    when "cultural_phrases" then @novel.bible_cultural_phrases.build(attrs)
    when "story"            then @novel.bible_story_entries.build(attrs)
    end
  end
end
