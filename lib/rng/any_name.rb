# frozen_string_literal: true

module Rng
  class AnyName < Lutaml::Model::Serializable
    attribute :name, :string
    attribute :id, :string
    attribute :ns, :string
    attribute :datatypeLibrary, :string
    attribute :except, Except

    xml do
      element "anyName"
      ordered

      map_attribute "name", to: :name
      map_attribute "id", to: :id
      map_attribute "ns", to: :ns, value_map: {
        from: { empty: :empty, omitted: :omitted, nil: :nil },
        to: { empty: :empty, omitted: :omitted, nil: :nil },
      }
      map_attribute "datatypeLibrary", to: :datatypeLibrary

      map_element "except", to: :except
    end
  end
end
