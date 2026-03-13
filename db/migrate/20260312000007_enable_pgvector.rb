class EnablePgvector < ActiveRecord::Migration[8.1]
  def up
    enable_extension "vector"
  end

  def down
    disable_extension "vector"
  end
end
