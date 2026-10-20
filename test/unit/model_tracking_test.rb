# frozen_string_literal: true

require_relative '../test_helper'

class RedmineCustomFieldManagerModelTrackingTest < ActiveSupport::TestCase
  def test_standard_custom_field_save_bumps_the_type_revision
    custom_field = IssueCustomField.create!(:name => 'RCFM tracked field', :field_format => 'string')
    revision = revision_for('custom_fields:IssueCustomField')
    previous_sequence = revision.sequence

    custom_field.update!(:name => 'RCFM tracked field updated')

    assert_equal previous_sequence + 1, revision.reload.sequence
  end

  def test_standard_custom_field_destroy_records_a_non_restorable_audit_history
    User.current = User.find(1)
    field = GroupCustomField.create!(:name => 'RCFM deleted field', :field_format => 'enumeration')
    value = field.enumerations.create!(:name => 'Deleted choice')
    group = Group.generate!
    CustomValue.create!(
      :customized => group,
      :custom_field => field,
      :value => value.id.to_s
    )
    custom_values_count = field.custom_values.count
    enumeration_count = field.enumerations.count

    assert_difference 'RedmineCustomFieldManager::History.count', 1 do
      field.destroy!
    end

    history = RedmineCustomFieldManager::History.last
    changes = history.parsed_changes
    deleted_change = changes.fetch('diff').find {|change| change.fetch('id').to_i == field.id}
    assert_equal 'delete', history.operation
    assert_equal 'custom_fields', history.target_type
    assert_equal field.id, history.target_id
    assert_equal field.name, changes.fetch('field_name')
    assert_equal custom_values_count, changes.fetch('custom_values_count')
    assert_equal enumeration_count, changes.fetch('enumeration_count')
    assert_equal false, changes.fetch('restorable')
    assert_equal field.name, deleted_change.fetch('before').fetch('name')
    assert_nil deleted_change.fetch('after')
  end

  def test_custom_field_destroy_rolls_back_when_audit_history_cannot_be_recorded
    field = IssueCustomField.create!(:name => 'RCFM rollback delete', :field_format => 'string')
    RedmineCustomFieldManager::HistoryRecorder.stubs(:record!).raises('simulated history failure')

    assert_raises RuntimeError do
      field.destroy!
    end
    assert CustomField.exists?(field.id)
  end

  def test_enumeration_revisions_are_independent_per_custom_field
    first_field = IssueCustomField.create!(:name => 'RCFM enum one', :field_format => 'enumeration')
    second_field = IssueCustomField.create!(:name => 'RCFM enum two', :field_format => 'enumeration')
    first_field.enumerations.create!(:name => 'First')
    first_revision = revision_for("custom_field_enumerations:#{first_field.id}")
    previous_sequence = first_revision.sequence

    second_field.enumerations.create!(:name => 'Second')

    assert_equal previous_sequence, first_revision.reload.sequence
    assert revision_for("custom_field_enumerations:#{second_field.id}").sequence.positive?
  end

  def test_custom_value_save_uses_the_revision_as_a_mutex_without_bumping_it
    field = GroupCustomField.create!(:name => 'RCFM value tracking', :field_format => 'enumeration')
    value = field.enumerations.create!(:name => 'Tracked')
    revision = revision_for("custom_field_enumerations:#{field.id}")
    previous_sequence = revision.sequence
    group = Group.generate!

    group.custom_field_values = {field.id.to_s => value.id.to_s}
    group.save!

    assert_equal previous_sequence, revision.reload.sequence
  end

  def test_unchanged_custom_value_save_does_not_lock_the_revision
    field = GroupCustomField.create!(:name => 'RCFM unchanged value', :field_format => 'enumeration')
    value = field.enumerations.create!(:name => 'Tracked')
    group = Group.generate!
    custom_value = CustomValue.create!(
      :customized => group,
      :custom_field => field,
      :value => value.id.to_s
    )
    RedmineCustomFieldManager::Revision.expects(:lock_for!).never
    custom_value.save!
  end

  def test_changing_a_custom_values_field_revalidates_against_the_destination_field
    source_field = GroupCustomField.create!(:name => 'RCFM source value', :field_format => 'enumeration')
    source_value = source_field.enumerations.create!(:name => 'Source')
    destination_field = GroupCustomField.create!(
      :name => 'RCFM destination value',
      :field_format => 'enumeration'
    )
    destination_field.enumerations.create!(:name => 'Destination')
    group = Group.generate!
    custom_value = CustomValue.create!(
      :customized => group,
      :custom_field => source_field,
      :value => source_value.id.to_s
    )

    assert_raises ActiveRecord::RecordInvalid do
      custom_value.update!(:custom_field_id => destination_field.id)
    end
    assert_equal source_field.id, custom_value.reload.custom_field_id
    assert_equal source_value.id.to_s, custom_value.value
  end

  private

  def revision_for(scope_key)
    RedmineCustomFieldManager::Revision.find_by!(:scope_key => scope_key)
  end
end
