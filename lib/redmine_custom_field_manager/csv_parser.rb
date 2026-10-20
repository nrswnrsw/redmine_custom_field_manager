# frozen_string_literal: true

require 'csv'

module RedmineCustomFieldManager
  class CsvParser
    Parsed = Struct.new(:metadata, :rows, keyword_init: true)
    Row = Struct.new(:source_id, :name, :active, :position, :row_number, keyword_init: true)

    MAX_BYTES = 50 * 1024 * 1024

    def initialize(data)
      @data = data.to_s
    end

    def parse
      raise InvalidChangeError, 'CSV file is empty' if @data.empty?
      raise InvalidChangeError, 'CSV file is too large' if @data.bytesize > MAX_BYTES

      data = @data.dup.force_encoding(Encoding::UTF_8)
      raise InvalidChangeError, 'CSV is not valid UTF-8' unless data.valid_encoding?

      table = CSV.parse(remove_bom(data), :headers => true, :encoding => 'UTF-8')
      validate_headers!(table.headers)
      metadata_rows = table.select {|row| row['record_type'] == 'metadata'}
      enumeration_rows = table.select {|row| row['record_type'] == 'enumeration'}
      if metadata_rows.length != 1
        raise InvalidChangeError, 'CSV must contain exactly one metadata row'
      end

      valid_types = %w[metadata enumeration]
      unless table.all? {|row| valid_types.include?(row['record_type'])}
        raise InvalidChangeError, 'CSV contains an unknown record_type'
      end

      metadata = parse_metadata(metadata_rows.first)
      rows = enumeration_rows.each_with_index.map do |row, index|
        parse_enumeration(row, index + 3, metadata)
      end
      validate_rows!(rows)

      Parsed.new(:metadata => metadata, :rows => rows.sort_by(&:position))
    rescue CSV::MalformedCSVError, EncodingError => e
      raise InvalidChangeError, "invalid CSV: #{e.message}"
    end

    private

    def remove_bom(value)
      value.delete_prefix("\uFEFF")
    end

    def validate_headers!(headers)
      unless headers == CsvExporter::HEADERS
        raise InvalidChangeError, 'CSV headers do not match the supported schema'
      end
    end

    def parse_metadata(row)
      ensure_schema!(row)
      {
        'source_instance_id' => required_value(row, 'source_instance_id'),
        'source_field_id' => required_value(row, 'source_field_id'),
        'source_field_type' => required_value(row, 'source_field_type'),
        'source_field_name' => decode_cell(row['source_field_name'], row['source_field_name_escaped'])
      }
    end

    def parse_enumeration(row, row_number, metadata)
      ensure_schema!(row)
      %w[source_instance_id source_field_id source_field_type].each do |key|
        if row[key].to_s != metadata.fetch(key).to_s
          raise InvalidChangeError, "CSV row #{row_number} has inconsistent source metadata"
        end
      end
      field_name = decode_cell(row['source_field_name'], row['source_field_name_escaped'])
      if field_name != metadata.fetch('source_field_name')
        raise InvalidChangeError, "CSV row #{row_number} has inconsistent source metadata"
      end

      name = decode_cell(row['name'], row['name_escaped']).strip
      raise InvalidChangeError, "CSV row #{row_number} has a blank name" if name.blank?
      if name.length > 60
        raise InvalidChangeError, "CSV row #{row_number} name exceeds 60 characters"
      end

      Row.new(
        :source_id => row['id'].presence,
        :name => name,
        :active => parse_boolean(row['active'], row_number),
        :position => parse_position(row['position'], row_number),
        :row_number => row_number
      )
    end

    def validate_rows!(rows)
      source_ids = rows.filter_map(&:source_id)
      if source_ids.length != source_ids.uniq.length
        raise InvalidChangeError, 'CSV contains duplicate enumeration IDs'
      end

      positions = rows.map(&:position)
      if positions.length != positions.uniq.length
        raise InvalidChangeError, 'CSV contains duplicate positions'
      end
      unless positions.sort == (1..positions.length).to_a
        raise InvalidChangeError, 'CSV positions must be consecutive and start at 1'
      end
    end

    def ensure_schema!(row)
      return if row['schema_version'] == CsvExporter::SCHEMA_VERSION

      raise InvalidChangeError, 'CSV schema version is not supported'
    end

    def required_value(row, key)
      value = row[key].to_s
      raise InvalidChangeError, "CSV metadata #{key} is missing" if value.blank?

      value
    end

    def decode_cell(value, escaped)
      value = value.to_s
      return value unless parse_boolean(escaped, nil)
      unless value.start_with?("'")
        raise InvalidChangeError, 'CSV escaped cell is malformed'
      end

      value.delete_prefix("'")
    end

    def parse_boolean(value, row_number)
      case value.to_s.downcase
      when '1', 'true'
        true
      when '0', 'false'
        false
      else
        location = row_number ? "row #{row_number}" : 'metadata'
        raise InvalidChangeError, "CSV #{location} contains an invalid boolean"
      end
    end

    def parse_position(value, row_number)
      position = Integer(value.to_s, 10)
      raise ArgumentError unless position.positive?

      position
    rescue ArgumentError, TypeError
      raise InvalidChangeError, "CSV row #{row_number} contains an invalid position"
    end
  end
end
