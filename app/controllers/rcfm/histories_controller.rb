# frozen_string_literal: true

module Rcfm
  class HistoriesController < ApplicationController
    layout 'admin'
    self.main_menu = false

    before_action :require_admin
    before_action :find_history, :only => [:show, :restore_preview, :restore]

    def index
      @histories = RedmineCustomFieldManager::History
                   .select(:id, :scope_key, :target_type, :target_id, :operation, :user_id, :has_snapshot, :created_at)
                   .order(:id => :desc)
    end

    def show
      @changes = @history.parsed_changes
      @snapshot = @history.reconstructed_snapshot
    rescue JSON::ParserError, RedmineCustomFieldManager::InvalidChangeError => e
      flash.now[:error] = e.message
      @changes = {}
      @snapshot = []
    end

    def destroy
      RedmineCustomFieldManager::HistoryMaintenance.delete_ids!(params.require(:history_ids))
      flash[:notice] = l(:rcfm_history_deleted)
      redirect_to rcfm_histories_path
    rescue RedmineCustomFieldManager::InvalidChangeError, ActionController::ParameterMissing => e
      flash[:error] = e.message
      redirect_to rcfm_histories_path
    end

    def cleanup
      cutoff = Time.zone.parse(params.require(:before).to_s)
      raise RedmineCustomFieldManager::InvalidChangeError, 'cleanup date is invalid' unless cutoff

      RedmineCustomFieldManager::HistoryMaintenance.delete_before!(cutoff)
      flash[:notice] = l(:rcfm_history_deleted)
      redirect_to rcfm_histories_path
    rescue ArgumentError, RedmineCustomFieldManager::InvalidChangeError, ActionController::ParameterMissing => e
      flash[:error] = e.message
      redirect_to rcfm_histories_path
    end

    def restore_preview
      @preview = restorer.preview
    rescue RedmineCustomFieldManager::InvalidChangeError => e
      flash[:error] = e.message
      redirect_to rcfm_history_path(@history)
    end

    def restore
      restorer.apply!(
        :base_digest => params.require(:base_digest),
        :plan_digest => params.require(:plan_digest)
      )
      flash[:notice] = l(:rcfm_history_restored)
      redirect_to rcfm_histories_path
    rescue RedmineCustomFieldManager::ConflictError
      flash[:error] = l(:rcfm_restore_conflict)
      redirect_to rcfm_history_path(@history)
    rescue RedmineCustomFieldManager::ProtectedDeletionError => e
      flash[:error] = "#{l(:rcfm_error_used_enumerations)} #{e.protected_items.pluck('name').join(', ')}"
      redirect_to rcfm_history_path(@history)
    rescue RedmineCustomFieldManager::InvalidChangeError, ActionController::ParameterMissing => e
      flash[:error] = e.message
      redirect_to rcfm_history_path(@history)
    end

    private

    def find_history
      @history = RedmineCustomFieldManager::History.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      render_404
    end

    def restorer
      RedmineCustomFieldManager::HistoryRestorer.new(:history => @history, :user => User.current)
    end
  end
end
