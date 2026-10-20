# frozen_string_literal: true

require_relative '../test_helper'
require 'csv'

class Rcfm::EnumerationsControllerTest < Redmine::ControllerTest
  fixtures :users

  def setup
    @request.session[:user_id] = 1
    @field = GroupCustomField.create!(:name => 'RCFM controller list', :field_format => 'enumeration')
    @first = @field.enumerations.create!(:name => 'First')
    @second = @field.enumerations.create!(:name => 'Second')
  end

  def test_update_returns_json_and_preserves_ids
    put :update, :params => valid_params

    assert_response :success
    assert_equal true, response.parsed_body['ok']
    assert_equal [@second.id, @first.id], @field.reload.enumerations.reorder(:position, :id).pluck(:id)
  end

  def test_update_requires_an_administrator
    @request.session[:user_id] = 2

    put :update, :params => valid_params

    assert_response :forbidden
  end

  def test_update_returns_conflict_without_writing
    params = valid_params
    @first.update!(:name => 'Changed elsewhere')

    put :update, :params => params

    assert_response :conflict
    assert_equal 'conflict', response.parsed_body['error']
    assert_equal 'Changed elsewhere', @first.reload.name
  end

  def test_update_returns_and_applies_an_explicit_safe_merge
    base_snapshot = RedmineCustomFieldManager::Snapshot.enumerations(@field)
    base_digest = RedmineCustomFieldManager::Snapshot.digest(base_snapshot)
    mine = [@first, @second].map do |record|
      {
        :client_id => record.id.to_s,
        :id => record.id,
        :name => record == @first ? 'Mine' : record.name,
        :active => record.active?,
        :deleted => false
      }
    end
    @second.update!(:active => false)

    put :update, :params => {
      :custom_field_id => @field.id,
      :base_digest => base_digest,
      :base_snapshot => base_snapshot,
      :items => mine
    }

    assert_response :conflict
    proposal = response.parsed_body.fetch('merge_proposal')
    assert_not_nil proposal
    current_digest = response.parsed_body.fetch('current_digest')

    put :update, :params => {
      :custom_field_id => @field.id,
      :base_digest => base_digest,
      :base_snapshot => base_snapshot,
      :items => proposal,
      :force => '1',
      :resolution => 'merge',
      :confirmed_digest => current_digest
    }

    assert_response :success
    assert_equal 'Mine', @first.reload.name
    assert_not @second.reload.active?
    assert_equal 'merge', RedmineCustomFieldManager::History.last.operation
  end

  def test_export_returns_a_reimportable_csv
    get :export, :params => {:custom_field_id => @field.id}

    assert_response :success
    assert_includes response.media_type, 'text/csv'
    parsed = RedmineCustomFieldManager::CsvParser.new(response.body).parse
    assert_equal [@first.id.to_s, @second.id.to_s], parsed.rows.map(&:source_id)
  end

  def test_import_preview_returns_differences_without_writing
    post :import_preview, :params => {
      :custom_field_id => @field.id,
      :csv_data => csv_data('Renamed'),
      :mode => 'update'
    }

    assert_response :success
    assert response.parsed_body.dig('plan', 'resolved')
    assert_equal ['rename'], response.parsed_body.dig('plan', 'diffs').pluck('action')
    assert_equal 'First', @first.reload.name
  end

  def test_import_applies_the_exact_preview
    csv = csv_data('Renamed')
    post :import_preview, :params => {
      :custom_field_id => @field.id,
      :csv_data => csv,
      :mode => 'update'
    }
    preview = response.parsed_body

    post :import, :params => {
      :custom_field_id => @field.id,
      :csv_data => csv,
      :mode => 'update',
      :base_digest => preview.fetch('base_digest'),
      :plan_digest => preview.dig('plan', 'digest')
    }

    assert_response :success
    assert_equal 'Renamed', @first.reload.name
    assert_equal @first.id, @field.reload.enumerations.reorder(:position, :id).first.id
  end

  def test_csv_actions_require_an_administrator
    @request.session[:user_id] = 2

    get :export, :params => {:custom_field_id => @field.id}
    assert_response :forbidden

    post :import_preview, :params => {
      :custom_field_id => @field.id,
      :csv_data => csv_data('Renamed'),
      :mode => 'update'
    }
    assert_response :forbidden
  end

  private

  def valid_params
    {
      :custom_field_id => @field.id,
      :base_digest => RedmineCustomFieldManager::Snapshot.enumerations_digest(@field),
      :items => [@second, @first].map do |record|
        {
          :client_id => record.id.to_s,
          :id => record.id,
          :name => record.name,
          :active => record.active?,
          :deleted => false
        }
      end
    }
  end

  def csv_data(first_name)
    instance_id = RedmineCustomFieldManager::InstanceIdentity.value
    CSV.generate do |csv|
      csv << RedmineCustomFieldManager::CsvExporter::HEADERS
      csv << ['metadata', '1', instance_id, @field.id, @field.type, @field.name, '0', nil, nil, '0', nil, nil]
      csv << ['enumeration', '1', instance_id, @field.id, @field.type, @field.name, '0', @first.id, first_name, '0', '1', 1]
      csv << ['enumeration', '1', instance_id, @field.id, @field.type, @field.name, '0', @second.id, @second.name, '0', '1', 2]
    end
  end
end
