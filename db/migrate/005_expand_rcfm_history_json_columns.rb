# frozen_string_literal: true

class ExpandRcfmHistoryJsonColumns < ActiveRecord::Migration[7.2]
  LONG_TEXT_LIMIT = 4.gigabytes - 1

  def up
    change_column :rcfm_histories, :changes_json, :text, :null => false, :limit => LONG_TEXT_LIMIT
    change_column :rcfm_histories, :snapshot_json, :text, :null => false, :limit => LONG_TEXT_LIMIT
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'shrinking history JSON columns could truncate existing snapshots'
  end
end
