# frozen_string_literal: true

module RedmineCustomFieldManager
  module BulkUpdater
    BATCH_SIZE = 500

    module_function

    def update_attribute(relation, attribute, values_by_id)
      return if values_by_id.empty?

      model = relation.model
      connection = model.connection
      id_column = connection.quote_column_name(model.primary_key)
      attribute_column = connection.quote_column_name(attribute)
      values_by_id.to_a.each_slice(BATCH_SIZE) do |pairs|
        sql = "#{attribute_column} = CASE #{id_column}"
        pairs.each do |id, value|
          sql << " WHEN #{connection.quote(id)} THEN #{connection.quote(value)}"
        end
        sql << " ELSE #{attribute_column} END"
        relation.where(model.primary_key => pairs.map(&:first)).update_all(Arel.sql(sql))
      end
    end
  end
end
