# frozen_string_literal: true

module RedmineCustomFieldManager
  class EnumerationUpdater
    MAX_NAME_LENGTH = 60

    Result = Struct.new(:changed_ids, :created_ids, :digest, :snapshot, keyword_init: true)

    def initialize(custom_field:, items:, base_digest:, user:, force: false, confirmed_digest: nil,
                   resolution: nil)
      @custom_field = custom_field
      @items = normalize_items(items)
      @base_digest = base_digest.to_s
      @user = user
      @force = ActiveModel::Type::Boolean.new.cast(force)
      @confirmed_digest = confirmed_digest.to_s
      @resolution = resolution.presence || (@force ? 'force' : 'normal')
      unless %w[normal merge force restore csv_import].include?(@resolution)
        raise InvalidChangeError, 'change operation is invalid'
      end
    end

    def call
      CustomFieldEnumeration.transaction do
        revision = Revision.lock_for!(revision_key)
        @custom_field.lock!
        ensure_enumeration_field!

        current_records = @custom_field.enumerations.reorder(:position, :id).lock.to_a
        before_snapshot = Snapshot.enumerations(@custom_field, current_records)
        before_digest = Snapshot.digest(before_snapshot)
        ensure_not_stale!(before_digest, before_snapshot)
        validate_items!(current_records)
        ensure_deletions_are_safe!(current_records)

        changed_ids, created_ids = persist_items!(current_records)
        after_snapshot = Snapshot.enumerations(@custom_field.reload)
        after_digest = Snapshot.digest(after_snapshot)

        if changed_ids.any? || created_ids.any?
          revision.bump!
          HistoryRecorder.record!(
            :scope_key => revision_key,
            :target_type => 'custom_field_enumerations',
            :target_id => @custom_field.id,
            :operation => @resolution == 'normal' ? 'update' : @resolution,
            :user => @user,
            :base_digest => before_digest,
            :result_digest => after_digest,
            :before_snapshot => before_snapshot,
            :after_snapshot => after_snapshot,
            :metadata => {
              'changed_ids' => changed_ids,
              'created_ids' => created_ids,
              'resolution' => @resolution
            }
          )
        end

        Result.new(
          :changed_ids => changed_ids,
          :created_ids => created_ids,
          :digest => after_digest,
          :snapshot => after_snapshot
        )
      end
    end

    private

    def revision_key
      "custom_field_enumerations:#{@custom_field.id}"
    end

    def normalize_items(items)
      Array(items).map.with_index do |attributes, index|
        attributes = if attributes.respond_to?(:to_unsafe_h)
                       attributes.to_unsafe_h
                     else
                       attributes.to_h
                     end.stringify_keys
        id = attributes['id'].presence
        {
          'client_id' => attributes['client_id'].presence || id || "new-#{index}",
          'id' => id && Integer(id.to_s, 10),
          'name' => attributes['name'].to_s,
          'active' => ActiveModel::Type::Boolean.new.cast(attributes['active']),
          'deleted' => ActiveModel::Type::Boolean.new.cast(attributes['deleted'])
        }
      end
    rescue ArgumentError, TypeError
      raise InvalidChangeError, 'enumeration IDs must be integers'
    end

    def ensure_enumeration_field!
      return if @custom_field.field_format == 'enumeration'

      raise InvalidChangeError, 'the custom field is not a key/value list'
    end

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

    def validate_items!(current_records)
      client_ids = @items.map {|item| item.fetch('client_id').to_s}
      if client_ids.length != client_ids.uniq.length
        raise InvalidChangeError, 'client_id contains duplicates'
      end

      persisted_items = @items.select {|item| item['id']}
      persisted_ids = persisted_items.map {|item| item.fetch('id')}
      if persisted_ids.length != persisted_ids.uniq.length
        raise InvalidChangeError, 'enumeration IDs contain duplicates'
      end
      unless persisted_ids.sort == current_records.map(&:id).sort
        raise InvalidChangeError, 'items must contain every current enumeration exactly once'
      end

      @items.reject {|item| item['deleted']}.each do |item|
        if item['name'].blank?
          raise InvalidChangeError, 'enumeration names cannot be blank'
        end
        if item['name'].length > MAX_NAME_LENGTH
          raise InvalidChangeError, "enumeration names cannot exceed #{MAX_NAME_LENGTH} characters"
        end
      end
    end

    def ensure_deletions_are_safe!(current_records)
      records_by_id = current_records.index_by(&:id)
      protected_items = @items.filter_map do |item|
        next unless item['deleted'] && item['id']

        record = records_by_id.fetch(item['id'])
        reasons = EnumerationUsage.new(record).reasons
        next if reasons.empty?

        {'id' => record.id, 'name' => record.name, 'reasons' => reasons}
      end
      raise ProtectedDeletionError, protected_items if protected_items.any?
    end

    def persist_items!(current_records)
      records_by_id = current_records.index_by(&:id)
      changed_ids = []
      created_ids = {}
      kept_items = @items.reject {|item| item['deleted']}
      deleted_ids = @items.filter_map {|item| item['id'] if item['deleted']}

      if deleted_ids.any?
        if defined?(ImportMapping) && ImportMapping.table_exists?
          ImportMapping.where(:target_enumeration_id => deleted_ids).delete_all
        end
        CustomFieldEnumeration.where(
          :id => deleted_ids,
          :custom_field_id => @custom_field.id
        ).delete_all
        changed_ids.concat(deleted_ids)
      end

      names = {}
      active_states = {}
      kept_items.each do |item|
        if item['id']
          record = records_by_id.fetch(item['id'])
          names[record.id] = item['name'] if record.name != item['name']
          active_states[record.id] = item['active'] if record.active? != item['active']
          changed_ids << record.id if names.key?(record.id) || active_states.key?(record.id)
          item['record'] = record
        else
          record = @custom_field.enumerations.create!(
            :name => item['name'],
            :active => item['active']
          )
          item['record'] = record
          created_ids[item['client_id']] = record.id
        end
      end
      relation = CustomFieldEnumeration.where(:custom_field_id => @custom_field.id)
      BulkUpdater.update_attribute(relation, :name, names)
      BulkUpdater.update_attribute(relation, :active, active_states)

      positions = {}
      kept_items.each_with_index do |item, index|
        record = item.fetch('record')
        position = index + 1
        next if record.position == position

        positions[record.id] = position
        changed_ids << record.id if item['id']
      end
      BulkUpdater.update_attribute(relation, :position, positions)

      [changed_ids.uniq, created_ids]
    end
  end
end
