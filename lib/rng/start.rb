require "lutaml/model"

module Rng
  class Start < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :ns, :string
    attribute :datatypeLibrary, :string
    attribute :combine, :string
    attribute :ref, Ref
    attribute :element, Element
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
    attribute :grammar, Grammar

    xml do
      root "start", ordered: true

      map_attribute "id", to: :id
      map_attribute "ns", to: :ns
      map_attribute "datatypeLibrary", to: :datatypeLibrary
      map_attribute "combine", to: :combine

      map_element "ref", to: :ref
      map_element "element", to: :element
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
      map_element "grammar", to: :grammar
    end
  end
end
