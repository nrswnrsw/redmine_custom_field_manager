# frozen_string_literal: true

require_relative '../test_helper'
require 'securerandom'
require 'timeout'

class RedmineCustomFieldManagerConcurrentEnumerationUsageTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  def setup
    @field = GroupCustomField.create!(
      :name => "RCFM concurrent usage #{SecureRandom.hex(4)}",
      :field_format => 'enumeration',
      :is_required => false
    )
    @value = @field.enumerations.create!(:name => 'Concurrent value')
    @group = Group.generate!
  end

  def teardown
    CustomValue.where(:custom_field_id => @field&.id).delete_all if @field
    CustomFieldEnumeration.where(:custom_field_id => @field&.id).delete_all if @field
    CustomField.where(:id => @field&.id).delete_all if @field
    User.where(:id => @group&.id).delete_all if @group
    RedmineCustomFieldManager::History.where(:scope_key => scope_key).delete_all if @field
    RedmineCustomFieldManager::Revision.where(:scope_key => scope_key).delete_all if @field
  end

  def test_committed_usage_blocks_a_concurrent_deletion
    skip_unless_row_locks!
    usage_ready = Queue.new
    release_usage = Queue.new
    deletion_started = Queue.new
    base_digest = RedmineCustomFieldManager::Snapshot.enumerations_digest(@field)

    usage_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        CustomValue.transaction do
          CustomValue.create!(
            :customized => Group.find(@group.id),
            :custom_field => GroupCustomField.find(@field.id),
            :value => @value.id.to_s
          )
          usage_ready << true
          wait_for(release_usage)
        end
      end
    end
    wait_for(usage_ready)

    deletion_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        deletion_started << true
        begin
          enumeration_updater(base_digest).call
          nil
        rescue StandardError => e
          e
        end
      end
    end
    wait_for(deletion_started)
    release_usage << true

    thread_value!(usage_thread)
    error = thread_value!(deletion_thread)
    assert_kind_of RedmineCustomFieldManager::ProtectedDeletionError, error
    assert CustomFieldEnumeration.exists?(@value.id)
    assert CustomValue.where(:custom_field_id => @field.id, :value => @value.id.to_s).exists?
  ensure
    release_usage << true if usage_thread&.alive?
    usage_thread&.join(5)
    deletion_thread&.join(5)
  end

  def test_committed_deletion_rejects_a_concurrent_new_usage
    skip_unless_row_locks!
    deletion_ready = Queue.new
    release_deletion = Queue.new
    usage_started = Queue.new

    deletion_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        RedmineCustomFieldManager::Revision.transaction do
          RedmineCustomFieldManager::Revision.lock_for!(scope_key)
          CustomFieldEnumeration.where(:id => @value.id, :custom_field_id => @field.id).delete_all
          deletion_ready << true
          wait_for(release_deletion)
        end
      end
    end
    wait_for(deletion_ready)

    usage_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        usage_started << true
        begin
          CustomValue.create!(
            :customized => Group.find(@group.id),
            :custom_field => GroupCustomField.find(@field.id),
            :value => @value.id.to_s
          )
          nil
        rescue StandardError => e
          e
        end
      end
    end
    wait_for(usage_started)
    release_deletion << true

    thread_value!(deletion_thread)
    error = thread_value!(usage_thread)
    assert_kind_of ActiveRecord::RecordInvalid, error
    assert_not CustomFieldEnumeration.exists?(@value.id)
    assert_not CustomValue.where(:custom_field_id => @field.id, :value => @value.id.to_s).exists?
  ensure
    release_deletion << true if deletion_thread&.alive?
    deletion_thread&.join(5)
    usage_thread&.join(5)
  end

  private

  def skip_unless_row_locks!
    skip 'SQLite does not provide row-level locking' if ActiveRecord::Base.connection.adapter_name.match?(/sqlite/i)
  end

  def scope_key
    "custom_field_enumerations:#{@field.id}"
  end

  def enumeration_updater(base_digest)
    RedmineCustomFieldManager::EnumerationUpdater.new(
      :custom_field => GroupCustomField.find(@field.id),
      :items => [{
        'client_id' => @value.id.to_s,
        'id' => @value.id,
        'name' => @value.name,
        'active' => true,
        'deleted' => true
      }],
      :base_digest => base_digest,
      :user => nil
    )
  end

  def wait_for(queue)
    Timeout.timeout(10) { queue.pop }
  end

  def thread_value!(thread)
    raise 'concurrent test thread timed out' unless thread.join(10)

    thread.value
  end
end
