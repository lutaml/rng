# frozen_string_literal: true

module Rng
  # This represents the RNG schema
  class Grammar < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :ns, :string
    attribute :datatypeLibrary, :string
    attribute :start, Start, collection: true
    attribute :define, Define, collection: true, initialize_empty: true
    attribute :element, Element, collection: true, initialize_empty: true
    attribute :include, Include, collection: true
    attribute :div, Div, collection: true, initialize_empty: true

    xml do
      element "grammar"
      ordered

      namespace ::Rng::Namespaces::RngNamespace

      map_attribute "datatypeLibrary", to: :datatypeLibrary, value_map: {
        from: { empty: :empty, omitted: :omitted, nil: :nil },
        to: { empty: :empty, omitted: :omitted, nil: :nil },
      }
      map_attribute "ns", to: :ns, value_map: {
        from: { empty: :empty, omitted: :omitted, nil: :nil },
        to: { empty: :empty, omitted: :omitted, nil: :nil },
      }
      map_attribute "id", to: :id

      map_element "start", to: :start
      map_element "define", to: :define
      map_element "element", to: :element
      map_element "include", to: :include
      map_element "div", to: :div
    end
  end
end
