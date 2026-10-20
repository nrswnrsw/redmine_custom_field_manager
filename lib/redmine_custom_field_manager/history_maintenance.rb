# frozen_string_literal: true

module RedmineCustomFieldManager
  module HistoryMaintenance
    module_function

    def delete_ids!(ids)
      ids = Array(ids).map {|id| Integer(id.to_s, 10)}.uniq
      History.transaction do
        scopes = History.where(:id => ids).distinct.pluck(:scope_key).sort
        lock_scopes!(scopes)
        targets = History.where(:id => ids).lock.to_a
        raise InvalidChangeError, 'one or more selected histories do not exist' unless targets.length == ids.length

        delete_materialized!(targets)
      end
    rescue ArgumentError, TypeError
      raise InvalidChangeError, 'history IDs must be integers'
    end

    def delete_before!(time)
      History.transaction do
        scopes = History.where(:created_at => ...time).distinct.pluck(:scope_key).sort
        lock_scopes!(scopes)
        targets = History.where(:created_at => ...time).lock.to_a
        delete_materialized!(targets)
      end
    end

    def prune_scope!(scope_key)
      settings = retention_settings
      return if settings.values.all?(&:nil?)

      relation = History.where(:scope_key => scope_key).order(:id => :desc)
      ids = []
      if settings[:max_generations]
        ids.concat(relation.offset(settings[:max_generations]).pluck(:id))
      end
      if settings[:retention_days]
        cutoff = settings[:retention_days].days.ago
        ids.concat(relation.where(:created_at => ...cutoff).pluck(:id))
      end
      targets = History.where(:id => ids.uniq).lock.to_a
      delete_materialized!(targets)
    end

    def retention_settings
      values = Setting.plugin_redmine_custom_field_manager || {}
      {
        :retention_days => positive_integer(values['retention_days']),
        :max_generations => positive_integer(values['max_generations'])
      }
    rescue NoMethodError
      {:retention_days => nil, :max_generations => nil}
    end

    def positive_integer(value)
      return if value.blank?

      parsed = Integer(value.to_s, 10)
      parsed if parsed.positive?
    rescue ArgumentError, TypeError
      nil
    end

    def delete_materialized!(targets)
      return 0 if targets.empty?

      ids = targets.map(&:id)
      scopes = targets.map(&:scope_key).uniq
      snapshots = {}
      History.where(:scope_key => scopes).where.not(:id => ids).order(:id).each do |history|
        snapshots[history.id] = HistoryReconstructor.new(history).snapshot
      end
      snapshots.each do |id, snapshot|
        History.where(:id => id).update_all(
          :has_snapshot => true,
          :snapshot_json => JSON.generate(snapshot)
        )
      end
      History.where(:id => ids).delete_all
    end

    def lock_scopes!(scopes)
      scopes.each {|scope| Revision.lock_for!("history:#{scope}")}
    end
  end
end
