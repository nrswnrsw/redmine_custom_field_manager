# frozen_string_literal: true

module RedmineCustomFieldManager
  module ModelTracking
    module CustomField
      extend ActiveSupport::Concern

      included do
        before_save :rcfm_lock_custom_fields_revision
        before_destroy :rcfm_lock_and_prepare_custom_field_deletion, :prepend => true
        after_save :rcfm_bump_custom_fields_revision
        after_destroy :rcfm_bump_custom_fields_revision
        after_destroy :rcfm_record_custom_field_deletion_history
      end

      private

      def rcfm_lock_custom_fields_revision
        return unless RedmineCustomFieldManager::Revision.table_exists?

        key = "custom_fields:#{type}"
        @rcfm_custom_fields_revision = RedmineCustomFieldManager::Revision.lock_for!(key)
        rcfm_lock_field_enumerations_revision if field_format == 'enumeration'
      end

      def rcfm_lock_and_prepare_custom_field_deletion
        rcfm_lock_custom_fields_revision
        rcfm_prepare_custom_field_deletion_history
      end

      def rcfm_bump_custom_fields_revision
        @rcfm_custom_fields_revision.bump! if @rcfm_custom_fields_revision
        @rcfm_field_enumerations_revision.bump! if @rcfm_field_enumerations_revision
      end

      def rcfm_prepare_custom_field_deletion_history
        return unless RedmineCustomFieldManager::History.table_exists?

        before_snapshot = RedmineCustomFieldManager::Snapshot.custom_fields(:field_type => type)
        @rcfm_custom_field_deletion_history = {
          :before_snapshot => before_snapshot,
          :base_digest => RedmineCustomFieldManager::Snapshot.digest(before_snapshot),
          :metadata => {
            'field_name' => name,
            'field_format' => field_format,
            'custom_values_count' => custom_values.count,
            'enumeration_count' => enumerations.count,
            'restorable' => false
          }
        }
      end

      def rcfm_record_custom_field_deletion_history
        deletion = @rcfm_custom_field_deletion_history
        return unless deletion

        after_snapshot = RedmineCustomFieldManager::Snapshot.custom_fields(:field_type => type)
        RedmineCustomFieldManager::HistoryRecorder.record!(
          :scope_key => "custom_fields:#{type}",
          :target_type => 'custom_fields',
          :target_id => id,
          :operation => 'delete',
          :user => User.current,
          :base_digest => deletion.fetch(:base_digest),
          :result_digest => RedmineCustomFieldManager::Snapshot.digest(after_snapshot),
          :before_snapshot => deletion.fetch(:before_snapshot),
          :after_snapshot => after_snapshot,
          :metadata => deletion.fetch(:metadata)
        )
      end

      def rcfm_lock_field_enumerations_revision
        return unless persisted?

        key = "custom_field_enumerations:#{id}"
        @rcfm_field_enumerations_revision = RedmineCustomFieldManager::Revision.lock_for!(key)
      end
    end
  end
end
