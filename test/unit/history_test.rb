# frozen_string_literal: true

require_relative '../test_helper'

class RedmineCustomFieldManagerHistoryTest < ActiveSupport::TestCase
  fixtures :users

  def setup
    RedmineCustomFieldManager::History.delete_all
    RedmineCustomFieldManager::Revision.where(
      :scope_key => 'history:custom_field_enumerations:99'
    ).delete_all
    Setting.plugin_redmine_custom_field_manager = {
      'retention_days' => '',
      'max_generations' => ''
    }
  end

  def teardown
    Setting.clear_cache
  end

  def test_periodic_snapshots_and_diffs_reconstruct_every_generation
    before = [{'id' => 1, 'name' => 'Value 0', 'active' => true, 'position' => 1}]
    21.times do |index|
      after = [{'id' => 1, 'name' => "Value #{index + 1}", 'active' => true, 'position' => 1}]
      record(before, after)
      before = after
    end

    histories = RedmineCustomFieldManager::History.order(:id).to_a
    assert histories.first.has_snapshot?
    assert histories[19].has_snapshot?
    assert_not histories.last.has_snapshot?
    assert_equal 'Value 21', histories.last.reconstructed_snapshot.first.fetch('name')
    assert_equal 21, histories.sum {|history| history.parsed_changes.fetch('diff').length}
  end

  def test_history_after_deleting_entire_scope_starts_a_new_snapshot_chain
    before = [{'id' => 1, 'name' => 'Value 0', 'active' => true, 'position' => 1}]
    first_after = [before.first.merge('name' => 'Value 1')]
    first = record(before, first_after)
    RedmineCustomFieldManager::HistoryMaintenance.delete_ids!([first.id])

    second_after = [first_after.first.merge('name' => 'Value 2')]
    second = record(first_after, second_after)

    revision = RedmineCustomFieldManager::Revision.find_by!(
      :scope_key => 'history:custom_field_enumerations:99'
    )
    assert_equal 2, revision.sequence
    assert second.has_snapshot?
    assert_equal second_after, second.reconstructed_snapshot
  end

  def test_manual_deletion_materializes_remaining_histories
    before = [{'id' => 1, 'name' => 'Value 0', 'active' => true, 'position' => 1}]
    3.times do |index|
      after = [{'id' => 1, 'name' => "Value #{index + 1}", 'active' => true, 'position' => 1}]
      record(before, after)
      before = after
    end
    histories = RedmineCustomFieldManager::History.order(:id).to_a

    RedmineCustomFieldManager::HistoryMaintenance.delete_ids!([histories.first.id, histories.second.id])

    survivor = RedmineCustomFieldManager::History.find(histories.last.id)
    assert survivor.has_snapshot?
    assert_equal 'Value 3', survivor.reconstructed_snapshot.first.fetch('name')
  end

  def test_manual_deletion_materializes_only_diff_chain_boundaries
    before = [{'id' => 1, 'name' => 'Value 0', 'active' => true, 'position' => 1}]
    6.times do |index|
      after = [{'id' => 1, 'name' => "Value #{index + 1}", 'active' => true, 'position' => 1}]
      record(before, after)
      before = after
    end
    histories = RedmineCustomFieldManager::History.order(:id).to_a

    RedmineCustomFieldManager::HistoryMaintenance.delete_ids!([histories[1].id, histories[3].id])

    survivors = RedmineCustomFieldManager::History.order(:id).to_a
    assert_equal [true, true, true, false], survivors.map(&:has_snapshot?)
    assert_equal ['Value 1', 'Value 3', 'Value 5', 'Value 6'],
                 survivors.map {|history| history.reconstructed_snapshot.first.fetch('name')}
  end

  def test_max_generation_retention_keeps_restorable_latest_histories
    Setting.plugin_redmine_custom_field_manager = {
      'retention_days' => '',
      'max_generations' => '2'
    }
    before = [{'id' => 1, 'name' => 'Value 0', 'active' => true, 'position' => 1}]
    3.times do |index|
      after = [{'id' => 1, 'name' => "Value #{index + 1}", 'active' => true, 'position' => 1}]
      record(before, after)
      before = after
    end

    histories = RedmineCustomFieldManager::History.order(:id).to_a
    assert_equal 2, histories.length
    assert_equal [true, false], histories.map(&:has_snapshot?)
    assert_equal ['Value 2', 'Value 3'], histories.map {|history| history.reconstructed_snapshot.first.fetch('name')}
  end

  def test_retention_after_deleting_entire_scope_keeps_remaining_histories_reconstructable
    before = [{'id' => 1, 'name' => 'Value 0', 'active' => true, 'position' => 1}]
    first_after = [before.first.merge('name' => 'Value 1')]
    first = record(before, first_after)
    RedmineCustomFieldManager::HistoryMaintenance.delete_ids!([first.id])
    Setting.plugin_redmine_custom_field_manager = {
      'retention_days' => '',
      'max_generations' => '2'
    }

    before = first_after
    3.times do |index|
      after = [before.first.merge('name' => "Value #{index + 2}")]
      record(before, after)
      before = after
    end

    histories = RedmineCustomFieldManager::History.order(:id).to_a
    assert_equal 2, histories.length
    assert_equal [true, false], histories.map(&:has_snapshot?)
    assert_equal ['Value 3', 'Value 4'],
                 histories.map {|history| history.reconstructed_snapshot.first.fetch('name')}
  end

  def test_retention_does_not_reset_the_periodic_snapshot_sequence
    Setting.plugin_redmine_custom_field_manager = {
      'retention_days' => '',
      'max_generations' => '25'
    }
    before = [{'id' => 1, 'name' => 'Value 0', 'active' => true, 'position' => 1}]
    45.times do |index|
      after = [{'id' => 1, 'name' => "Value #{index + 1}", 'active' => true, 'position' => 1}]
      record(before, after)
      before = after
    end

    histories = RedmineCustomFieldManager::History.order(:id).to_a
    periodic = histories.find {|history| history.reconstructed_snapshot.first.fetch('name') == 'Value 40'}

    assert_equal 25, histories.length
    assert periodic
    assert periodic.has_snapshot?
    assert_equal 'Value 45', histories.last.reconstructed_snapshot.first.fetch('name')
  end

  def test_invalid_retention_setting_is_not_treated_as_unlimited
    Setting.plugin_redmine_custom_field_manager = {
      'retention_days' => 'invalid',
      'max_generations' => ''
    }

    assert_raises RedmineCustomFieldManager::InvalidChangeError do
      RedmineCustomFieldManager::HistoryMaintenance.retention_settings
    end
  end

  def test_malformed_retention_setting_is_not_treated_as_unlimited
    Setting.plugin_redmine_custom_field_manager = 'invalid'

    assert_raises RedmineCustomFieldManager::InvalidChangeError do
      RedmineCustomFieldManager::HistoryMaintenance.retention_settings
    end
  end

  def test_history_columns_accept_a_ten_thousand_item_snapshot_and_diff
    before = Array.new(10_000) do |index|
      {'id' => index + 1, 'name' => "Value #{index + 1}", 'active' => true, 'position' => index + 1}
    end
    after = before.reverse_each.with_index.map do |item, index|
      item.merge('position' => index + 1)
    end

    history = record(before, after)

    assert_operator history.snapshot_json.bytesize, :>, 65_535
    assert_operator history.changes_json.bytesize, :>, 65_535
    assert_equal after, history.reconstructed_snapshot
  end

  private

  def record(before, after)
    RedmineCustomFieldManager::HistoryRecorder.record!(
      :scope_key => 'custom_field_enumerations:99',
      :target_type => 'custom_field_enumerations',
      :target_id => 99,
      :operation => 'update',
      :user => User.find(1),
      :base_digest => RedmineCustomFieldManager::Snapshot.digest(before),
      :result_digest => RedmineCustomFieldManager::Snapshot.digest(after),
      :before_snapshot => before,
      :after_snapshot => after
    )
  end
end
