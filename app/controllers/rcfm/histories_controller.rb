# frozen_string_literal: true

module Rcfm
  class HistoriesController < ApplicationController
    layout 'admin'
    self.main_menu = false

    before_action :require_admin
    before_action :find_history, :only => [:show, :restore_preview, :restore]

    def index
      scope = RedmineCustomFieldManager::History.all
      scope = scope.where(:scope_key => params[:scope_key]) if params[:scope_key].present?
      @history_count = scope.count
      @history_pages = Paginator.new(@history_count, per_page_option, params[:page])
      @histories = scope.select(:id, :scope_key, :target_type, :target_id, :operation, :user_id, :has_snapshot, :created_at)
                   .includes(:user)
                   .order(:id => :desc)
                   .limit(@history_pages.per_page)
                   .offset(@history_pages.offset)
      load_history_target_names(@histories)
    end

    def show
      load_history_target_names([@history])
      @changes = @history.parsed_changes
      @snapshot = @history.reconstructed_snapshot
    rescue JSON::ParserError, RedmineCustomFieldManager::InvalidChangeError
      flash.now[:error] = l(:rcfm_error_invalid_change)
      @changes = {}
      @snapshot = []
    end

    def destroy
      RedmineCustomFieldManager::HistoryMaintenance.delete_ids!(params.require(:history_ids))
      flash[:notice] = l(:rcfm_history_deleted)
      redirect_to rcfm_histories_path
    rescue RedmineCustomFieldManager::InvalidChangeError, ActionController::ParameterMissing
      flash[:error] = l(:rcfm_error_invalid_change)
      redirect_to rcfm_histories_path
    end

    def cleanup
      cutoff = Time.zone.parse(params.require(:before).to_s)
      raise RedmineCustomFieldManager::InvalidChangeError unless cutoff

      RedmineCustomFieldManager::HistoryMaintenance.delete_before!(cutoff)
      flash[:notice] = l(:rcfm_history_deleted)
      redirect_to rcfm_histories_path
    rescue ArgumentError, RedmineCustomFieldManager::InvalidChangeError, ActionController::ParameterMissing
      flash[:error] = l(:rcfm_error_invalid_change)
      redirect_to rcfm_histories_path
    end

    def restore_preview
      load_history_target_names([@history])
      @preview = restorer.preview
    rescue RedmineCustomFieldManager::InvalidChangeError
      flash[:error] = l(:rcfm_error_invalid_change)
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
    rescue RedmineCustomFieldManager::InvalidChangeError, ActionController::ParameterMissing
      flash[:error] = l(:rcfm_error_invalid_change)
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

    def load_history_target_names(histories)
      ids = histories.filter_map do |history|
        history.target_id if history.target_type == 'custom_field_enumerations'
      end
      @history_target_names = CustomField.where(:id => ids).pluck(:id, :name).to_h
    end
  end
end
