# frozen_string_literal: true

module RedmineCustomFieldManager
  class History < ApplicationRecord
    self.table_name = "#{table_name_prefix}rcfm_histories#{table_name_suffix}"

    validates :target_type, :operation, :base_digest, :result_digest,
              :changes_json, :snapshot_json, :scope_key, :presence => true

    belongs_to :user, :class_name => '::User', :optional => true

    def reconstructed_snapshot
      HistoryReconstructor.new(self).snapshot
    end

    def parsed_changes
      JSON.parse(changes_json)
    end
  end
end
