# frozen_string_literal: true

require "lutaml/model"

module Rng
  class Param < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :ns, :string
    attribute :datatypeLibrary, :string
    attribute :name, :string
    attribute :value, :string

    xml do
      root "param", ordered: true
      namespace "http://relaxng.org/ns/structure/1.0"

      map_attribute "id", to: :id
      map_attribute "ns", to: :ns, value_map: {
        from: { empty: :empty, omitted: :omitted, nil: :nil },
        to: { empty: :empty, omitted: :omitted, nil: :nil }
      }
      map_attribute "datatypeLibrary", to: :datatypeLibrary, value_map: {
        from: { empty: :empty, omitted: :omitted, nil: :nil },
        to: { empty: :empty, omitted: :omitted, nil: :nil }
      }
      map_attribute "name", to: :name
      map_content to: :value
    end
  end
end
