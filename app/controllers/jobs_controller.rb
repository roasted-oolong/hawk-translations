class JobsController < ApplicationController
  def index
    @translation_jobs = TranslationJob.includes(:novel, :user).recent
  end
end
