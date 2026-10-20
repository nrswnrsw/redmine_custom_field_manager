# frozen_string_literal: true

module RedmineCustomFieldManager
  class CsvImportPlan
    MODES = %w[append update sync].freeze
    MISSING_ACTIONS = %w[delete disable].freeze

    attr_reader :custom_field, :parsed, :mode, :items, :diffs, :unresolved,
                :mapping_targets, :missing_items, :digest, :cross_environment

    def initialize(custom_field:, parsed:, mode:, mappings: {}, missing_default: 'disable',
                   missing_actions: {})
      @custom_field = custom_field
      @parsed = parsed
      @mode = mode.to_s
      @requested_mappings = stringify_hash(mappings)
      @missing_default = missing_default.to_s
      @requested_missing_actions = stringify_hash(missing_actions)
      @items = []
      @diffs = []
      @unresolved = []
      @mapping_targets = {}
      @missing_items = []
      build!
    end

    def resolved?
      unresolved.empty?
    end

    def serializable_hash
      {
        'mode' => mode,
        'cross_environment' => cross_environment,
        'resolved' => resolved?,
        'diffs' => diffs,
        'unresolved' => unresolved,
        'missing_items' => missing_items,
        'digest' => digest
      }
    end

    private

    def build!
      validate!
      @current_records = custom_field.enumerations.reorder(:position, :id).to_a
      @current_by_id = @current_records.index_by {|record| record.id.to_s}
      @cross_environment = parsed.metadata.fetch('source_instance_id') != InstanceIdentity.value
      resolutions = resolve_rows
      validate_unique_targets!(resolutions)
      @items = build_items(resolutions)
      @diffs = build_diffs
      @digest = Snapshot.digest(
        'mode' => mode,
        'source' => parsed.metadata,
        'rows' => parsed.rows.map {|row| row.to_h},
        'items' => items.map {|item| item.slice('client_id', 'id', 'name', 'active', 'deleted')},
        'mappings' => mapping_targets
      )
    end

    def validate!
      raise InvalidChangeError, 'the custom field is not a key/value list' unless custom_field.field_format == 'enumeration'
      raise InvalidChangeError, 'CSV import mode is invalid' unless MODES.include?(mode)
      unless MISSING_ACTIONS.include?(@missing_default)
        raise InvalidChangeError, 'the default missing-item action is invalid'
      end
      if parsed.metadata.fetch('source_field_type') != custom_field.type
        raise InvalidChangeError, 'CSV custom field type does not match the target field'
      end
      if mode != 'append' &&
         parsed.metadata.fetch('source_instance_id') == InstanceIdentity.value &&
         parsed.metadata.fetch('source_field_id').to_s != custom_field.id.to_s
        raise InvalidChangeError, 'CSV source field does not match the target field'
      end
    end

    def resolve_rows
      return parsed.rows.map.with_index {|row, index| new_resolution(row, index)} if mode == 'append'

      parsed.rows.map.with_index do |row, index|
        if cross_environment
          resolve_cross_environment_row(row, index)
        else
          resolve_same_environment_row(row, index)
        end
      end
    end

    def resolve_same_environment_row(row, index)
      return new_resolution(row, index) if row.source_id.blank?

      target = @current_by_id[row.source_id.to_s]
      raise InvalidChangeError, "CSV row #{row.row_number} refers to an unknown enumeration ID" unless target

      existing_resolution(row, index, target, false)
    end

    def resolve_cross_environment_row(row, index)
      return new_resolution(row, index) if row.source_id.blank?

      explicit = @requested_mappings.key?(row.source_id.to_s)
      choice = @requested_mappings[row.source_id.to_s]
      if explicit
        return new_resolution(row, index, true) if choice.to_s == 'new'

        target = @current_by_id[choice.to_s]
        unless target
          raise InvalidChangeError, "CSV row #{row.row_number} mapping target does not exist"
        end

        return existing_resolution(row, index, target, true)
      end

      stored = stored_mapping(row.source_id)
      target = stored && @current_by_id[stored.target_enumeration_id.to_s]
      return existing_resolution(row, index, target, true) if target

      candidates = @current_records.select {|record| record.name == row.name}
      @unresolved << {
        'source_id' => row.source_id,
        'name' => row.name,
        'row_number' => row.row_number,
        'candidates' => candidates.map {|record| target_hash(record)}
      }
      unresolved_resolution(row, index)
    end

    def stored_mapping(source_id)
      ImportMapping.find_by(
        :source_instance_id => parsed.metadata.fetch('source_instance_id'),
        :source_field_id => parsed.metadata.fetch('source_field_id'),
        :source_enumeration_id => source_id.to_s,
        :target_custom_field_id => custom_field.id
      )
    end

    def new_resolution(row, index, confirmed = false)
      client_id = "csv-#{index + 1}"
      @mapping_targets[row.source_id.to_s] = client_id if cross_environment && row.source_id.present? && confirmed
      {'row' => row, 'client_id' => client_id, 'record' => nil, 'unresolved' => false}
    end

    def existing_resolution(row, index, target, remember_mapping)
      @mapping_targets[row.source_id.to_s] = target.id if cross_environment && remember_mapping
      {
        'row' => row,
        'client_id' => target.id.to_s,
        'record' => target,
        'unresolved' => false,
        'index' => index
      }
    end

    def unresolved_resolution(row, index)
      {
        'row' => row,
        'client_id' => "unresolved-#{index + 1}",
        'record' => nil,
        'unresolved' => true
      }
    end

    def validate_unique_targets!(resolutions)
      ids = resolutions.filter_map {|resolution| resolution['record']&.id}
      return if ids.length == ids.uniq.length

      raise InvalidChangeError, 'multiple CSV rows are mapped to the same enumeration'
    end

    def build_items(resolutions)
      unresolved_resolutions = resolutions.select {|resolution| resolution['unresolved']}
      return current_items if unresolved_resolutions.any?

      imported = resolutions.map do |resolution|
        row = resolution.fetch('row')
        record = resolution['record']
        {
          'client_id' => resolution.fetch('client_id'),
          'id' => record&.id,
          'name' => row.name,
          'active' => row.active,
          'deleted' => false,
          'source_id' => row.source_id
        }
      end

      case mode
      when 'append'
        current_items + imported
      when 'update'
        arrange_update_items(imported)
      when 'sync'
        build_sync_items(imported)
      end
    end

    def current_items
      @current_records.map do |record|
        {
          'client_id' => record.id.to_s,
          'id' => record.id,
          'name' => record.name,
          'active' => record.active?,
          'deleted' => false,
          'source_id' => nil
        }
      end
    end

    def arrange_update_items(imported)
      matched_ids = imported.filter_map {|item| item['id']}
      untouched = current_items.reject {|item| matched_ids.include?(item['id'])}
      output = Array.new(imported.length + untouched.length)
      parsed.rows.each_with_index do |row, index|
        output[row.position - 1] = imported[index]
      end
      untouched.each do |item|
        empty_index = output.index(nil)
        output[empty_index] = item
      end
      output
    end

    def build_sync_items(imported)
      matched_ids = imported.filter_map {|item| item['id']}
      missing = @current_records.reject {|record| matched_ids.include?(record.id)}
      missing_items = missing.map do |record|
        requested = @requested_missing_actions.fetch(record.id.to_s, @missing_default)
        unless MISSING_ACTIONS.include?(requested)
          raise InvalidChangeError, "missing-item action for ##{record.id} is invalid"
        end

        used = EnumerationUsage.new(record).in_use?
        action = used ? 'disable' : requested
        @missing_items << target_hash(record).merge('used' => used, 'action' => action)
        {
          'client_id' => record.id.to_s,
          'id' => record.id,
          'name' => record.name,
          'active' => action == 'disable' ? false : record.active?,
          'deleted' => action == 'delete',
          'source_id' => nil
        }
      end
      imported + missing_items
    end

    def build_diffs
      before_by_id = @current_records.index_by(&:id)
      output = []
      items.each_with_index do |item, index|
        if item['id'].nil?
          output << diff('add', item, nil, index + 1)
          next
        end
        before = before_by_id.fetch(item['id'])
        if item['deleted']
          output << diff('delete', item, before, nil)
          next
        end
        output << diff('rename', item, before, index + 1) if before.name != item['name']
        if before.active? != item['active']
          output << diff(item['active'] ? 'activate' : 'deactivate', item, before, index + 1)
        end
        output << diff('move', item, before, index + 1) if before.position != index + 1
      end
      output
    end

    def diff(action, item, before, position)
      {
        'action' => action,
        'id' => item['id'],
        'source_id' => item['source_id'],
        'before_name' => before&.name,
        'name' => item['name'],
        'before_position' => before&.position,
        'position' => position
      }
    end

    def target_hash(record)
      {'id' => record.id, 'name' => record.name, 'active' => record.active?, 'position' => record.position}
    end

    def stringify_hash(value)
      return {} if value.blank?

      value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
      value.to_h.transform_keys(&:to_s).transform_values(&:to_s)
    end
  end
end
