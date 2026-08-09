class CreateRenderingRules < ActiveRecord::Migration[8.1]
  def change
    create_table :rendering_rules do |t|
      # Nullable: novel_id IS NULL rows are the global (American-literary-
      # convention) defaults every novel inherits unless it overrides them.
      # A non-null novel_id row is that novel's override or addition for the
      # given rule_key.
      t.references :novel, null: true, foreign_key: true
      t.string  :rule_key,        null: false
      t.string  :name,            null: false
      t.text    :guidance,        null: false
      t.text    :example_input
      t.text    :example_output
      t.integer :position,        null: false, default: 0

      t.timestamps
    end

    # Scopes uniqueness of a novel's own rule_key — fine as a plain composite
    # index since novel_id is a real value here, not NULL.
    add_index :rendering_rules, [ :novel_id, :rule_key ], unique: true,
      name: "index_rendering_rules_on_novel_and_rule_key"

    # Postgres treats every NULL as distinct, so the composite index above
    # would silently allow duplicate rule_keys among the novel_id IS NULL
    # default rows. A partial unique index (scoped to novel_id IS NULL)
    # closes that gap and enforces "one default per rule_key" at the DB
    # layer, not just in the model validation.
    add_index :rendering_rules, :rule_key, unique: true,
      where: "novel_id IS NULL",
      name: "index_rendering_rules_on_rule_key_when_default"
  end
end
