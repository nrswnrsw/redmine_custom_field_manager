# frozen_string_literal: true

class AddHistoryReconstructionFields < ActiveRecord::Migration[7.2]
  # Migration-local models must not depend on the current application model.
  # rubocop:disable Rails/ApplicationRecord
  class MigrationHistory < ActiveRecord::Base
    self.table_name = 'rcfm_histories'
  end
  # rubocop:enable Rails/ApplicationRecord

  def up
    add_column :rcfm_histories, :scope_key, :string, :limit => 191
    add_column :rcfm_histories, :has_snapshot, :boolean, :null => false, :default => true

    MigrationHistory.reset_column_information
    MigrationHistory.find_each do |history|
      history.update_columns(:scope_key => scope_key(history))
    end
    change_column_null :rcfm_histories, :scope_key, false
    add_index :rcfm_histories, [:scope_key, :created_at],
              :name => 'index_rcfm_histories_on_scope_and_created_at'
  end

  def down
    remove_index :rcfm_histories, :name => 'index_rcfm_histories_on_scope_and_created_at'
    remove_column :rcfm_histories, :has_snapshot
    remove_column :rcfm_histories, :scope_key
  end

  private

  def scope_key(history)
    if history.target_type == 'custom_field_enumerations'
      "custom_field_enumerations:#{history.target_id}"
    else
      changes = JSON.parse(history.changes_json)
      "custom_fields:#{changes.fetch('field_type', 'unknown')}"
    end
  rescue JSON::ParserError
    'custom_fields:unknown'
  end
end
