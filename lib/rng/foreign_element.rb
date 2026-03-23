# frozen_string_literal: true

require "lutaml/model"

module Rng
  # Represents a foreign element (from a non-RELAX NG namespace)
  # Used in annotation blocks like [eg:foo [ "content" ]]
  class ForeignElement < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :namespace, :string
    attribute :content, :string
    attribute :attributes, ForeignAttribute, collection: true
    attribute :elements, ForeignElement, collection: true

    xml do
      root "element"
      namespace "http://relaxng.org/ns/structure/1.0"

      map_attribute "name", to: :name
      map_attribute "namespace", to: :namespace
      map_content to: :content
      map_element "attribute", to: :attributes
      map_element "element", to: :elements
    end

    def initialize(name: nil, namespace: nil, content: nil,
                   attributes: [], elements: [])
      @name = name
      @namespace = namespace
      @content = content
      @attributes = attributes
      @elements = elements
    end
  end
end
