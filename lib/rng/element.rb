require "lutaml/model"

module Rng
  class Element < Lutaml::Model::Serializable
    attribute :attr_name, :string
    attribute :name, :string
    attribute :ns, :string
    attribute :ns_name, NsName
    attribute :datatypeLibrary, :string
    attribute :id, :string
    attribute :attribute, Attribute
    attribute :ref, Ref, collection: true
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
    attribute :element, Element, collection: true
    attribute :grammar, Grammar
    attribute :parent_ref, ParentRef

    xml do
      root "element", ordered: true
      namespace "http://relaxng.org/ns/structure/1.0"

      map_attribute "name", to: :attr_name
      map_attribute "ns", to: :ns
      map_attribute "datatypeLibrary", to: :datatypeLibrary
      map_attribute "id", to: :id
      map_element "name", to: :name
      map_element "nsName", to: :ns_name
      map_element "attribute", to: :attribute
      map_element "ref", to: :ref
      map_element "choice", to: :choice
      map_element "group", to: :group
      map_element "interleave", to: :interleave
      map_element "mixed", to: :mixed
      map_element "optional", to: :optional
      map_element "zeroOrMore", to: :zeroOrMore
      map_element "oneOrMore", to: :oneOrMore
      map_element "anyName", to: :anyName
      map_element "text", to: :text
      map_element "empty", to: :empty
      map_element "value", to: :value
      map_element "data", to: :data
      map_element "list", to: :list
      map_element "notAllowed", to: :notAllowed
      map_element "element", to: :element
      map_element "mixed", to: :mixed
      map_element "grammar", to: :grammar
      map_element "parentRef", to: :parent_ref
    end
  end
end
