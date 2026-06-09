class JobsController < ApplicationController
  def index
    @translation_jobs = TranslationJob.includes(:novel, :user).recent
    @has_active_jobs  = @translation_jobs.any?(&:cancellable?)
  end
end
