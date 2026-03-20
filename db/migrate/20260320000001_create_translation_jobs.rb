class CreateTranslationJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :translation_jobs do |t|
      t.references :novel, null: false, foreign_key: true
      t.references :user,  null: false, foreign_key: true

      t.string  :job_type,       null: false
      t.string  :status,         null: false, default: "queued"
      t.integer :chapter_start
      t.integer :chapter_end
      t.text    :result_payload
      t.string  :solid_queue_job_id

      t.timestamps
    end

    add_index :translation_jobs, :status
    add_index :translation_jobs, :job_type
    add_index :translation_jobs, [ :novel_id, :created_at ]
  end
end
