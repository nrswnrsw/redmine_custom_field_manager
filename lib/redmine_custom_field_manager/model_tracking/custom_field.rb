# frozen_string_literal: true

module RedmineCustomFieldManager
  module ModelTracking
    module CustomField
      extend ActiveSupport::Concern

      included do
        before_save :rcfm_lock_custom_fields_revision
        before_destroy :rcfm_lock_custom_fields_revision
        after_save :rcfm_bump_custom_fields_revision
        after_destroy :rcfm_bump_custom_fields_revision
      end

      private

      def rcfm_lock_custom_fields_revision
        return unless RedmineCustomFieldManager::Revision.table_exists?

        key = "custom_fields:#{type}"
        @rcfm_custom_fields_revision = RedmineCustomFieldManager::Revision.lock_for!(key)
        rcfm_lock_field_enumerations_revision if field_format == 'enumeration'
      end

      def rcfm_bump_custom_fields_revision
        @rcfm_custom_fields_revision.bump! if @rcfm_custom_fields_revision
        @rcfm_field_enumerations_revision.bump! if @rcfm_field_enumerations_revision
      end

      def rcfm_lock_field_enumerations_revision
        return unless persisted?

        key = "custom_field_enumerations:#{id}"
        @rcfm_field_enumerations_revision = RedmineCustomFieldManager::Revision.lock_for!(key)
      end
    end
  end
end
