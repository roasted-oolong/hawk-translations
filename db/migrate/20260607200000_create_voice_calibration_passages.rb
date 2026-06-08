class CreateVoiceCalibrationPassages < ActiveRecord::Migration[8.1]
  def change
    create_table :voice_calibration_passages do |t|
      t.references :novel, null: false, foreign_key: true
      t.string  :heading,               null: false
      t.string  :chapter_ref
      t.text    :quote,                 null: false
      t.text    :what_it_demonstrates
      t.text    :wrong_version
      t.text    :rule,                  null: false
      t.integer :position,              null: false, default: 0

      t.timestamps
    end

    add_index :voice_calibration_passages, [ :novel_id, :position ]
  end
end
