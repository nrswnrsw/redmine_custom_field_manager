# frozen_string_literal: true

class CreateRcfmHistories < ActiveRecord::Migration[7.2]
  def change
    create_table :rcfm_histories do |t|
      t.string :target_type, :null => false, :limit => 40
      t.integer :target_id
      t.integer :user_id
      t.string :operation, :null => false, :limit => 40
      t.string :base_digest, :null => false, :limit => 64
      t.string :result_digest, :null => false, :limit => 64
      t.text :changes_json, :null => false
      t.text :snapshot_json, :null => false
      t.datetime :created_at, :null => false
    end

    add_index :rcfm_histories, [:target_type, :target_id, :created_at],
              :name => 'index_rcfm_histories_on_target_and_created_at'
    add_index :rcfm_histories, :user_id
  end
end
