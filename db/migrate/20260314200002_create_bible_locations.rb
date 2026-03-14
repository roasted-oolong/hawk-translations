class CreateBibleLocations < ActiveRecord::Migration[8.1]
  def change
    create_table :bible_locations do |t|
      t.references :novel, null: false, foreign_key: true, index: true

      t.string :name,          null: false
      t.string :korean_name
      t.string :location_type
      t.text   :description
      t.text   :significance
      t.integer :first_appearance_chapter
      t.text   :notes
      t.datetime :last_updated_at

      t.timestamps
    end
  end
end
