# frozen_string_literal: true

require_relative 'lib/redmine_custom_field_manager'

Redmine::Plugin.register :redmine_custom_field_manager do
  name 'Redmine Custom Field Manager'
  author 'Narusawa'
  description 'Improves custom field and key/value list management.'
  version RedmineCustomFieldManager::VERSION
  url 'https://github.com/nrswnrsw/redmine_custom_field_manager'

  requires_redmine :version_or_higher => '6.0.0'

  settings :default => {
    'retention_days' => '',
    'max_generations' => ''
  }, :partial => 'settings/redmine_custom_field_manager'
end

RedmineCustomFieldManager::ModelTracking.install!
SettingsController.include(RedmineCustomFieldManager::SettingsControllerPatch) unless
  SettingsController < RedmineCustomFieldManager::SettingsControllerPatch
