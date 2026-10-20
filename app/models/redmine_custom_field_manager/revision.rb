# frozen_string_literal: true

module RedmineCustomFieldManager
  class Revision < ApplicationRecord
    self.table_name = "#{table_name_prefix}rcfm_revisions#{table_name_suffix}"

    validates :scope_key, :presence => true

    def self.lock_for!(scope_key)
      create_or_find_by!(:scope_key => scope_key).lock!
    end

    def bump!
      update_columns(
        :sequence => sequence + 1,
        :updated_at => Time.current
      )
    end
  end
end
