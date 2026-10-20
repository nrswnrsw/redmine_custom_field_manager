# frozen_string_literal: true

module RedmineCustomFieldManager
  module ModelTracking
    module CustomValue
      extend ActiveSupport::Concern

      included do
        before_save :rcfm_lock_and_validate_enumeration_usage
        before_destroy :rcfm_lock_enumerations_revision
      end

      private

      def rcfm_lock_and_validate_enumeration_usage
        return unless new_record? || will_save_change_to_value? || will_save_change_to_custom_field_id?

        field_ids = [custom_field_id]
        field_ids << custom_field_id_in_database if respond_to?(:custom_field_id_in_database)
        rcfm_lock_enumerations_revisions(field_ids)

        field = ::CustomField.find_by(:id => custom_field_id)
        return unless field && field.field_format == 'enumeration'
        return if value.blank?
        return if field.enumerations.where(:id => value.to_s).exists?

        errors.add(:value, :inclusion)
        raise ActiveRecord::RecordInvalid, self
      end

      def rcfm_lock_enumerations_revision
        return unless RedmineCustomFieldManager::Revision.table_exists?

        rcfm_lock_enumerations_revisions([custom_field_id])
      end

      def rcfm_lock_enumerations_revisions(field_ids)
        return unless RedmineCustomFieldManager::Revision.table_exists?

        ::CustomField.where(:id => field_ids.compact.uniq, :field_format => 'enumeration')
                     .order(:id).pluck(:id).each do |field_id|
          RedmineCustomFieldManager::Revision.lock_for!("custom_field_enumerations:#{field_id}")
        end
      end
    end
  end
end
