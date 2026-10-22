# frozen_string_literal: true

require_relative '../test_helper'

class Rcfm::HistoriesControllerTest < Redmine::ControllerTest
  fixtures :users

  def setup
    @request.session[:user_id] = 1
    Setting.plugin_redmine_custom_field_manager = {'retention_days' => '', 'max_generations' => ''}
    field = GroupCustomField.create!(:name => 'RCFM history controller', :field_format => 'enumeration')
    value = field.enumerations.create!(:name => 'Before')
    RedmineCustomFieldManager::EnumerationUpdater.new(
      :custom_field => field,
      :items => [{
        'client_id' => value.id.to_s,
        'id' => value.id,
        'name' => 'After',
        'active' => true,
        'deleted' => false
      }],
      :base_digest => RedmineCustomFieldManager::Snapshot.enumerations_digest(field),
      :user => User.find(1)
    ).call
    @history = RedmineCustomFieldManager::History.last
  end

  def test_index_loads_only_history_metadata
    get :index

    assert_response :success
    assert_select '.rcfm-history-list'
    assert_select "a[href='#{rcfm_history_path(@history)}']"
    assert_select '.rcfm-history-list', :text => /RCFM history controller/
    assert_select '.rcfm-history-list', :text => /List update/
  end

  def test_index_paginates_history_metadata
    template = @history.attributes.except('id', 'created_at')
    30.times do |index|
      RedmineCustomFieldManager::History.create!(template.merge(:created_at => (index + 1).minutes.ago))
    end

    get :index

    assert_response :success
    histories = @controller.instance_variable_get(:@histories)
    pages = @controller.instance_variable_get(:@history_pages)
    assert_operator histories.length, :<=, pages.per_page
    assert_select '.pagination'
  end

  def test_show_loads_reconstructed_details_on_demand
    get :show, :params => {:id => @history.id}

    assert_response :success
    assert_select '.rcfm-json-detail', :count => 2
    assert_select '.rcfm-history-changes tbody tr', :minimum => 1
    assert_select '.rcfm-history-state tbody tr', :minimum => 1
    assert_select 'details.rcfm-history-state-section:not([open])', :count => 1
    assert_select '.rcfm-history-technical'
  end

  def test_show_collapses_a_large_change_list_with_its_count
    changes = 21.times.map do |index|
      {
        'id' => index + 1,
        'action' => 'update',
        'before' => {'id' => index + 1, 'name' => "Before #{index}", 'position' => index + 1},
        'after' => {'id' => index + 1, 'name' => "After #{index}", 'position' => index + 1}
      }
    end
    @history.update_columns(:changes_json => {'diff' => changes}.to_json)

    get :show, :params => {:id => @history.id}

    assert_response :success
    assert_select 'details.rcfm-history-changes-section:not([open]) > summary', :text => /21/
    assert_select '.rcfm-history-changes tbody tr', :count => 21
  end

  def test_restore_preview_is_rendered_before_apply
    CustomField.find(@history.target_id).enumerations.first.update!(:active => false)

    post :restore_preview, :params => {:id => @history.id}

    assert_response :success
    assert_select "form[action='#{rcfm_restore_history_path(@history)}']"
    assert_select 'input[name="plan_digest"]'
    assert_select 'table.list', :text => /Active/
  end

  def test_custom_field_deletion_history_is_shown_as_non_restorable_audit
    field = IssueCustomField.create!(:name => 'RCFM deleted audit', :field_format => 'string')
    field.destroy!
    history = RedmineCustomFieldManager::History.last

    get :show, :params => {:id => history.id}

    assert_response :success
    assert_select '.rcfm-history-audit-only', :text => /cannot be restored/
    assert_select '.rcfm-history-changes', :text => /RCFM deleted audit/
    assert_select "form[action='#{rcfm_preview_history_restore_path(history)}']", :count => 0
    assert_select '.box.tabular', :text => /Custom field deletion/
  end

  def test_history_actions_require_an_administrator
    @request.session[:user_id] = 2

    get :index

    assert_response :forbidden
  end

  def test_destroy_does_not_change_current_values
    current = @history.reconstructed_snapshot

    delete :destroy, :params => {:history_ids => [@history.id]}

    assert_redirected_to rcfm_histories_path
    assert_not RedmineCustomFieldManager::History.exists?(@history.id)
    field = CustomField.find(@history.target_id)
    assert_equal current, RedmineCustomFieldManager::Snapshot.enumerations(field)
  end
end
