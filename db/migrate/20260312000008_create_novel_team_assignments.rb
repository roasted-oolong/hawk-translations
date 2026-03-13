class CreateNovelTeamAssignments < ActiveRecord::Migration[8.1]
  def change
    create_table :novel_team_assignments do |t|
      t.references :novel, null: false, foreign_key: true
      t.references :team,  null: false, foreign_key: true
      t.string     :permission_level, null: false

      t.timestamps
    end

    add_index :novel_team_assignments, [ :novel_id, :team_id ], unique: true
  end
end
