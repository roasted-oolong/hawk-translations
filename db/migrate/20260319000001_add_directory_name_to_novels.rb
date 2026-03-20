class AddDirectoryNameToNovels < ActiveRecord::Migration[8.1]
  def change
    # directory_name is the filesystem directory name for the novel
    # (e.g. "idols-rewind"), used by PipelineDispatcher to locate the
    # novel's files on disk. Distinct from title, which is UI display text.
    #
    # null: true initially so existing rows are valid during migration.
    # A follow-up change_column_null tightens the constraint after the
    # existing record has been backfilled by the import script.
    add_column :novels, :directory_name, :string

    add_index :novels, [ :organization_id, :directory_name ], unique: true
  end
end
