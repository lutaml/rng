# frozen_string_literal: true

module Rng
  class Value < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :ns, :string
    attribute :datatypeLibrary, :string
    attribute :type, :string
    attribute :value, :string

    xml do
      element "value"
      namespace ::Rng::Namespaces::RngNamespace

      map_attribute "type", to: :type
      map_attribute "id", to: :id
      map_attribute "ns", to: :ns, value_map: {
        from: { empty: :empty, omitted: :omitted, nil: :nil },
        to: { empty: :empty, omitted: :omitted, nil: :nil },
      }
      map_attribute "datatypeLibrary", to: :datatypeLibrary, value_map: {
        from: { empty: :empty, omitted: :omitted, nil: :nil },
        to: { empty: :empty, omitted: :omitted, nil: :nil },
      }
      map_content to: :value
    end
  end
end
