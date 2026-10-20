# frozen_string_literal: true

module RedmineCustomFieldManager
  class CustomFieldOrderUpdater
    Result = Struct.new(:changed_ids, :digest, :snapshot, keyword_init: true)

    def initialize(field_type:, ordered_ids:, base_digest:, user:, force: false,
                   confirmed_digest: nil, resolution: nil)
      @field_type = field_type.to_s
      @ordered_ids = Array(ordered_ids).map {|id| Integer(id.to_s, 10)}
      @base_digest = base_digest.to_s
      @user = user
      @force = ActiveModel::Type::Boolean.new.cast(force)
      @confirmed_digest = confirmed_digest.to_s
      @resolution = resolution.presence || (@force ? 'force' : 'normal')
      unless %w[normal merge force restore].include?(@resolution)
        raise InvalidChangeError, 'conflict resolution is invalid'
      end
    rescue ArgumentError, TypeError
      raise InvalidChangeError, 'ordered_ids must contain integer IDs only'
    end

    def call
      CustomField.transaction do
        revision = Revision.lock_for!("custom_fields:#{@field_type}")
        fields = CustomField.where(:type => @field_type).order(:position, :id).lock.to_a
        before_snapshot = Snapshot.custom_fields(:field_type => @field_type, :records => fields)
        before_digest = Snapshot.digest(before_snapshot)
        ensure_not_stale!(before_digest, before_snapshot)

        validate_order!(fields)

        changed_ids = persist_positions!(fields)
        after_snapshot = Snapshot.custom_fields(:field_type => @field_type)
        after_digest = Snapshot.digest(after_snapshot)

        if changed_ids.any?
          revision.bump!
          HistoryRecorder.record!(
            :scope_key => "custom_fields:#{@field_type}",
            :target_type => 'custom_fields',
            :target_id => nil,
            :operation => @resolution == 'normal' ? 'reorder' : "reorder_#{@resolution}",
            :user => @user,
            :base_digest => before_digest,
            :result_digest => after_digest,
            :before_snapshot => before_snapshot,
            :after_snapshot => after_snapshot,
            :metadata => {
              'field_type' => @field_type,
              'changed_ids' => changed_ids,
              'resolution' => @resolution
            }
          )
        end

        Result.new(:changed_ids => changed_ids, :digest => after_digest, :snapshot => after_snapshot)
      end
    end

    private

    def ensure_not_stale!(current_digest, current_snapshot)
      return if ActiveSupport::SecurityUtils.secure_compare(current_digest, @base_digest)
      if @force && ActiveSupport::SecurityUtils.secure_compare(current_digest, @confirmed_digest)
        return
      end

      raise ConflictError.new(
        :current_digest => current_digest,
        :current_snapshot => current_snapshot
      )
    end

    def validate_order!(fields)
      unless fields.any? && fields.all? {|field| field.type == @field_type}
        raise InvalidChangeError, 'unknown custom field type'
      end

      current_ids = fields.map(&:id)
      if @ordered_ids.length != @ordered_ids.uniq.length
        raise InvalidChangeError, 'ordered_ids contains duplicates'
      end
      unless @ordered_ids.sort == current_ids.sort
        raise InvalidChangeError, 'ordered_ids must contain every field in the selected type exactly once'
      end
    end

    def persist_positions!(fields)
      requested_by_id = fields.index_by(&:id)
      requested = @ordered_ids.map {|id| requested_by_id.fetch(id)}
      positions = requested.each_with_index.filter_map do |field, index|
        [field.id, index + 1] unless field.position == index + 1
      end.to_h
      BulkUpdater.update_attribute(CustomField.all, :position, positions)
      positions.keys
    end
  end
end
