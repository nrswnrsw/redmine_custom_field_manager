# frozen_string_literal: true

require_relative '../test_helper'

class RedmineCustomFieldManagerSnapshotTest < ActiveSupport::TestCase
  def setup
    @custom_field = IssueCustomField.create!(:name => 'RCFM snapshot', :field_format => 'string')
  end

  def test_digest_is_stable_for_the_same_custom_field_state
    first = digest
    second = digest

    assert_equal first, second
    assert_match(/\A[0-9a-f]{64}\z/, first)
  end

  def test_digest_changes_when_a_tracked_attribute_changes
    before = digest

    @custom_field.update_columns(:name => "#{@custom_field.name} changed")

    assert_not_equal before, digest
  end

  private

  def digest
    RedmineCustomFieldManager::Snapshot.custom_fields_digest(:field_type => 'IssueCustomField')
  end
end
