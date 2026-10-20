# frozen_string_literal: true

module RedmineCustomFieldManager
  module ModelTracking
    module CustomValue
      extend ActiveSupport::Concern

      included do
        before_validation :rcfm_lock_enumerations_revision
        before_destroy :rcfm_lock_enumerations_revision
        after_save :rcfm_bump_enumerations_revision
        after_destroy :rcfm_bump_enumerations_revision
      end

      private

      def rcfm_lock_enumerations_revision
        return unless RedmineCustomFieldManager::Revision.table_exists?
        return unless custom_field && custom_field.field_format == 'enumeration'

        key = "custom_field_enumerations:#{custom_field_id}"
        @rcfm_enumerations_revision = RedmineCustomFieldManager::Revision.lock_for!(key)
      end

      def rcfm_bump_enumerations_revision
        @rcfm_enumerations_revision.bump! if @rcfm_enumerations_revision
      end
    end
  end
end
