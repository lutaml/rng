# frozen_string_literal: true

require "lutaml/model"

module Rng
  class List < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :ns, :string
    attribute :datatypeLibrary, :string
    attribute :element, Element, collection: true, initialize_empty: true
    attribute :attribute, Attribute, collection: true, initialize_empty: true
    attribute :ref, Ref, collection: true, initialize_empty: true
    attribute :choice, Choice, collection: true, initialize_empty: true
    attribute :group, Group, collection: true, initialize_empty: true
    attribute :interleave, Interleave, collection: true, initialize_empty: true
    attribute :mixed, Mixed, collection: true, initialize_empty: true
    attribute :optional, Optional, collection: true, initialize_empty: true
    attribute :zeroOrMore, ZeroOrMore, collection: true, initialize_empty: true
    attribute :oneOrMore, OneOrMore, collection: true, initialize_empty: true
    attribute :text, Text, collection: true, initialize_empty: true
    attribute :empty, Empty, collection: true, initialize_empty: true
    attribute :value, Value, collection: true, initialize_empty: true
    attribute :data, Data, collection: true, initialize_empty: true
    attribute :notAllowed, NotAllowed, collection: true, initialize_empty: true

    xml do
      root "list", ordered: true
      namespace "http://relaxng.org/ns/structure/1.0"

      map_attribute "id", to: :id
      map_attribute "ns", to: :ns, value_map: {
        from: { empty: :empty, omitted: :omitted, nil: :nil },
        to: { empty: :empty, omitted: :omitted, nil: :nil }
      }
      map_attribute "datatypeLibrary", to: :datatypeLibrary, value_map: {
        from: { empty: :empty, omitted: :omitted, nil: :nil },
        to: { empty: :empty, omitted: :omitted, nil: :nil }
      }
      map_element "element", to: :element
      map_element "attribute", to: :attribute
      map_element "ref", to: :ref
      map_element "choice", to: :choice
      map_element "group", to: :group
      map_element "interleave", to: :interleave
      map_element "mixed", to: :mixed
      map_element "optional", to: :optional
      map_element "zeroOrMore", to: :zeroOrMore
      map_element "oneOrMore", to: :oneOrMore
      map_element "text", to: :text
      map_element "empty", to: :empty
      map_element "value", to: :value
      map_element "data", to: :data
      map_element "notAllowed", to: :notAllowed
    end
  end
end
