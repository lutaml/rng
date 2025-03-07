require "lutaml/model"

module Rng
  # This represents the RNG schema
  class Schema < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :ns, :string
    attribute :datatypeLibrary, :string
    attribute :start, Start
    attribute :define, Define, collection: true, initialize_empty: true
    attribute :element, Element, collection: true

    xml do
      root "grammar", ordered: true
      namespace "http://relaxng.org/ns/structure/1.0"

      map_element "start", to: :start
      map_element "define", to: :define
      map_element "element", to: :element
      map_attribute "ns", to: :ns
      map_attribute "datatypeLibrary", to: :datatypeLibrary
      map_attribute "id", to: :id
    end
  end
end
