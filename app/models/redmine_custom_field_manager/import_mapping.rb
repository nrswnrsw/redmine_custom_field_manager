# frozen_string_literal: true

module RedmineCustomFieldManager
  class ImportMapping < ApplicationRecord
    self.table_name = "#{table_name_prefix}rcfm_import_mappings#{table_name_suffix}"

    validates :source_instance_id, :source_field_id, :source_enumeration_id,
              :target_custom_field_id, :target_enumeration_id, :presence => true
  end
end
