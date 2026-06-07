class AddProgressPctToTranslationJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :translation_jobs, :progress_pct, :integer
  end
end
