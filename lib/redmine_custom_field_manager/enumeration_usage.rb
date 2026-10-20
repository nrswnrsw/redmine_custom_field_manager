# frozen_string_literal: true

module RedmineCustomFieldManager
  class EnumerationUsage
    def self.referenced_ids(custom_field)
      custom_field.custom_values.distinct.pluck(:value).filter_map do |value|
        Integer(value, 10)
      rescue ArgumentError, TypeError
        nil
      end.to_set
    end

    def self.default_ids(custom_field)
      Array.wrap(custom_field.default_value).filter_map do |value|
        Integer(value, 10)
      rescue ArgumentError, TypeError
        nil
      end.to_set
    end

    def self.used_ids(custom_field)
      referenced_ids(custom_field) | default_ids(custom_field)
    end

    def initialize(enumeration)
      @enumeration = enumeration
      @custom_field = enumeration.custom_field
    end

    def in_use?
      reasons.any?
    end

    def reasons
      result = []
      result << 'custom_values' if @enumeration.custom_values.exists?
      result << 'default_value' if used_as_default?
      result
    end

    private

    def used_as_default?
      values = Array.wrap(@custom_field.default_value).map(&:to_s)
      values.include?(@enumeration.id.to_s)
    end
  end
end
