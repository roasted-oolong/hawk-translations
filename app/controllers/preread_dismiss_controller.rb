class PrereadDismissController < ApplicationController
  before_action :set_novel

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
