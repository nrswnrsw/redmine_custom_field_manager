# frozen_string_literal: true

module RedmineCustomFieldManager
  module SettingsControllerPatch
    extend ActiveSupport::Concern

    included do
      before_action :rcfm_validate_retention_settings, :only => :plugin
    end

    private

    def rcfm_validate_retention_settings
      return unless request.post? && params[:id].to_s == 'redmine_custom_field_manager'

      values = params[:settings] ? params[:settings].permit!.to_h : {}
      return if HistoryMaintenance.valid_retention_settings?(values)

      @plugin = Redmine::Plugin.find('redmine_custom_field_manager')
      @partial = @plugin.settings[:partial]
      @settings = values
      flash.now[:error] = l(:rcfm_retention_invalid)
      render :plugin, :status => :unprocessable_content
    end
  end
end
