# frozen_string_literal: true

require_relative '../test_helper'

class RedmineCustomFieldManagerHistoryTest < ActiveSupport::TestCase
  fixtures :users

  def setup
    RedmineCustomFieldManager::History.delete_all
    Setting.plugin_redmine_custom_field_manager = {
      'retention_days' => '',
      'max_generations' => ''
    }
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
    assert histories.all?(&:has_snapshot?)
    assert_equal ['Value 2', 'Value 3'], histories.map {|history| history.reconstructed_snapshot.first.fetch('name')}
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
