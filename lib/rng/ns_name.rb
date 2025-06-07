# frozen_string_literal: true

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
      map_attribute "ns", to: :ns, value_map: {
        from: { empty: :empty, omitted: :omitted, nil: :nil },
        to: { empty: :empty, omitted: :omitted, nil: :nil }
      }
      map_attribute "datatypeLibrary", to: :datatypeLibrary, value_map: {
        from: { empty: :empty, omitted: :omitted, nil: :nil },
        to: { empty: :empty, omitted: :omitted, nil: :nil }
      }
      map_attribute "name", to: :name

      map_element "except", to: :except
    end
  end
end
