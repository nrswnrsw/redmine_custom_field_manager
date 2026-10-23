# frozen_string_literal: true

require_relative '../test_helper'

class RcfmSettingsControllerTest < Redmine::ControllerTest
  tests SettingsController
  fixtures :users

  def setup
    @request.session[:user_id] = 1
    Setting.plugin_redmine_custom_field_manager = {
      'retention_days' => '30',
      'max_generations' => '100'
    }
  end

  def test_invalid_retention_settings_are_rejected_without_overwriting_saved_values
    post :plugin, :params => {
      :id => 'redmine_custom_field_manager',
      :settings => {'retention_days' => '0', 'max_generations' => 'invalid'}
    }

    assert_response :unprocessable_content
    assert_equal I18n.t(:rcfm_retention_invalid), flash[:error]
    assert_equal '30', Setting.plugin_redmine_custom_field_manager['retention_days']
    assert_equal '100', Setting.plugin_redmine_custom_field_manager['max_generations']
    assert_select 'input[name="settings[retention_days]"][value="0"]'
  end

  def test_blank_or_positive_retention_settings_are_saved
    post :plugin, :params => {
      :id => 'redmine_custom_field_manager',
      :settings => {'retention_days' => '', 'max_generations' => '25'}
    }

    assert_redirected_to plugin_settings_path(Redmine::Plugin.find('redmine_custom_field_manager'))
    assert_equal '', Setting.plugin_redmine_custom_field_manager['retention_days']
    assert_equal '25', Setting.plugin_redmine_custom_field_manager['max_generations']
  end
end
