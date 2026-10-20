# frozen_string_literal: true

require 'securerandom'

module RedmineCustomFieldManager
  module InstanceIdentity
    module_function

    def value
      Metadata.create_or_find_by!(:key => 'instance_id') do |metadata|
        metadata.value = SecureRandom.uuid
      end.value
    end
  end
end
