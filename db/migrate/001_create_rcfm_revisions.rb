# frozen_string_literal: true

class CreateRcfmRevisions < ActiveRecord::Migration[7.2]
  def change
    create_table :rcfm_revisions do |t|
      t.string :scope_key, :null => false, :limit => 191
      t.integer :sequence, :null => false, :default => 0
      t.timestamps :null => false
    end

    add_index :rcfm_revisions, :scope_key, :unique => true
  end
end
