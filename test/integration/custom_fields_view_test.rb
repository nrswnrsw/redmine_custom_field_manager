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
    assert_select '.rcfm-selection-bar', :count => 0
    assert_select '.rcfm-custom-field-bulk-tools details.rcfm-operation-panel--move:not([open]) button.rcfm-move-selected'
    assert_select '.rcfm-custom-field-bulk-tools button.rcfm-select-all'
    assert_select '.rcfm-operation-panel--move summary', :text => /Move to a destination/
    assert_select '.rcfm-bulk-move-help', :text => /Select the items to move/
    assert_select '.rcfm-commit-bar button.rcfm-save.rcfm-button-primary', :text => 'Save changes'
    assert_select '.rcfm-commit-bar button.rcfm-reset', :text => 'Discard all unsaved changes'
    assert_select '.rcfm-bulk-move-count', :text => '0 selected'
    assert_operator response.body.index('class="list custom_fields rcfm-sortable"'), :<,
                    response.body.index('class="rcfm-custom-field-bulk-tools"')
    assert_select 'th', :text => /Individual actions/
    assert_select 'input.rcfm-select[aria-label*="for moving"]'
    assert_select 'a.rcfm-delete-custom-field[data-confirm*="Other checked fields will not be deleted"]'
    assert_select 'a.rcfm-delete-custom-field[data-confirm*="cannot be restored from change history"]'
    assert_select 'input.rcfm-target[placeholder="Enter a destination name"]'
    assert_select 'form.rcfm-manager[data-rcfm-target-required="Enter a destination name."]'
    assert_select 'form.rcfm-manager[data-rcfm-target-candidate*="current position"]'
    assert_select 'form.rcfm-manager[data-rcfm-target-candidate-selected="selected"]'
    assert_select '.rcfm-target-candidates[hidden]'
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
    assert_select '.rcfm-introduction',
                  :text => 'After you add or edit a choice, a Save changes button appears at the bottom of the page. Press it to make your changes final.'
    assert_select '.rcfm-enumeration-name', :text => 'Visible value'
    assert_select 'table.rcfm-enumerations thead th:first-child', :text => 'Select'
    assert_select 'table.rcfm-enumerations thead th:first-child .hidden-for-sighted', :count => 0
    assert_select 'table.rcfm-enumerations thead th:last-child .hidden-for-sighted',
                  :text => 'Individual actions'
    assert_select 'input.rcfm-items'
    assert_select 'input.rcfm-base-snapshot'
    assert_select 'button.rcfm-undo', :text => 'Undo'
    assert_select 'button.rcfm-redo', :text => 'Redo'
    assert_select 'details.rcfm-enumeration-selection-tools:not([open])'
    assert_select 'details.rcfm-enumeration-selection-tools.box', :count => 0
    assert_select '.rcfm-enumeration-selection-tools button.rcfm-select-all'
    assert_select '.rcfm-operation-panel--state button.rcfm-activate-selected'
    assert_select '.rcfm-operation-panel--state button.rcfm-delete-selected.rcfm-button-danger'
    assert_select '.rcfm-operation-panel--state h3', :text => 'Status and deletion'
    assert_select 'details.rcfm-operation-panel--move:not([open]) button.rcfm-move-selected'
    assert_select '.rcfm-operation-panel--move summary', :text => /Move to a destination/
    assert_select '.rcfm-commit-bar button.rcfm-save.rcfm-button-primary', :text => 'Save changes'
    assert_select '.rcfm-commit-bar button.rcfm-reset', :text => 'Discard all unsaved changes'
    assert_select '.rcfm-selection-count', :text => '0 selected'
    assert_select 'input.rcfm-target[placeholder="Enter a destination name"]'
    assert_select 'form.rcfm-enumeration-manager[data-rcfm-target-required="Enter a destination name."]'
    assert_select 'form.rcfm-enumeration-manager[data-rcfm-target-candidate*="current position"]'
    assert_select 'form.rcfm-enumeration-manager[data-rcfm-target-candidate-selected="selected"]'
    assert_select '.rcfm-target-candidates[hidden]'
    assert_select '.rcfm-conflict .rcfm-conflict-merge'
    assert_select 'a.rcfm-csv-export'
    assert_select 'a.rcfm-csv-template[href*="template=1"]'
    assert_select '.rcfm-csv-import .info', :text => /Save or discard/
    assert_select '.rcfm-protection-indicator[title*="default value"] .icon-svg'
    assert_select '.rcfm-protected-help', :text => 'Locked values are in use or are defaults and cannot be deleted.'
    assert_select '.rcfm-single-add label', :text => 'New choice'
    assert_select 'input.rcfm-add-one-input[placeholder="Enter a value name"][aria-describedby="rcfm-add-one-error"]'
    assert_select '#rcfm-add-one-error.rcfm-field-error[role="alert"][hidden]'
    assert_select 'button.rcfm-add-one', :text => 'Add'
    assert_select '.rcfm-bulk-add-input[aria-label="Add multiple values"][aria-describedby="rcfm-bulk-add-error"]'
    assert_select '#rcfm-bulk-add-error.rcfm-field-error[role="alert"][hidden]'
    assert_select '.rcfm-error[role="alert"][tabindex="-1"][hidden]'
    assert_select '.rcfm-enumeration-utilities details:not([open])', :count => 2
    assert_select 'input.rcfm-csv-file'
    assert_select 'button.rcfm-csv-preview-button'
    assert_select 'script[src*="enumeration_manager"]'
    assert_operator response.body.index('class="list rcfm-enumerations rcfm-sortable"'), :<,
                    response.body.index('class="rcfm-single-add"')
    assert_operator response.body.index('class="rcfm-single-add"'), :<,
                    response.body.index('class="rcfm-toolbar rcfm-enumeration-selection-tools"')
    assert_operator response.body.index('class="rcfm-toolbar rcfm-enumeration-selection-tools"'), :<,
                    response.body.index('class="rcfm-enumeration-utilities"')
  end
end
