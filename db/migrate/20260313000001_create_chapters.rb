class CreateChapters < ActiveRecord::Migration[8.1]
  def change
    create_table :chapters do |t|
      t.references :novel,  null: false, foreign_key: true
      t.integer    :number, null: false
      t.string     :title
      t.string     :status, null: false, default: "untranslated"

      t.timestamps
    end

    add_index :chapters, [ :novel_id, :number ], unique: true
  end
end
