# frozen_string_literal: true

require_relative '../test_helper'

class RedmineCustomFieldManagerConflictAnalysisTest < ActiveSupport::TestCase
  def test_custom_field_order_can_merge_when_server_only_changed_metadata
    base = [
      {'id' => 1, 'type' => 'IssueCustomField', 'name' => 'One', 'position' => 1},
      {'id' => 2, 'type' => 'IssueCustomField', 'name' => 'Two', 'position' => 2}
    ]
    current = base.map(&:dup)
    current.first['name'] = 'One on server'

    analysis = RedmineCustomFieldManager::ConflictAnalysis.custom_fields(
      :base_snapshot => base,
      :mine_ids => [2, 1],
      :current_snapshot => current,
      :base_digest => RedmineCustomFieldManager::Snapshot.digest(base)
    )

    assert_equal [2, 1], analysis.fetch(:merge_proposal)
    assert analysis.fetch(:base_snapshot_valid)
  end

  def test_custom_field_order_does_not_propose_ambiguous_double_reorder
    base = [1, 2, 3].map do |id|
      {'id' => id, 'type' => 'IssueCustomField', 'name' => id.to_s, 'position' => id}
    end
    current = [2, 1, 3].map.with_index do |id, index|
      base.find {|item| item['id'] == id}.merge('position' => index + 1)
    end

    analysis = RedmineCustomFieldManager::ConflictAnalysis.custom_fields(
      :base_snapshot => base,
      :mine_ids => [1, 3, 2],
      :current_snapshot => current,
      :base_digest => RedmineCustomFieldManager::Snapshot.digest(base)
    )

    assert_nil analysis.fetch(:merge_proposal)
  end

  def test_enumerations_merge_independent_attribute_changes
    base = enumeration_snapshot
    mine = [
      {'client_id' => '1', 'id' => 1, 'name' => 'Mine', 'active' => true, 'deleted' => false},
      {'client_id' => '2', 'id' => 2, 'name' => 'Two', 'active' => true, 'deleted' => false}
    ]
    current = base.map(&:dup)
    current.last['active'] = false

    analysis = RedmineCustomFieldManager::ConflictAnalysis.enumerations(
      :base_snapshot => base,
      :mine_items => mine,
      :current_snapshot => current,
      :base_digest => RedmineCustomFieldManager::Snapshot.digest(base)
    )

    proposal = analysis.fetch(:merge_proposal)
    assert_equal 'Mine', proposal.first.fetch('name')
    assert_not proposal.last.fetch('active')
  end

  def test_enumerations_do_not_merge_different_changes_to_the_same_attribute
    base = enumeration_snapshot
    mine = [
      {'client_id' => '1', 'id' => 1, 'name' => 'Mine', 'active' => true, 'deleted' => false},
      {'client_id' => '2', 'id' => 2, 'name' => 'Two', 'active' => true, 'deleted' => false}
    ]
    current = base.map(&:dup)
    current.first['name'] = 'Server'

    analysis = RedmineCustomFieldManager::ConflictAnalysis.enumerations(
      :base_snapshot => base,
      :mine_items => mine,
      :current_snapshot => current,
      :base_digest => RedmineCustomFieldManager::Snapshot.digest(base)
    )

    assert_nil analysis.fetch(:merge_proposal)
  end

  private

  def enumeration_snapshot
    [
      {'id' => 1, 'name' => 'One', 'active' => true, 'position' => 1},
      {'id' => 2, 'name' => 'Two', 'active' => true, 'position' => 2}
    ]
  end
end
