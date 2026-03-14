class CreateBibleStoryEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :bible_story_entries do |t|
      t.references :novel, null: false, foreign_key: true, index: true

      t.string :category, null: false
      t.string :title,    null: false
      t.text   :content
      t.integer :first_appearance_chapter
      t.text   :notes
      t.datetime :last_updated_at

      t.timestamps
    end
  end
end
