# frozen_string_literal: true

module RedmineCustomFieldManager
  module ConflictAnalysis
    module_function

    def custom_fields(base_snapshot:, mine_ids:, current_snapshot:, base_digest:)
      base = normalize_snapshot(base_snapshot)
      mine_ids = Array(mine_ids).map {|id| Integer(id.to_s, 10)}
      current = normalize_snapshot(current_snapshot)
      valid_base = valid_base?(base, base_digest)
      mine = order_snapshot(mine_ids, base, current)
      proposal = custom_field_proposal(base, mine_ids, current, valid_base)
      proposal_snapshot = proposal && order_snapshot(proposal, base, current)

      response(base, mine, current, proposal, valid_base, proposal_snapshot)
    rescue ArgumentError, TypeError
      response([], [], normalize_snapshot(current_snapshot), nil, false)
    end

    def enumerations(base_snapshot:, mine_items:, current_snapshot:, base_digest:)
      base = normalize_snapshot(base_snapshot)
      current = normalize_snapshot(current_snapshot)
      mine = normalize_mine_items(mine_items)
      valid_base = valid_base?(base, base_digest)
      proposal = enumeration_proposal(base, mine, current, valid_base)
      proposal_snapshot = proposal && mine_snapshot(normalize_mine_items(proposal))

      response(base, mine_snapshot(mine), current, proposal, valid_base, proposal_snapshot)
    rescue ArgumentError, TypeError
      response([], [], normalize_snapshot(current_snapshot), nil, false)
    end

    def normalize_snapshot(snapshot)
      Array(snapshot).map do |item|
        item = safe_hash(item).stringify_keys
        item.slice('id', 'type', 'name', 'active', 'position').tap do |normalized|
          normalized['id'] = Integer(normalized.fetch('id').to_s, 10)
          normalized['position'] = Integer(normalized.fetch('position').to_s, 10)
          normalized['active'] = ActiveModel::Type::Boolean.new.cast(normalized['active']) if normalized.key?('active')
        end
      end
    end

    def normalize_mine_items(items)
      kept_position = 0
      Array(items).map.with_index do |item, index|
        item = safe_hash(item).stringify_keys
        deleted = ActiveModel::Type::Boolean.new.cast(item['deleted'])
        kept_position += 1 unless deleted
        id = item['id'].present? ? Integer(item['id'].to_s, 10) : nil
        {
          'key' => id ? id.to_s : "new:#{item['client_id'].presence || index}",
          'client_id' => item['client_id'].presence || id&.to_s || "new-#{index}",
          'id' => id,
          'name' => item['name'].to_s,
          'active' => ActiveModel::Type::Boolean.new.cast(item['active']),
          'deleted' => deleted,
          'position' => deleted ? nil : kept_position
        }
      end
    end

    def valid_base?(base, base_digest)
      return false if base.empty? && base_digest.blank?

      digest = Snapshot.digest(base)
      digest.bytesize == base_digest.to_s.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(digest, base_digest.to_s)
    end

    def order_snapshot(ids, base, current)
      records = (base + current).index_by {|item| item.fetch('id')}
      ids.map.with_index do |id, index|
        record = records[id]
        next {'id' => id, 'position' => index + 1} unless record

        record.merge('position' => index + 1)
      end
    end

    def custom_field_proposal(base, mine_ids, current, valid_base)
      return unless valid_base

      base_ids = base.map {|item| item.fetch('id')}
      current_ids = current.map {|item| item.fetch('id')}
      return unless mine_ids.sort == base_ids.sort && current_ids.sort == base_ids.sort

      if current_ids == base_ids || mine_ids == current_ids
        mine_ids
      elsif mine_ids == base_ids
        current_ids
      end
    end

    def enumeration_proposal(base, mine, current, valid_base)
      return unless valid_base

      base_ids = base.map {|item| item.fetch('id')}
      current_ids = current.map {|item| item.fetch('id')}
      persisted_mine = mine.select {|item| item['id']}
      return unless persisted_mine.map {|item| item.fetch('id')}.sort == base_ids.sort
      return unless current_ids.sort == base_ids.sort

      base_by_id = base.index_by {|item| item.fetch('id')}
      current_by_id = current.index_by {|item| item.fetch('id')}
      mine_by_id = persisted_mine.index_by {|item| item.fetch('id')}
      merged_by_key = {}
      unsafe = false

      base_ids.each do |id|
        base_item = base_by_id.fetch(id)
        current_item = current_by_id.fetch(id)
        mine_item = mine_by_id.fetch(id)
        if mine_item['deleted'] && values_changed?(base_item, current_item)
          unsafe = true
          break
        end

        name = merge_value(base_item['name'], mine_item['name'], current_item['name'])
        active = merge_value(base_item['active'], mine_item['active'], current_item['active'])
        if name.equal?(unsafe_merge) || active.equal?(unsafe_merge)
          unsafe = true
          break
        end

        merged_by_key[id.to_s] = {
          'client_id' => mine_item['client_id'],
          'id' => id,
          'name' => name,
          'active' => active,
          'deleted' => mine_item['deleted']
        }
      end
      return if unsafe

      mine.select {|item| item['id'].nil?}.each do |item|
        merged_by_key[item.fetch('key')] = item.slice('client_id', 'id', 'name', 'active', 'deleted')
      end

      deleted_ids = mine.select {|item| item['deleted'] && item['id']}.map {|item| item.fetch('id')}
      mine_existing_order = mine.reject {|item| item['deleted'] || item['id'].nil?}.map {|item| item.fetch('id')}
      base_after_deletion = base_ids - deleted_ids
      mine_structural = mine.any? {|item| item['id'].nil?} || deleted_ids.any? || mine_existing_order != base_after_deletion
      server_reordered = current_ids != base_ids
      return if mine_structural && server_reordered

      order = mine_structural ? mine.map {|item| item.fetch('key')} : current_ids.map(&:to_s)
      order.filter_map {|key| merged_by_key[key.to_s]}
    end

    def merge_value(base, mine, current)
      mine_changed = mine != base
      current_changed = current != base
      return unsafe_merge if mine_changed && current_changed && mine != current
      return mine if mine_changed

      current
    end

    def unsafe_merge
      @unsafe_merge ||= Object.new.freeze
    end

    def values_changed?(base, current)
      base['name'] != current['name'] || base['active'] != current['active']
    end

    def mine_snapshot(mine)
      mine.map do |item|
        item.slice('id', 'name', 'active', 'position').merge('deleted' => item['deleted'])
      end
    end

    def response(base, mine, current, proposal, valid_base, proposal_snapshot = nil)
      {
        :base_snapshot_valid => valid_base,
        :base_snapshot => base,
        :mine_snapshot => mine,
        :current_snapshot => current,
        :diffs => comparison_diffs(base, mine, current),
        :merge_proposal => proposal,
        :merge_proposal_snapshot => proposal_snapshot
      }
    end

    def comparison_diffs(base, mine, current)
      base_by_key = comparison_index(base)
      mine_by_key = comparison_index(mine)
      current_by_key = comparison_index(current)
      (base_by_key.keys | mine_by_key.keys | current_by_key.keys).filter_map do |key|
        original = base_by_key[key]
        mine_item = mine_by_key[key]
        current_item = current_by_key[key]
        next if mine_item == original && current_item == original

        {
          'key' => key,
          'base' => original,
          'mine' => mine_item,
          'current' => current_item
        }
      end
    end

    def comparison_index(items)
      Array(items).map.with_index.index_by do |(item, index)|
        item['id'] ? item['id'].to_s : "new:#{index}"
      end.transform_values(&:first)
    end

    def safe_hash(value)
      value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value.to_h
    end
  end
end
