class CreateBibleTerminologies < ActiveRecord::Migration[8.1]
  def change
    create_table :bible_terminologies do |t|
      t.references :novel, null: false, foreign_key: true, index: true

      t.string :term,        null: false
      t.string :korean_term
      t.text   :definition
      t.text   :usage_notes
      t.integer :first_appearance_chapter
      t.text   :notes
      t.datetime :last_updated_at

      t.timestamps
    end
  end
end
