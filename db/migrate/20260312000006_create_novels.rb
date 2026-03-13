class CreateNovels < ActiveRecord::Migration[8.1]
  def change
    create_table :novels do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :series,       null: true,  foreign_key: true
      t.bigint     :poc_user_id,  null: true
      t.string     :title,        null: false
      t.string     :korean_title
      t.string     :genre
      t.text       :summary
      t.text       :tone
      t.text       :notes
      t.string     :visibility,   null: false, default: "discoverable"

      t.timestamps
    end

    add_foreign_key :novels, :users, column: :poc_user_id
    add_index :novels, :poc_user_id
  end
end
