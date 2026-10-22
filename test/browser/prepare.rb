# frozen_string_literal: true

field_names = ['RCFM browser enumeration', 'RCFM browser target']
CustomField.where(:name => field_names).find_each(&:destroy)

field = GroupCustomField.create!(
  :name => field_names.first,
  :field_format => 'enumeration',
  :is_required => false
)
%w[Browser\ value\ A Browser\ value\ B Browser\ value\ C].each_with_index do |name, index|
  field.enumerations.create!(:name => name, :position => index + 1, :active => true)
end
GroupCustomField.create!(
  :name => field_names.last,
  :field_format => 'string',
  :is_required => false
)

puts field.id
