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
      raise InvalidChangeError, 'retention settings must be an object' unless values.is_a?(Hash)

      {
        :retention_days => positive_integer(values['retention_days'], 'retention_days'),
        :max_generations => positive_integer(values['max_generations'], 'max_generations')
      }
    end

    def valid_retention_settings?(values)
      positive_integer(values['retention_days'], 'retention_days')
      positive_integer(values['max_generations'], 'max_generations')
      true
    rescue InvalidChangeError
      false
    end

    def positive_integer(value, name)
      return if value.blank?

      parsed = Integer(value.to_s, 10)
      raise InvalidChangeError, "#{name} must be a positive integer" unless parsed.positive?

      parsed
    rescue ArgumentError, TypeError
      raise InvalidChangeError, "#{name} must be a positive integer"
    end

    def delete_materialized!(targets)
      return 0 if targets.empty?

      ids = targets.map(&:id)
      scopes = targets.map(&:scope_key).uniq
      snapshots = boundary_histories(scopes, ids).to_h do |history|
        [history.id, HistoryReconstructor.new(history).snapshot]
      end
      snapshots.each do |id, snapshot|
        History.where(:id => id).update_all(
          :has_snapshot => true,
          :snapshot_json => JSON.generate(snapshot)
        )
      end
      History.where(:id => ids).delete_all
    end

    def boundary_histories(scopes, deleted_ids)
      deleted = deleted_ids.to_set
      boundary_ids = scopes.flat_map do |scope|
        previous_deleted = false
        History.where(:scope_key => scope).order(:id).pluck(:id).filter_map do |id|
          if deleted.include?(id)
            previous_deleted = true
            next
          end

          if previous_deleted
            previous_deleted = false
            id
          end
        end
      end
      History.where(:id => boundary_ids, :has_snapshot => false).order(:id).to_a
    end

    def lock_scopes!(scopes)
      scopes.each {|scope| Revision.lock_for!("history:#{scope}")}
    end
  end
end
