# frozen_string_literal: true

require_relative '../test_helper'

class RedmineCustomFieldManagerCustomFieldOrderUpdaterTest < ActiveSupport::TestCase
  fixtures :users

  def setup
    @first = IssueCustomField.create!(:name => 'RCFM first', :field_format => 'string')
    @other_type = ProjectCustomField.create!(:name => 'RCFM project', :field_format => 'string')
    @second = IssueCustomField.create!(:name => 'RCFM second', :field_format => 'string')
    @base_digest = RedmineCustomFieldManager::Snapshot.custom_fields_digest(:field_type => 'IssueCustomField')
  end

  def test_reorders_only_the_selected_type_slots_and_records_history
    other_type_position = @other_type.position
    issue_ids = CustomField.where(:type => 'IssueCustomField').order(:position, :id).pluck(:id)
    requested = issue_ids.reverse

    assert_difference 'RedmineCustomFieldManager::History.count', 1 do
      result = updater(requested).call
      assert result.changed_ids.any?
    end

    assert_equal requested, CustomField.where(:type => 'IssueCustomField').order(:position, :id).pluck(:id)
    assert_equal other_type_position, @other_type.reload.position
  end

  def test_rejects_a_stale_snapshot_without_partial_updates
    original_positions = CustomField.order(:id).pluck(:id, :position)
    @first.update!(:name => 'RCFM changed elsewhere')
    issue_ids = CustomField.where(:type => 'IssueCustomField').order(:position, :id).pluck(:id).reverse

    assert_no_difference 'RedmineCustomFieldManager::History.count' do
      assert_raises RedmineCustomFieldManager::ConflictError do
        updater(issue_ids).call
      end
    end

    assert_equal original_positions, CustomField.order(:id).pluck(:id, :position)
  end

  def test_rejects_missing_ids
    issue_ids = CustomField.where(:type => 'IssueCustomField').order(:position, :id).pluck(:id)

    assert_raises RedmineCustomFieldManager::InvalidChangeError do
      updater(issue_ids.drop(1)).call
    end
  end

  def test_force_requires_the_exact_confirmed_digest_and_is_recorded
    desired = CustomField.where(:type => 'IssueCustomField').order(:position, :id).pluck(:id).reverse
    @first.update!(:name => 'Changed elsewhere')
    current_digest = RedmineCustomFieldManager::Snapshot.custom_fields_digest(:field_type => 'IssueCustomField')

    assert_raises RedmineCustomFieldManager::ConflictError do
      updater(desired, :force => true, :confirmed_digest => 'wrong').call
    end

    result = updater(desired, :force => true, :confirmed_digest => current_digest).call
    assert_equal desired, result.snapshot.map {|item| item.fetch('id')}
    assert_equal 'reorder_force', RedmineCustomFieldManager::History.last.operation
  end

  private

  def updater(ids, options = {})
    RedmineCustomFieldManager::CustomFieldOrderUpdater.new(
      :field_type => 'IssueCustomField',
      :ordered_ids => ids,
      :base_digest => @base_digest,
      :user => User.find(1),
      :force => options[:force],
      :confirmed_digest => options[:confirmed_digest]
    )
  end
end
