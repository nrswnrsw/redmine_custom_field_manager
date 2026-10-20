# frozen_string_literal: true

module Rcfm
  class CustomFieldsController < ApplicationController
    layout 'admin'
    self.main_menu = false

    before_action :require_admin

    def update_order
      result = RedmineCustomFieldManager::CustomFieldOrderUpdater.new(
        :field_type => params.require(:field_type),
        :ordered_ids => ordered_ids,
        :base_digest => params.require(:base_digest),
        :user => User.current,
        :force => params[:force],
        :confirmed_digest => params[:confirmed_digest],
        :resolution => params[:resolution]
      ).call

      render :json => {
        :ok => true,
        :changed_ids => result.changed_ids,
        :digest => result.digest
      }
    rescue RedmineCustomFieldManager::ConflictError => e
      analysis = RedmineCustomFieldManager::ConflictAnalysis.custom_fields(
        :base_snapshot => parsed_base_snapshot,
        :mine_ids => ordered_ids,
        :current_snapshot => e.current_snapshot,
        :base_digest => params[:base_digest]
      )
      render :json => {
        :ok => false,
        :error => 'conflict',
        :message => l(:rcfm_error_conflict),
        :current_digest => e.current_digest
      }.merge(analysis), :status => :conflict
    rescue RedmineCustomFieldManager::InvalidChangeError, ActionController::ParameterMissing, JSON::ParserError => e
      render :json => {
        :ok => false,
        :error => 'invalid_change',
        :message => e.message
      }, :status => :unprocessable_content
    end

    private

    def ordered_ids
      value = params.require(:ordered_ids)
      value.is_a?(String) ? JSON.parse(value) : Array(value)
    end

    def parsed_base_snapshot
      value = params[:base_snapshot]
      return [] if value.blank?

      value.is_a?(String) ? JSON.parse(value) : Array(value)
    end
  end
end
