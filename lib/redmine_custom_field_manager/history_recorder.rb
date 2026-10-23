# frozen_string_literal: true

module RedmineCustomFieldManager
  class HistoryRecorder
    SNAPSHOT_INTERVAL = 20

    def self.record!(scope_key:, target_type:, target_id:, operation:, user:, base_digest:,
                     result_digest:, before_snapshot:, after_snapshot:, metadata: {})
      History.transaction do
        revision = Revision.lock_for!("history:#{scope_key}")
        generation = revision.sequence + 1
        has_snapshot = generation == 1 || (generation % SNAPSHOT_INTERVAL).zero?
        changes = metadata.stringify_keys.merge('diff' => diff(before_snapshot, after_snapshot))
        history = History.create!(
          :scope_key => scope_key,
          :target_type => target_type,
          :target_id => target_id,
          :operation => operation,
          :user_id => user && user.id,
          :base_digest => base_digest,
          :result_digest => result_digest,
          :changes_json => JSON.generate(changes),
          :snapshot_json => has_snapshot ? JSON.generate(after_snapshot) : 'null',
          :has_snapshot => has_snapshot
        )
        revision.bump!
        HistoryMaintenance.prune_scope!(scope_key)
        history
      end
    end

    def self.diff(before_snapshot, after_snapshot)
      before = Array(before_snapshot).index_by {|item| item.fetch('id').to_s}
      after = Array(after_snapshot).index_by {|item| item.fetch('id').to_s}
      (before.keys | after.keys).filter_map do |key|
        old_value = before[key]
        new_value = after[key]
        next if old_value == new_value

        {'id' => key, 'before' => old_value, 'after' => new_value}
      end
    end
  end
end
