require "lutaml/model"

module Rng
  class Element < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :ns, :string
    attribute :datatypeLibrary, :string
    attribute :id, :string
    attribute :attribute, Attribute
    attribute :ref, Ref
    attribute :choice, Choice
    attribute :group, Group
    attribute :interleave, Interleave
    attribute :mixed, Mixed
    attribute :optional, Optional
    attribute :zeroOrMore, ZeroOrMore
    attribute :oneOrMore, OneOrMore
    attribute :text, Text
    attribute :empty, Empty
    attribute :value, Value
    attribute :data, Data
    attribute :list, List
    attribute :notAllowed, NotAllowed
    attribute :element, Element

    xml do
      map_attribute "name", to: :name
      map_attribute "ns", to: :ns
      map_attribute "datatypeLibrary", to: :datatypeLibrary
      map_attribute "id", to: :id
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
      map_element "list", to: :list
      map_element "notAllowed", to: :notAllowed
      map_element "element", to: :element
    end
  end
end
