# frozen_string_literal: true

require "lutaml/model"

module Rng
  class Attribute < Lutaml::Model::Serializable
    attribute :name, Name
    attribute :attr_name, :string
    attribute :ns, :string
    attribute :datatypeLibrary, :string
    attribute :id, :string
    attribute :ns_name, NsName
    attribute :ref, Ref
    attribute :choice, Choice
    attribute :group, Group
    attribute :interleave, Interleave
    attribute :mixed, Mixed
    attribute :optional, Optional
    attribute :zeroOrMore, ZeroOrMore
    attribute :oneOrMore, OneOrMore
    attribute :anyName, AnyName
    attribute :text, Text
    attribute :empty, Empty
    attribute :value, Value
    attribute :data, Data
    attribute :list, List
    attribute :notAllowed, NotAllowed
    attribute :attribute, Attribute

    xml do
      root "attribute", ordered: true
      namespace "http://relaxng.org/ns/structure/1.0"

      map_element "name", to: :name
      map_attribute "name", to: :attr_name
      map_attribute "ns", to: :ns, value_map: {
        from: { empty: :empty, omitted: :omitted, nil: :nil },
        to: { empty: :empty, omitted: :omitted, nil: :nil }
      }
      map_attribute "datatypeLibrary", to: :datatypeLibrary, value_map: {
        from: { empty: :empty, omitted: :omitted, nil: :nil },
        to: { empty: :empty, omitted: :omitted, nil: :nil }
      }
      map_attribute "id", to: :id
      map_element "ref", to: :ref
      map_element "choice", to: :choice
      map_element "group", to: :group
      map_element "interleave", to: :interleave
      map_element "mixed", to: :mixed
      map_element "optional", to: :optional
      map_element "zeroOrMore", to: :zeroOrMore
      map_element "oneOrMore", to: :oneOrMore
      map_element "anyName", to: :anyName
      map_element "text", to: :text, value_map: {
        from: { empty: :empty, omitted: :omitted, nil: :nil },
        to: { empty: :empty, omitted: :omitted, nil: :nil }
      }
      map_element "empty", to: :empty
      map_element "value", to: :value
      map_element "data", to: :data
      map_element "list", to: :list
      map_element "notAllowed", to: :notAllowed
      map_element "attribute", to: :attribute
      map_element "nsName", to: :ns_name
    end
  end
end
