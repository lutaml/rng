# frozen_string_literal: true

module Rng
  # Div element for documentation and grouping in RELAX NG schemas
  class Div < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :ns, :string
    attribute :datatypeLibrary, :string
    attribute :start, Start, collection: true, initialize_empty: true
    attribute :define, Define, collection: true, initialize_empty: true
    attribute :div, Div, collection: true, initialize_empty: true
    attribute :include, Include, collection: true, initialize_empty: true
    attribute :foreign_attributes, ForeignAttribute, collection: true
    attribute :foreign_elements, ForeignElement, collection: true

    xml do
      element "div"
      ordered

      namespace ::Rng::Namespaces::RngNamespace

      map_attribute "id", to: :id
      map_attribute "ns", to: :ns, value_map: {
        from: { empty: :empty, omitted: :omitted, nil: :nil },
        to: { empty: :empty, omitted: :omitted, nil: :nil },
      }
      map_attribute "datatypeLibrary", to: :datatypeLibrary, value_map: {
        from: { empty: :empty, omitted: :omitted, nil: :nil },
        to: { empty: :empty, omitted: :omitted, nil: :nil },
      }

      map_element "start", to: :start
      map_element "define", to: :define
      map_element "div", to: :div
      map_element "include", to: :include
    end
  end
end
