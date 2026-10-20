# frozen_string_literal: true

name = 'RCFM performance 10000'
field = GroupCustomField.find_by(:name => name)
field&.destroy
field = GroupCustomField.create!(:name => name, :field_format => 'enumeration')

rows = Array.new(10_000) do |index|
  {
    :custom_field_id => field.id,
    :name => format('Performance value %05d', index + 1),
    :active => true,
    :position => index + 1
  }
end
CustomFieldEnumeration.insert_all!(rows)
puts field.id
