# frozen_string_literal: true

module RedmineCustomFieldManager
  class CsvImporter
    Result = Struct.new(:update_result, :plan, keyword_init: true)

    def initialize(custom_field:, parsed:, mode:, mappings:, missing_default:,
                   missing_actions:, base_digest:, plan_digest:, user:)
      @custom_field = custom_field
      @parsed = parsed
      @mode = mode
      @mappings = mappings
      @missing_default = missing_default
      @missing_actions = missing_actions
      @base_digest = base_digest.to_s
      @plan_digest = plan_digest.to_s
      @user = user
    end

    def call
      CustomFieldEnumeration.transaction do
        plan = CsvImportPlan.new(
          :custom_field => @custom_field,
          :parsed => @parsed,
          :mode => @mode,
          :mappings => @mappings,
          :missing_default => @missing_default,
          :missing_actions => @missing_actions
        )
        raise InvalidChangeError, 'CSV mappings must be confirmed before import' unless plan.resolved?
        unless secure_equal?(plan.digest, @plan_digest)
          raise InvalidChangeError, 'CSV import preview is no longer current'
        end

        result = EnumerationUpdater.new(
          :custom_field => @custom_field,
          :items => plan.items,
          :base_digest => @base_digest,
          :user => @user,
          :resolution => 'csv_import'
        ).call
        persist_mappings!(plan, result)
        Result.new(:update_result => result, :plan => plan)
      end
    end

    private

    def secure_equal?(left, right)
      return false unless left.bytesize == right.bytesize

      ActiveSupport::SecurityUtils.secure_compare(left, right)
    end

    def persist_mappings!(plan, update_result)
      return unless plan.cross_environment

      plan.mapping_targets.each do |source_id, target|
        target_id = update_result.created_ids.fetch(target, target)
        mapping = ImportMapping.find_or_initialize_by(
          :source_instance_id => @parsed.metadata.fetch('source_instance_id'),
          :source_field_id => @parsed.metadata.fetch('source_field_id'),
          :source_enumeration_id => source_id,
          :target_custom_field_id => @custom_field.id
        )
        mapping.target_enumeration_id = target_id
        mapping.save!
      end
    end
  end
end
