# frozen_string_literal: true

module Rcfm
  module HistoriesHelper
    def rcfm_history_target(history)
      if history.target_type == 'custom_fields'
        field_type = history.scope_key.delete_prefix('custom_fields:')
        tab = CustomFieldsHelper::CUSTOM_FIELDS_TABS.find {|item| item[:name] == field_type}
        type_name = tab ? l(tab[:label]) : l(:label_custom_field_plural)
        if history.operation == 'delete' && history.target_id
          l(:rcfm_history_deleted_custom_field_target, :type => type_name, :id => history.target_id)
        else
          l(:rcfm_history_custom_fields_target, :type => type_name)
        end
      else
        name = @history_target_names && @history_target_names[history.target_id]
        if name
          l(:rcfm_history_enumeration_target, :name => name, :id => history.target_id)
        else
          l(:rcfm_history_deleted_target, :id => history.target_id)
        end
      end
    end

    def rcfm_history_operation(operation)
      key = case operation.to_s
            when 'csv_import' then :rcfm_history_operation_csv_import
            when 'delete' then :rcfm_history_operation_delete
            when /restore/ then :rcfm_history_operation_restore
            when /merge/ then :rcfm_history_operation_merge
            when /force/ then :rcfm_history_operation_force
            when /reorder/ then :rcfm_history_operation_reorder
            else :rcfm_history_operation_update
            end
      l(key)
    end

    def rcfm_history_change(change)
      if change['before'].nil?
        l(:rcfm_history_added)
      elsif change['after'].nil?
        l(:rcfm_history_deleted_change)
      else
        l(:rcfm_history_updated)
      end
    end

    def rcfm_history_state(item, target_type)
      return l(:rcfm_history_no_value) unless item

      parts = [item['name'].presence || "##{item['id']}"]
      if target_type == 'custom_field_enumerations'
        parts << (item['active'] ? l(:field_active) : l(:rcfm_state_inactive))
      end
      parts << l(:rcfm_state_position, :position => item['position']) if item.key?('position')
      parts.join(' / ')
    end

    def rcfm_restore_blocker(blocker)
      case blocker['code']
      when 'custom_field_ids_changed'
        l(:rcfm_restore_blocker_custom_field_ids)
      when 'enumeration_missing'
        l(:rcfm_restore_blocker_missing_enumeration, :id => blocker['id'])
      when 'enumeration_in_use'
        l(:rcfm_restore_blocker_used_enumeration, :id => blocker['id'])
      else
        l(:rcfm_restore_blocked)
      end
    end
  end
end
