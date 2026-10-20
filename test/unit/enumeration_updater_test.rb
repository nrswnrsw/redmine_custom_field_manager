# frozen_string_literal: true

require_relative '../test_helper'

class RedmineCustomFieldManagerEnumerationUpdaterTest < ActiveSupport::TestCase
  fixtures :users

  def setup
    @field = GroupCustomField.create!(
      :name => 'RCFM key value list',
      :field_format => 'enumeration',
      :is_required => false
    )
    @first = @field.enumerations.create!(:name => 'First')
    @second = @field.enumerations.create!(:name => 'Second')
    @base_digest = digest
  end

  def test_updates_adds_and_reorders_atomically_without_changing_existing_ids
    items = [
      item_for(@second, :name => 'Second renamed', :active => false),
      {'client_id' => 'new-one', 'name' => 'New value', 'active' => true, 'deleted' => false},
      item_for(@first)
    ]

    assert_difference 'RedmineCustomFieldManager::History.count', 1 do
      result = updater(items).call
      assert_equal ['new-one'], result.created_ids.keys
    end

    values = @field.reload.enumerations.reorder(:position, :id).to_a
    assert_equal [@second.id, result_id_for('new-one'), @first.id], values.map(&:id)
    assert_equal ['Second renamed', 'New value', 'First'], values.map(&:name)
    assert_equal [false, true, true], values.map(&:active?)
    assert_equal [1, 2, 3], values.map(&:position)
  end

  def test_deletes_an_unused_value
    updater([item_for(@first, :deleted => true), item_for(@second)]).call

    assert_not CustomFieldEnumeration.exists?(@first.id)
    assert CustomFieldEnumeration.exists?(@second.id)
  end

  def test_rejects_deleting_a_used_value_and_rolls_back_all_changes
    group = Group.generate!
    group.custom_field_values = {@field.id.to_s => @first.id.to_s}
    group.save!
    original_names = @field.enumerations.reorder(:position, :id).pluck(:id, :name)
    items = [
      item_for(@first, :deleted => true),
      item_for(@second, :name => 'Must roll back')
    ]

    error = assert_raises RedmineCustomFieldManager::ProtectedDeletionError do
      updater(items).call
    end

    assert_equal [@first.id], error.protected_items.map {|item| item.fetch('id')}
    assert_equal original_names, @field.reload.enumerations.reorder(:position, :id).pluck(:id, :name)
  end

  def test_rejects_deleting_the_default_value
    @field.update!(:default_value => @first.id.to_s)
    @base_digest = digest

    error = assert_raises RedmineCustomFieldManager::ProtectedDeletionError do
      updater([item_for(@first, :deleted => true), item_for(@second)]).call
    end

    assert_equal ['default_value'], error.protected_items.first.fetch('reasons')
  end

  def test_detects_conflict_and_requires_the_exact_confirmed_server_digest_for_force
    desired = [item_for(@first, :name => 'Mine'), item_for(@second)]
    @first.update!(:name => 'Theirs')
    current_digest = digest

    assert_raises RedmineCustomFieldManager::ConflictError do
      updater(desired).call
    end

    @second.update!(:name => 'Changed again')
    assert_raises RedmineCustomFieldManager::ConflictError do
      updater(desired, :force => true, :confirmed_digest => current_digest).call
    end

    current_digest = digest
    result = updater(desired, :force => true, :confirmed_digest => current_digest).call
    assert_equal 'Mine', @first.reload.name
    assert_equal result.digest, digest
  end

  def test_rejects_payload_that_omits_an_existing_id
    assert_raises RedmineCustomFieldManager::InvalidChangeError do
      updater([item_for(@first)]).call
    end
  end

  private

  def item_for(record, overrides = {})
    {
      'client_id' => record.id.to_s,
      'id' => record.id,
      'name' => record.name,
      'active' => record.active?,
      'deleted' => false
    }.merge(overrides.stringify_keys)
  end

  def updater(items, options = {})
    RedmineCustomFieldManager::EnumerationUpdater.new(
      :custom_field => @field,
      :items => items,
      :base_digest => @base_digest,
      :user => User.find(1),
      :force => options[:force],
      :confirmed_digest => options[:confirmed_digest]
    )
  end

  def digest
    RedmineCustomFieldManager::Snapshot.enumerations_digest(@field.reload)
  end

  def result_id_for(client_id)
    JSON.parse(RedmineCustomFieldManager::History.last.changes_json)
      .fetch('created_ids')
      .fetch(client_id)
  end
end
