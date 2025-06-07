# frozen_string_literal: true

require "lutaml/model"

module Rng
  # This represents the RNG schema
  class Grammar < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :ns, :string
    attribute :datatypeLibrary, :string
    attribute :start, Start
    attribute :define, Define, collection: true, initialize_empty: true
    attribute :element, Element, collection: true
    attribute :include, Include, collection: true

    xml do
      root "grammar", ordered: true
      namespace "http://relaxng.org/ns/structure/1.0"

      map_attribute "datatypeLibrary", to: :datatypeLibrary, value_map: {
        from: { empty: :empty, omitted: :omitted, nil: :nil },
        to: { empty: :empty, omitted: :omitted, nil: :nil }
      }
      map_attribute "ns", to: :ns, value_map: {
        from: { empty: :empty, omitted: :omitted, nil: :nil },
        to: { empty: :empty, omitted: :omitted, nil: :nil }
      }
      map_attribute "id", to: :id

      map_element "start", to: :start
      map_element "define", to: :define
      map_element "element", to: :element
      map_element "include", to: :include
    end
  end
end
