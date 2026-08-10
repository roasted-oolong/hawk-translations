class PrereadDismissController < ApplicationController
  before_action :set_novel

  # Dismiss a single pending preread suggestion immediately — the standalone
  # counterpart to skipping inside the /preread_review slideshow, which only
  # persists once the whole batch is submitted via bible_import#create.
  def create
    key = params.require(:key)
    @novel.append_preread_dismissed_key!(key)
    redirect_back fallback_location: novel_path(@novel), notice: "Suggestion dismissed."
  end

  def destroy
    key      = params.require(:key)
    existing = JSON.parse(@novel.preread_dismissed_keys || "[]") rescue []
    @novel.update_column(:preread_dismissed_keys, existing.reject { |k| k == key }.to_json)
    redirect_back fallback_location: novel_path(@novel), notice: "Entry restored to pending queue."
  end

  private

  def set_novel
    @novel = Novel.find(params[:novel_id])
  end
end
