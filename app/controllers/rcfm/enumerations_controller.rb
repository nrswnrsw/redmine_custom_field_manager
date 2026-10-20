# frozen_string_literal: true

module Rcfm
  class EnumerationsController < ApplicationController
    layout 'admin'
    self.main_menu = false

    before_action :require_admin
    before_action :find_custom_field

    def export
      template = params[:template].to_s == '1'
      send_data(
        RedmineCustomFieldManager::CsvExporter.new(@custom_field, template: template).generate,
        :filename => "custom_field_#{@custom_field.id}_enumerations#{'_template' if template}.csv",
        :type => 'text/csv; charset=utf-8',
        :disposition => 'attachment'
      )
    rescue RedmineCustomFieldManager::InvalidChangeError
      render :plain => l(:rcfm_error_invalid_change), :status => :unprocessable_content
    end

    def import_preview
      parsed = csv_parser.parse
      plan = import_plan(parsed)
      render :json => {
        :ok => true,
        :plan => plan.serializable_hash,
        :base_digest => RedmineCustomFieldManager::Snapshot.enumerations_digest(@custom_field)
      }
    rescue RedmineCustomFieldManager::InvalidChangeError, ActionController::ParameterMissing => e
      render_import_error(e)
    end

    def import
      parsed = csv_parser.parse
      result = RedmineCustomFieldManager::CsvImporter.new(
        :custom_field => @custom_field,
        :parsed => parsed,
        :mode => params.require(:mode),
        :mappings => hash_param(:mappings),
        :missing_default => params.fetch(:missing_default, 'disable'),
        :missing_actions => hash_param(:missing_actions),
        :base_digest => params.require(:base_digest),
        :plan_digest => params.require(:plan_digest),
        :user => User.current
      ).call
      render :json => {
        :ok => true,
        :digest => result.update_result.digest,
        :changed_ids => result.update_result.changed_ids,
        :created_ids => result.update_result.created_ids
      }
    rescue RedmineCustomFieldManager::ConflictError => e
      render :json => {
        :ok => false,
        :error => 'conflict',
        :message => l(:rcfm_error_enumeration_conflict),
        :current_digest => e.current_digest,
        :current_snapshot => e.current_snapshot
      }, :status => :conflict
    rescue RedmineCustomFieldManager::ProtectedDeletionError => e
      render :json => {
        :ok => false,
        :error => 'protected_deletion',
        :message => l(:rcfm_error_used_enumerations),
        :protected_items => e.protected_items
      }, :status => :unprocessable_content
    rescue RedmineCustomFieldManager::InvalidChangeError, ActionController::ParameterMissing => e
      render_import_error(e)
    end

    def update
      result = RedmineCustomFieldManager::EnumerationUpdater.new(
        :custom_field => @custom_field,
        :items => items,
        :base_digest => params.require(:base_digest),
        :user => User.current,
        :force => params[:force],
        :confirmed_digest => params[:confirmed_digest],
        :resolution => params[:resolution]
      ).call

      render :json => {
        :ok => true,
        :changed_ids => result.changed_ids,
        :created_ids => result.created_ids,
        :digest => result.digest
      }
    rescue RedmineCustomFieldManager::ConflictError => e
      analysis = RedmineCustomFieldManager::ConflictAnalysis.enumerations(
        :base_snapshot => parsed_base_snapshot,
        :mine_items => items,
        :current_snapshot => e.current_snapshot,
        :base_digest => params[:base_digest]
      )
      render :json => {
        :ok => false,
        :error => 'conflict',
        :message => l(:rcfm_error_enumeration_conflict),
        :current_digest => e.current_digest
      }.merge(analysis), :status => :conflict
    rescue RedmineCustomFieldManager::ProtectedDeletionError => e
      render :json => {
        :ok => false,
        :error => 'protected_deletion',
        :message => l(:rcfm_error_used_enumerations),
        :protected_items => e.protected_items
      }, :status => :unprocessable_content
    rescue RedmineCustomFieldManager::InvalidChangeError, ActionController::ParameterMissing, JSON::ParserError
      render :json => {
        :ok => false,
        :error => 'invalid_change',
        :message => l(:rcfm_error_invalid_change)
      }, :status => :unprocessable_content
    end

    private

    def find_custom_field
      @custom_field = CustomField.find(params[:custom_field_id])
    rescue ActiveRecord::RecordNotFound
      render_404
    end

    def items
      value = params.require(:items)
      value.is_a?(String) ? JSON.parse(value) : Array(value)
    end

    def parsed_base_snapshot
      value = params[:base_snapshot]
      return [] if value.blank?

      value.is_a?(String) ? JSON.parse(value) : Array(value)
    end

    def csv_parser
      RedmineCustomFieldManager::CsvParser.new(params.require(:csv_data))
    end

    def import_plan(parsed)
      RedmineCustomFieldManager::CsvImportPlan.new(
        :custom_field => @custom_field,
        :parsed => parsed,
        :mode => params.require(:mode),
        :mappings => hash_param(:mappings),
        :missing_default => params.fetch(:missing_default, 'disable'),
        :missing_actions => hash_param(:missing_actions)
      )
    end

    def hash_param(key)
      value = params[key]
      return {} if value.blank?
      return JSON.parse(value) if value.is_a?(String)
      return value.to_unsafe_h if value.respond_to?(:to_unsafe_h)

      value.to_h
    rescue JSON::ParserError, TypeError
      raise RedmineCustomFieldManager::InvalidChangeError, "#{key} must be an object"
    end

    def render_import_error(_error)
      render :json => {
        :ok => false,
        :error => 'invalid_import',
        :message => l(:rcfm_error_invalid_import)
      }, :status => :unprocessable_content
    end
  end
end
