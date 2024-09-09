require "lutaml/model"
require_relative "element"

module Rng
  class Define < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :elements, Element, collection: true

    xml do
      map_attribute "name", to: :name
      map_element "element", to: :elements
    end
  end
end
