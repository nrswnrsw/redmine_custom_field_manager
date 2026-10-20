# frozen_string_literal: true

module RedmineCustomFieldManager
  module ModelTracking
    module CustomFieldEnumeration
      extend ActiveSupport::Concern

      module DestroyWrapper
        def destroy(reassign_to = nil)
          rcfm_lock_enumerations_revision
          super
        end
      end

      included do
        before_save :rcfm_lock_enumerations_revision
        before_destroy :rcfm_lock_enumerations_revision
        after_save :rcfm_bump_enumerations_revision
        after_destroy :rcfm_bump_enumerations_revision

        prepend DestroyWrapper unless self < DestroyWrapper
      end

      private

      def rcfm_lock_enumerations_revision
        return unless RedmineCustomFieldManager::Revision.table_exists?

        key = "custom_field_enumerations:#{custom_field_id}"
        @rcfm_enumerations_revision = RedmineCustomFieldManager::Revision.lock_for!(key)
      end

      def rcfm_bump_enumerations_revision
        @rcfm_enumerations_revision.bump! if @rcfm_enumerations_revision
      end
    end
  end
end
