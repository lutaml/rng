require "lutaml/model"
require_relative "element"

module Rng
  class Start < Lutaml::Model::Serializable
    attribute :ref, :string
    attribute :elements, Element, collection: true

    xml do
      map_attribute "ref", to: :ref
      map_element "element", to: :elements
    end
  end
end
