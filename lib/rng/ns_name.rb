require "lutaml/model"

module Rng
  class NsName < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :ns, :string
    attribute :datatypeLibrary, :string
    attribute :name, :string
    attribute :except, Except

    xml do
      map_attribute "id", to: :id
      map_attribute "ns", to: :ns
      map_attribute "datatypeLibrary", to: :datatypeLibrary
      map_attribute "name", to: :name

      map_element "except", to: :except
    end
  end
end
