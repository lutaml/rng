require "lutaml/model"

module Rng
  class Data < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :ns, :string
    attribute :datatypeLibrary, :string
    attribute :type, :string
    attribute :param, Param, collection: true, initialize_empty: true
    attribute :except, Except

    xml do
      root "data", ordered: true

      map_attribute "id", to: :id
      map_attribute "ns", to: :ns
      map_attribute "datatypeLibrary", to: :datatypeLibrary
      map_attribute "type", to: :type
      map_element "param", to: :param
      map_element "except", to: :except
    end
  end
end
