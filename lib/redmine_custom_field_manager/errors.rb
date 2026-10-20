# frozen_string_literal: true

module RedmineCustomFieldManager
  class Error < StandardError; end

  class ConflictError < Error
    attr_reader :current_digest, :current_snapshot

    def initialize(current_digest:, current_snapshot:)
      @current_digest = current_digest
      @current_snapshot = current_snapshot
      super('The target was modified after editing started.')
    end
  end

  class InvalidChangeError < Error; end

  class ProtectedDeletionError < InvalidChangeError
    attr_reader :protected_items

    def initialize(protected_items)
      @protected_items = protected_items
      super('One or more enumerations are in use and cannot be deleted.')
    end
  end
end
