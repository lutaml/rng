require "lutaml/model"

module Rng
  class Attribute < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :type, :string, collection: true

    xml do
      map_attribute "name", to: :name
      map_element "data", to: :type
    end
  end
end
