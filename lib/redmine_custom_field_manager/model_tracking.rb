# frozen_string_literal: true

require_relative 'model_tracking/custom_field'
require_relative 'model_tracking/custom_field_enumeration'
require_relative 'model_tracking/custom_value'

module RedmineCustomFieldManager
  module ModelTracking
    module_function

    def install!
      include_once(::CustomField, CustomField)
      include_once(::CustomFieldEnumeration, CustomFieldEnumeration)
      include_once(::CustomValue, CustomValue)
    end

    def include_once(model, concern)
      model.include(concern) unless model < concern
    end
  end
end
