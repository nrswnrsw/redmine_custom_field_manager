# frozen_string_literal: true

require_relative '../test_helper'

class RedmineCustomFieldManagerCustomFieldsViewTest < Redmine::IntegrationTest
  def test_standard_custom_fields_page_uses_the_manager_view
    log_user('admin', 'admin')

    get '/custom_fields', :params => {:tab => 'IssueCustomField'}

    assert_response :success
    assert_select 'form.rcfm-manager[data-rcfm-manager="custom-fields"]'
    assert_select 'input.rcfm-ordered-ids'
    assert_select 'input.rcfm-base-snapshot'
    assert_select 'button.rcfm-undo', :text => 'Undo'
    assert_select 'button.rcfm-redo', :text => 'Redo'
    assert_select '.rcfm-selection-count', :text => '0 selected'
    assert_select 'input.rcfm-target[placeholder="Enter a destination name"]'
    assert_select '.rcfm-conflict .rcfm-conflict-merge'
    assert_select 'script[src*="plugin_assets/redmine_custom_field_manager"]'
  end

  def test_standard_enumerations_page_uses_the_staged_manager_view
    field = GroupCustomField.create!(:name => 'RCFM integration list', :field_format => 'enumeration')
    value = field.enumerations.create!(:name => 'Visible value')
    field.update!(:default_value => value.id.to_s)
    log_user('admin', 'admin')

    get "/custom_fields/#{field.id}/enumerations"

    assert_response :success
    assert_select 'form.rcfm-enumeration-manager[data-rcfm-manager="enumerations"]'
    assert_select '.rcfm-enumeration-name', :text => 'Visible value'
    assert_select 'input.rcfm-items'
    assert_select 'input.rcfm-base-snapshot'
    assert_select 'button.rcfm-undo', :text => 'Undo'
    assert_select 'button.rcfm-redo', :text => 'Redo'
    assert_select '.rcfm-selection-count', :text => '0 selected'
    assert_select 'input.rcfm-target[placeholder="Enter a destination name"]'
    assert_select '.rcfm-conflict .rcfm-conflict-merge'
    assert_select 'a.rcfm-csv-export'
    assert_select 'a.rcfm-csv-template[href*="template=1"]'
    assert_select '.rcfm-csv-import .info', :text => /Save or discard/
    assert_select '.rcfm-protection-indicator[title*="default value"]'
    assert_select '.rcfm-protected-help'
    assert_select 'input.rcfm-csv-file'
    assert_select 'button.rcfm-csv-preview-button'
    assert_select 'script[src*="enumeration_manager"]'
  end
end
