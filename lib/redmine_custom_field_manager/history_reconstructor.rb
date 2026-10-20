# frozen_string_literal: true

module RedmineCustomFieldManager
  class HistoryReconstructor
    def initialize(history)
      @history = history
    end

    def snapshot
      direct = parsed_snapshot(@history)
      return direct if direct

      anchor = History.where(:scope_key => @history.scope_key, :has_snapshot => true)
                      .where(:id => ...@history.id)
                      .order(:id => :desc)
                      .first
      raise InvalidChangeError, 'history cannot be reconstructed because its base snapshot is missing' unless anchor

      state = parsed_snapshot(anchor)
      History.where(:scope_key => @history.scope_key, :id => (anchor.id + 1)..@history.id).order(:id).each do |entry|
        state = apply_diff(state, entry)
      end
      state
    end

    private

    def parsed_snapshot(history)
      return unless history.has_snapshot?

      value = JSON.parse(history.snapshot_json)
      value if value.is_a?(Array)
    rescue JSON::ParserError
      raise InvalidChangeError, "history ##{history.id} contains an invalid snapshot"
    end

    def apply_diff(state, history)
      by_id = state.index_by {|item| item.fetch('id').to_s}
      changes = JSON.parse(history.changes_json).fetch('diff')
      changes.each do |change|
        key = change.fetch('id').to_s
        if change['after']
          by_id[key] = change.fetch('after')
        else
          by_id.delete(key)
        end
      end
      by_id.values.sort_by {|item| [item.fetch('position'), item.fetch('id')]}
    rescue JSON::ParserError, KeyError
      raise InvalidChangeError, "history ##{history.id} contains an invalid diff"
    end
  end
end
