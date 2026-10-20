# frozen_string_literal: true

require_relative '../test_helper'

class Rcfm::CustomFieldsControllerTest < Redmine::ControllerTest
  fixtures :users

  def setup
    @request.session[:user_id] = 1
    @first = IssueCustomField.create!(:name => 'RCFM controller first', :field_format => 'string')
    @second = IssueCustomField.create!(:name => 'RCFM controller second', :field_format => 'string')
  end

  def test_update_order_requires_an_administrator
    @request.session[:user_id] = 2

    put :update_order, :params => valid_params

    assert_response :forbidden
  end

  def test_update_order_returns_json
    put :update_order, :params => valid_params

    assert_response :success
    assert_equal true, response.parsed_body['ok']
  end

  def test_update_order_reports_conflict
    params = valid_params
    @first.update!(:name => 'Changed after opening')

    put :update_order, :params => params

    assert_response :conflict
    assert_equal 'conflict', response.parsed_body['error']
    assert_not_nil response.parsed_body['merge_proposal']
  end

  private

  def valid_params
    snapshot = RedmineCustomFieldManager::Snapshot.custom_fields(:field_type => 'IssueCustomField')
    {
      :field_type => 'IssueCustomField',
      :ordered_ids => CustomField.where(:type => 'IssueCustomField').order(:position, :id).pluck(:id).reverse,
      :base_digest => RedmineCustomFieldManager::Snapshot.digest(snapshot),
      :base_snapshot => snapshot
    }
  end
end
