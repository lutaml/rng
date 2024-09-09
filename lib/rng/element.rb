require "lutaml/model"
require_relative "attribute"

module Rng
  class Element < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :attributes, Attribute, collection: true
    attribute :elements, Element, collection: true
    attribute :text, :boolean
    attribute :zero_or_more, Element, collection: true
    attribute :one_or_more, Element, collection: true
    attribute :optional, Element, collection: true
    attribute :choice, Element, collection: true

    xml do
      map_attribute "name", to: :name
      map_element "attribute", to: :attributes
      map_element "element", to: :elements
      map_element "text", to: :text
      map_element "zeroOrMore", to: :zero_or_more
      map_element "oneOrMore", to: :one_or_more
      map_element "optional", to: :optional
      map_element "choice", to: :choice
    end
  end
end
