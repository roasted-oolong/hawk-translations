class AddPrereadDismissedKeysToNovels < ActiveRecord::Migration[8.1]
  def change
    add_column :novels, :preread_dismissed_keys, :text, null: false, default: "[]"
  end
end
