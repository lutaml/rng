require "lutaml/model"

module Rng
  class Value < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :ns, :string
    attribute :datatypeLibrary, :string
    attribute :type, :string
    attribute :value, :string

    xml do
      map_attribute "type", to: :type
      map_attribute "id", to: :id
      map_attribute "ns", to: :ns
      map_attribute "datatypeLibrary", to: :datatypeLibrary
      map_content to: :value
    end
  end
end
