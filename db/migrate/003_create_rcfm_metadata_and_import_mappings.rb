# frozen_string_literal: true

class CreateRcfmMetadataAndImportMappings < ActiveRecord::Migration[7.2]
  def change
    create_table :rcfm_metadata do |t|
      t.string :key, :null => false, :limit => 191
      t.text :value, :null => false
      t.timestamps :null => false
    end
    add_index :rcfm_metadata, :key, :unique => true

    create_table :rcfm_import_mappings do |t|
      t.string :source_instance_id, :null => false, :limit => 64
      t.string :source_field_id, :null => false, :limit => 64
      t.string :source_enumeration_id, :null => false, :limit => 64
      t.integer :target_custom_field_id, :null => false
      t.integer :target_enumeration_id, :null => false
      t.timestamps :null => false
    end
    add_index :rcfm_import_mappings,
              [:source_instance_id, :source_field_id, :source_enumeration_id, :target_custom_field_id],
              :unique => true,
              :name => 'idx_rcfm_import_mappings_source_target'
    add_index :rcfm_import_mappings, :target_enumeration_id,
              :name => 'idx_rcfm_import_mappings_target_enum'
  end
end
