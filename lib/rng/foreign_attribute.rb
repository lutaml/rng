# frozen_string_literal: true

require "lutaml/model"

module Rng
  # Represents a foreign attribute (from a non-RELAX NG namespace)
  # Used in annotation blocks like [eg:foo = "value"]
  class ForeignAttribute < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :namespace, :string
    attribute :value, :string

    xml do
      root "attribute"
      namespace "http://relaxng.org/ns/structure/1.0"

      map_attribute "name", to: :name
      map_attribute "namespace", to: :namespace
      map_content to: :value
    end

    def initialize(name: nil, namespace: nil, value: nil)
      @name = name
      @namespace = namespace
      @value = value
    end
  end
end
