require "lutaml/model"

module Rng
  class Text < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :ns, :string
    attribute :datatypeLibrary, :string
    attribute :value, :string, default: ""

    xml do
      map_attribute "id", to: :id
      map_attribute "ns", to: :ns
      map_attribute "datatypeLibrary", to: :datatypeLibrary
      map_content to: :value
    end
  end
end
