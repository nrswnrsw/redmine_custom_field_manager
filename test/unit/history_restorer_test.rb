# frozen_string_literal: true

require_relative '../test_helper'

class RedmineCustomFieldManagerHistoryRestorerTest < ActiveSupport::TestCase
  fixtures :users

  def setup
    RedmineCustomFieldManager::History.delete_all
    Setting.plugin_redmine_custom_field_manager = {'retention_days' => '', 'max_generations' => ''}
    @field = GroupCustomField.create!(:name => 'RCFM restore list', :field_format => 'enumeration')
    @first = @field.enumerations.create!(:name => 'First')
    @second = @field.enumerations.create!(:name => 'Second')
  end

  def test_restores_the_entire_enumeration_target_and_records_the_restore
    update_enumerations('State A', true)
    selected_history = RedmineCustomFieldManager::History.last
    update_enumerations('State B', false)
    restorer = RedmineCustomFieldManager::HistoryRestorer.new(
      :history => selected_history,
      :user => User.find(1)
    )
    preview = restorer.preview

    restorer.apply!(:base_digest => preview.base_digest, :plan_digest => preview.plan_digest)

    assert_equal 'State A', @first.reload.name
    assert @second.reload.active?
    assert_equal 'restore', RedmineCustomFieldManager::History.last.operation
  end

  def test_restore_is_blocked_when_it_would_delete_a_used_value
    update_enumerations('Historical', true)
    selected_history = RedmineCustomFieldManager::History.last
    extra = @field.enumerations.create!(:name => 'Used later')
    group = Group.generate!
    group.custom_field_values = {@field.id.to_s => extra.id.to_s}
    group.save!

    preview = RedmineCustomFieldManager::HistoryRestorer.new(
      :history => selected_history,
      :user => User.find(1)
    ).preview

    assert preview.blockers.any? {|message| message.include?(extra.id.to_s)}
    assert_raises RedmineCustomFieldManager::InvalidChangeError do
      RedmineCustomFieldManager::HistoryRestorer.new(
        :history => selected_history,
        :user => User.find(1)
      ).apply!(:base_digest => preview.base_digest, :plan_digest => preview.plan_digest)
    end
  end

  def test_restore_is_blocked_when_a_historical_id_no_longer_exists
    update_enumerations('Historical', true)
    selected_history = RedmineCustomFieldManager::History.last
    CustomFieldEnumeration.where(:id => @first.id).delete_all

    preview = RedmineCustomFieldManager::HistoryRestorer.new(
      :history => selected_history,
      :user => User.find(1)
    ).preview

    assert preview.blockers.any? {|message| message.include?(@first.id.to_s)}
  end

  def test_restore_rejects_a_stale_preview
    update_enumerations('Historical', true)
    selected_history = RedmineCustomFieldManager::History.last
    update_enumerations('Current', true)
    restorer = RedmineCustomFieldManager::HistoryRestorer.new(
      :history => selected_history,
      :user => User.find(1)
    )
    preview = restorer.preview
    @second.update!(:active => false)

    assert_raises RedmineCustomFieldManager::InvalidChangeError do
      restorer.apply!(:base_digest => preview.base_digest, :plan_digest => preview.plan_digest)
    end
    assert_equal 'Current', @first.reload.name
  end

  def test_restores_only_the_custom_field_ordering_scope
    first_field = IssueCustomField.create!(:name => 'Restore order first', :field_format => 'string')
    second_field = IssueCustomField.create!(:name => 'Restore order second', :field_format => 'string')
    original = CustomField.where(:type => 'IssueCustomField').order(:position, :id).pluck(:id)
    desired = original.reverse
    RedmineCustomFieldManager::CustomFieldOrderUpdater.new(
      :field_type => 'IssueCustomField',
      :ordered_ids => desired,
      :base_digest => RedmineCustomFieldManager::Snapshot.custom_fields_digest(:field_type => 'IssueCustomField'),
      :user => User.find(1)
    ).call
    selected_history = RedmineCustomFieldManager::History.last
    first_field.update!(:name => 'Name must not be restored')
    RedmineCustomFieldManager::CustomFieldOrderUpdater.new(
      :field_type => 'IssueCustomField',
      :ordered_ids => original,
      :base_digest => RedmineCustomFieldManager::Snapshot.custom_fields_digest(:field_type => 'IssueCustomField'),
      :user => User.find(1)
    ).call
    restorer = RedmineCustomFieldManager::HistoryRestorer.new(:history => selected_history, :user => User.find(1))
    preview = restorer.preview

    restorer.apply!(:base_digest => preview.base_digest, :plan_digest => preview.plan_digest)

    assert_equal desired, CustomField.where(:type => 'IssueCustomField').order(:position, :id).pluck(:id)
    assert_equal 'Name must not be restored', first_field.reload.name
    assert CustomField.exists?(second_field.id)
    assert_equal 'reorder_restore', RedmineCustomFieldManager::History.last.operation
  end

  private

  def update_enumerations(first_name, second_active)
    RedmineCustomFieldManager::EnumerationUpdater.new(
      :custom_field => @field,
      :items => [
        item_for(@first, :name => first_name),
        item_for(@second, :active => second_active)
      ],
      :base_digest => RedmineCustomFieldManager::Snapshot.enumerations_digest(@field.reload),
      :user => User.find(1)
    ).call
  end

  def item_for(record, overrides = {})
    {
      'client_id' => record.id.to_s,
      'id' => record.id,
      'name' => record.reload.name,
      'active' => record.active?,
      'deleted' => false
    }.merge(overrides.stringify_keys)
  end
end
