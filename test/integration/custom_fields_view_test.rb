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
    assert_select '.rcfm-conflict .rcfm-conflict-merge'
    assert_select 'script[src*="plugin_assets/redmine_custom_field_manager"]'
  end

  def test_standard_enumerations_page_uses_the_staged_manager_view
    field = GroupCustomField.create!(:name => 'RCFM integration list', :field_format => 'enumeration')
    field.enumerations.create!(:name => 'Visible value')
    log_user('admin', 'admin')

    get "/custom_fields/#{field.id}/enumerations"

    assert_response :success
    assert_select 'form.rcfm-enumeration-manager[data-rcfm-manager="enumerations"]'
    assert_select '.rcfm-enumeration-name', :text => 'Visible value'
    assert_select 'input.rcfm-items'
    assert_select 'input.rcfm-base-snapshot'
    assert_select '.rcfm-conflict .rcfm-conflict-merge'
    assert_select 'a.rcfm-csv-export'
    assert_select 'input.rcfm-csv-file'
    assert_select 'button.rcfm-csv-preview-button'
    assert_select 'script[src*="enumeration_manager"]'
  end
end
