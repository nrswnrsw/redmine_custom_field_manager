# frozen_string_literal: true

require 'digest'
require 'json'

module RedmineCustomFieldManager
  module Snapshot
    module_function

    def custom_fields(field_type:, records: nil)
      records ||= CustomField.where(:type => field_type).order(:position, :id).to_a
      records.map do |record|
        {
          'id' => record.id,
          'type' => record.type,
          'name' => record.name,
          'position' => record.position
        }
      end
    end

    def custom_fields_digest(field_type:, records: nil)
      digest(custom_fields(:field_type => field_type, :records => records))
    end

    def enumerations(custom_field, records = nil)
      records ||= custom_field.enumerations.reorder(:position, :id).to_a
      records.map do |record|
        {
          'id' => record.id,
          'name' => record.name,
          'active' => record.active?,
          'position' => record.position
        }
      end
    end

    def enumerations_digest(custom_field, records = nil)
      digest(enumerations(custom_field, records))
    end

    def digest(value)
      Digest::SHA256.hexdigest(JSON.generate(value))
    end
  end
end
