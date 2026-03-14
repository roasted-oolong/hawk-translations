class CreateBibleCulturalPhrases < ActiveRecord::Migration[8.1]
  def change
    create_table :bible_cultural_phrases do |t|
      t.references :novel, null: false, foreign_key: true, index: true

      t.string :phrase,                  null: false
      t.string :korean_phrase
      t.text   :literal_translation
      t.text   :intended_meaning
      t.text   :context
      t.string :established_translation
      t.integer :first_appearance_chapter
      t.text   :notes
      t.datetime :last_updated_at

      t.timestamps
    end
  end
end
