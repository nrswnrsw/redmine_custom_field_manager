# frozen_string_literal: true

require 'csv'

module RedmineCustomFieldManager
  class CsvExporter
    SCHEMA_VERSION = '1'
    HEADERS = %w[
      record_type
      schema_version
      source_instance_id
      source_field_id
      source_field_type
      source_field_name
      source_field_name_escaped
      id
      name
      name_escaped
      active
      position
    ].freeze

    def initialize(custom_field, template: false)
      @custom_field = custom_field
      @template = template
    end

    def generate
      ensure_enumeration_field!
      instance_id = InstanceIdentity.value
      field_name, field_name_escaped = safe_spreadsheet_cell(@custom_field.name)

      csv = CSV.generate do |output|
        output << HEADERS
        output << [
          'metadata', SCHEMA_VERSION, instance_id, @custom_field.id,
          @custom_field.type, field_name, boolean_cell(field_name_escaped),
          nil, nil, '0', nil, nil
        ]
        export_records.each do |enumeration|
          name, name_escaped = safe_spreadsheet_cell(enumeration.name)
          output << [
            'enumeration', SCHEMA_VERSION, instance_id, @custom_field.id,
            @custom_field.type, field_name, boolean_cell(field_name_escaped),
            enumeration.id, name, boolean_cell(name_escaped),
            boolean_cell(enumeration.active?), enumeration.position
          ]
        end
      end

      "\uFEFF#{csv}"
    end

    private

    def export_records
      return [] if @template

      @custom_field.enumerations.reorder(:position, :id)
    end

    def ensure_enumeration_field!
      return if @custom_field.field_format == 'enumeration'

      raise InvalidChangeError, 'the custom field is not a key/value list'
    end

    def safe_spreadsheet_cell(value)
      value = value.to_s
      dangerous = value.match?(/\A(?:\s*[=+\-@]|[\t\r\n])/)
      [dangerous ? "'#{value}" : value, dangerous]
    end

    def boolean_cell(value)
      value ? '1' : '0'
    end
  end
end
