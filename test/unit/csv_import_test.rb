# frozen_string_literal: true

require_relative '../test_helper'
require 'csv'

class RedmineCustomFieldManagerCsvImportTest < ActiveSupport::TestCase
  fixtures :users

  def setup
    RedmineCustomFieldManager::ImportMapping.delete_all
    RedmineCustomFieldManager::Metadata.delete_all
    @field = GroupCustomField.create!(
      :name => 'RCFM CSV list',
      :field_format => 'enumeration',
      :is_required => false
    )
    @first = @field.enumerations.create!(:name => 'First')
    @second = @field.enumerations.create!(:name => 'Second')
  end

  def test_export_is_safe_for_spreadsheets_and_round_trips_exact_names
    @field.update!(:name => '=Dangerous field')
    @first.update!(:name => "+Dangerous\nvalue")

    data = RedmineCustomFieldManager::CsvExporter.new(@field).generate
    table = CSV.parse(data.delete_prefix("\uFEFF"), :headers => true)

    assert_equal "'=Dangerous field", table.first['source_field_name']
    assert_equal "'+Dangerous\nvalue", table[1]['name']
    parsed = RedmineCustomFieldManager::CsvParser.new(data).parse
    assert_equal '=Dangerous field', parsed.metadata.fetch('source_field_name')
    assert_equal "+Dangerous\nvalue", parsed.rows.first.name
  end

  def test_export_contains_metadata_when_the_list_is_empty
    @field.enumerations.delete_all

    parsed = RedmineCustomFieldManager::CsvParser.new(
      RedmineCustomFieldManager::CsvExporter.new(@field).generate
    ).parse

    assert_empty parsed.rows
    assert_equal @field.id.to_s, parsed.metadata.fetch('source_field_id')
  end

  def test_same_environment_update_preserves_ids_updates_and_adds
    data = csv_data(
      :source_instance_id => RedmineCustomFieldManager::InstanceIdentity.value,
      :source_field_id => @field.id,
      :rows => [
        {:id => @second.id, :name => 'Second renamed', :active => false, :position => 1},
        {:id => '', :name => 'Added', :active => true, :position => 2},
        {:id => @first.id, :name => 'First', :active => true, :position => 3}
      ]
    )
    parsed = RedmineCustomFieldManager::CsvParser.new(data).parse
    plan = plan_for(parsed, :mode => 'update')

    result = import(plan, parsed)

    records = @field.reload.enumerations.reorder(:position, :id).to_a
    assert_equal [@second.id, result.update_result.created_ids.fetch('csv-2'), @first.id], records.map(&:id)
    assert_equal ['Second renamed', 'Added', 'First'], records.map(&:name)
    assert_not records.first.active?
  end

  def test_same_environment_unknown_id_is_rejected
    parsed = RedmineCustomFieldManager::CsvParser.new(
      csv_data(
        :source_instance_id => RedmineCustomFieldManager::InstanceIdentity.value,
        :source_field_id => @field.id,
        :rows => [{:id => 999_999, :name => 'Unknown', :active => true, :position => 1}]
      )
    ).parse

    assert_raises RedmineCustomFieldManager::InvalidChangeError do
      plan_for(parsed, :mode => 'update')
    end
  end

  def test_cross_environment_requires_confirmation_and_reuses_saved_mapping
    parsed = RedmineCustomFieldManager::CsvParser.new(
      csv_data(
        :source_instance_id => 'another-instance',
        :source_field_id => 42,
        :rows => [{:id => 501, :name => 'First', :active => false, :position => 1}]
      )
    ).parse
    unresolved = plan_for(parsed, :mode => 'update')

    assert_not unresolved.resolved?
    assert_equal [@first.id], unresolved.unresolved.first.fetch('candidates').map {|item| item.fetch('id')}

    confirmed = plan_for(parsed, :mode => 'update', :mappings => {'501' => @first.id})
    import(confirmed, parsed, :mappings => {'501' => @first.id})

    assert_not @first.reload.active?
    mapping = RedmineCustomFieldManager::ImportMapping.find_by!(:source_enumeration_id => '501')
    assert_equal @first.id, mapping.target_enumeration_id
    assert plan_for(parsed, :mode => 'update').resolved?
  end

  def test_cross_environment_new_confirmation_never_reuses_the_source_id
    parsed = RedmineCustomFieldManager::CsvParser.new(
      csv_data(
        :source_instance_id => 'another-instance',
        :source_field_id => 42,
        :rows => [{:id => 501, :name => 'Remote', :active => true, :position => 1}]
      )
    ).parse
    plan = plan_for(parsed, :mode => 'update', :mappings => {'501' => 'new'})

    result = import(plan, parsed, :mappings => {'501' => 'new'})
    created_id = result.update_result.created_ids.fetch('csv-1')

    assert_not_equal 501, created_id
    assert_equal created_id,
                 RedmineCustomFieldManager::ImportMapping.find_by!(:source_enumeration_id => '501').target_enumeration_id
  end

  def test_cross_environment_duplicate_names_are_never_mapped_automatically
    duplicate = @field.enumerations.create!(:name => 'First')
    parsed = RedmineCustomFieldManager::CsvParser.new(
      csv_data(
        :source_instance_id => 'another-instance',
        :source_field_id => 42,
        :rows => [{:id => 501, :name => 'First', :active => true, :position => 1}]
      )
    ).parse

    plan = plan_for(parsed, :mode => 'update')

    assert_not plan.resolved?
    assert_equal [@first.id, duplicate.id].sort,
                 plan.unresolved.first.fetch('candidates').pluck('id').sort
  end

  def test_append_mode_creates_every_csv_row_without_reusing_ids
    parsed = RedmineCustomFieldManager::CsvParser.new(
      csv_data(
        :source_instance_id => RedmineCustomFieldManager::InstanceIdentity.value,
        :source_field_id => @field.id,
        :rows => [{:id => @first.id, :name => 'Copy', :active => true, :position => 1}]
      )
    ).parse
    plan = plan_for(parsed, :mode => 'append')

    result = import(plan, parsed, :mode => 'append')

    created_id = result.update_result.created_ids.fetch('csv-1')
    assert_not_equal @first.id, created_id
    assert_equal [@first.id, @second.id, created_id],
                 @field.reload.enumerations.reorder(:position, :id).pluck(:id)
  end

  def test_sync_disables_used_missing_value_and_deletes_unused_value
    third = @field.enumerations.create!(:name => 'Third')
    group = Group.generate!
    group.custom_field_values = {@field.id.to_s => @first.id.to_s}
    group.save!
    parsed = RedmineCustomFieldManager::CsvParser.new(
      csv_data(
        :source_instance_id => RedmineCustomFieldManager::InstanceIdentity.value,
        :source_field_id => @field.id,
        :rows => [{:id => @second.id, :name => 'Second', :active => true, :position => 1}]
      )
    ).parse
    plan = plan_for(
      parsed,
      :mode => 'sync',
      :missing_default => 'delete',
      :missing_actions => {@first.id => 'delete', third.id => 'delete'}
    )

    assert_equal 'disable', plan.missing_items.find {|item| item['id'] == @first.id}.fetch('action')
    import(
      plan,
      parsed,
      :mode => 'sync',
      :missing_default => 'delete',
      :missing_actions => {@first.id => 'delete', third.id => 'delete'}
    )

    assert CustomFieldEnumeration.exists?(@first.id)
    assert_not @first.reload.active?
    assert_not CustomFieldEnumeration.exists?(third.id)
  end

  def test_sync_rolls_back_if_a_value_becomes_used_after_preview
    parsed = RedmineCustomFieldManager::CsvParser.new(
      csv_data(
        :source_instance_id => RedmineCustomFieldManager::InstanceIdentity.value,
        :source_field_id => @field.id,
        :rows => [{:id => @second.id, :name => 'Changed', :active => true, :position => 1}]
      )
    ).parse
    plan = plan_for(parsed, :mode => 'sync', :missing_default => 'delete')
    group = Group.generate!
    group.custom_field_values = {@field.id.to_s => @first.id.to_s}
    group.save!

    assert_raises RedmineCustomFieldManager::InvalidChangeError do
      import(plan, parsed, :mode => 'sync', :missing_default => 'delete')
    end
    assert_equal 'Second', @second.reload.name
    assert CustomFieldEnumeration.exists?(@first.id)
  end

  def test_parser_rejects_nonconsecutive_positions
    data = csv_data(
      :source_instance_id => 'instance',
      :source_field_id => 1,
      :rows => [{:id => 1, :name => 'One', :active => true, :position => 2}]
    )

    assert_raises RedmineCustomFieldManager::InvalidChangeError do
      RedmineCustomFieldManager::CsvParser.new(data).parse
    end
  end

  private

  def csv_data(source_instance_id:, source_field_id:, rows:)
    CSV.generate do |csv|
      csv << RedmineCustomFieldManager::CsvExporter::HEADERS
      csv << ['metadata', '1', source_instance_id, source_field_id, @field.type, @field.name, '0', nil, nil, '0', nil, nil]
      rows.each do |row|
        csv << [
          'enumeration', '1', source_instance_id, source_field_id, @field.type, @field.name, '0',
          row.fetch(:id), row.fetch(:name), '0', row.fetch(:active) ? '1' : '0', row.fetch(:position)
        ]
      end
    end
  end

  def plan_for(parsed, options = {})
    RedmineCustomFieldManager::CsvImportPlan.new(
      :custom_field => @field,
      :parsed => parsed,
      :mode => options.fetch(:mode, 'update'),
      :mappings => options.fetch(:mappings, {}),
      :missing_default => options.fetch(:missing_default, 'disable'),
      :missing_actions => options.fetch(:missing_actions, {})
    )
  end

  def import(plan, parsed, options = {})
    RedmineCustomFieldManager::CsvImporter.new(
      :custom_field => @field,
      :parsed => parsed,
      :mode => options.fetch(:mode, 'update'),
      :mappings => options.fetch(:mappings, {}),
      :missing_default => options.fetch(:missing_default, 'disable'),
      :missing_actions => options.fetch(:missing_actions, {}),
      :base_digest => RedmineCustomFieldManager::Snapshot.enumerations_digest(@field),
      :plan_digest => plan.digest,
      :user => User.find(1)
    ).call
  end
end
