# frozen_string_literal: true

module RedmineCustomFieldManager
  class HistoryRestorer
    Preview = Struct.new(
      :history, :scope_key, :target_type, :target_id, :desired_snapshot,
      :current_snapshot, :items, :diffs, :blockers, :base_digest, :plan_digest,
      keyword_init: true
    )

    def initialize(history:, user:)
      @history = history
      @user = user
    end

    def preview
      if @history.operation == 'delete'
        raise InvalidChangeError, 'custom field deletion histories are audit-only'
      end

      desired = HistoryReconstructor.new(@history).snapshot
      if @history.target_type == 'custom_fields'
        custom_field_preview(desired)
      elsif @history.target_type == 'custom_field_enumerations'
        enumeration_preview(desired)
      else
        raise InvalidChangeError, 'history target is not supported'
      end
    end

    def apply!(base_digest:, plan_digest:)
      plan = preview
      raise InvalidChangeError, plan.blockers.join('; ') if plan.blockers.any?
      unless secure_equal?(plan.plan_digest, plan_digest.to_s)
        raise InvalidChangeError, 'restore preview is no longer current'
      end

      if plan.target_type == 'custom_fields'
        field_type = plan.scope_key.delete_prefix('custom_fields:')
        CustomFieldOrderUpdater.new(
          :field_type => field_type,
          :ordered_ids => plan.items,
          :base_digest => base_digest,
          :user => @user,
          :resolution => 'restore'
        ).call
      else
        field = CustomField.find(plan.target_id)
        EnumerationUpdater.new(
          :custom_field => field,
          :items => plan.items,
          :base_digest => base_digest,
          :user => @user,
          :resolution => 'restore'
        ).call
      end
    end

    private

    def custom_field_preview(desired)
      field_type = @history.scope_key.delete_prefix('custom_fields:')
      current = Snapshot.custom_fields(:field_type => field_type)
      desired_ids = desired.map {|item| item.fetch('id')}
      current_ids = current.map {|item| item.fetch('id')}
      blockers = []
      if desired_ids.sort != current_ids.sort
        blockers << {'code' => 'custom_field_ids_changed'}
      end
      build_preview(
        :desired => desired,
        :current => current,
        :items => desired_ids,
        :blockers => blockers,
        :target_id => nil
      )
    end

    def enumeration_preview(desired)
      field = CustomField.find(@history.target_id)
      current_records = field.enumerations.reorder(:position, :id).to_a
      current = Snapshot.enumerations(field, current_records)
      current_by_id = current_records.index_by(&:id)
      desired_ids = desired.map {|item| item.fetch('id')}
      missing_ids = desired_ids - current_by_id.keys
      blockers = missing_ids.map {|id| {'code' => 'enumeration_missing', 'id' => id}}
      items = desired.map do |item|
        {
          'client_id' => item.fetch('id').to_s,
          'id' => item.fetch('id'),
          'name' => item.fetch('name'),
          'active' => item.fetch('active'),
          'deleted' => false
        }
      end
      (current_by_id.keys - desired_ids).each do |id|
        record = current_by_id.fetch(id)
        reasons = EnumerationUsage.new(record).reasons
        blockers << {'code' => 'enumeration_in_use', 'id' => id, 'reasons' => reasons} if reasons.any?
        items << {
          'client_id' => id.to_s,
          'id' => id,
          'name' => record.name,
          'active' => record.active?,
          'deleted' => true
        }
      end
      build_preview(
        :desired => desired,
        :current => current,
        :items => items,
        :blockers => blockers,
        :target_id => field.id
      )
    rescue ActiveRecord::RecordNotFound
      raise InvalidChangeError, 'the target custom field no longer exists'
    end

    def build_preview(desired:, current:, items:, blockers:, target_id:)
      base_digest = Snapshot.digest(current)
      diffs = HistoryRecorder.diff(current, desired)
      plan_digest = Snapshot.digest(
        'history_id' => @history.id,
        'current' => current,
        'desired' => desired,
        'blockers' => blockers
      )
      Preview.new(
        :history => @history,
        :scope_key => @history.scope_key,
        :target_type => @history.target_type,
        :target_id => target_id,
        :desired_snapshot => desired,
        :current_snapshot => current,
        :items => items,
        :diffs => diffs,
        :blockers => blockers,
        :base_digest => base_digest,
        :plan_digest => plan_digest
      )
    end

    def secure_equal?(left, right)
      left.bytesize == right.bytesize && ActiveSupport::SecurityUtils.secure_compare(left, right)
    end
  end
end
