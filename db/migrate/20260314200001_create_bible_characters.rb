class CreateBibleCharacters < ActiveRecord::Migration[8.1]
  def change
    create_table :bible_characters do |t|
      t.references :novel, null: false, foreign_key: true, index: true

      t.string :name,                    null: false
      t.string :korean_name
      t.text   :aliases
      t.string :role
      t.string :significance
      t.text   :physical_description
      t.text   :speech_pattern
      t.text   :honorifics_used_toward
      t.text   :honorifics_they_use
      t.text   :relationships
      t.integer :first_appearance_chapter
      t.text   :notes
      t.datetime :last_updated_at

      t.timestamps
    end
  end
end
