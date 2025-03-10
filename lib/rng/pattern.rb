require "lutaml/model"

module Rng
  # Base class for all pattern elements
  class Pattern < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :ns, :string
    attribute :datatypeLibrary, :string

    xml do
      map_attribute "id", to: :id
      map_attribute "ns", to: :ns
      map_attribute "datatypeLibrary", to: :datatypeLibrary
    end
  end
end
