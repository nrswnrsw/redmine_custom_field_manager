# frozen_string_literal: true

module RedmineCustomFieldManager
  class Metadata < ApplicationRecord
    self.table_name = "#{table_name_prefix}rcfm_metadata#{table_name_suffix}"

    validates :key, :value, :presence => true
  end
end
