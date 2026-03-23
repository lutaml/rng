# frozen_string_literal: true

module Rng
  class ExternalRef < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :ns, :string
    attribute :datatypeLibrary, :string
    attribute :href, :string

    xml do
      root "externalRef"
      namespace ::Rng::Namespaces::RngNamespace

      map_attribute "id", to: :id
      map_attribute "ns", to: :ns, value_map: {
        from: { empty: :empty, omitted: :omitted, nil: :nil },
        to: { empty: :empty, omitted: :omitted, nil: :nil },
      }
      map_attribute "datatypeLibrary", to: :datatypeLibrary, value_map: {
        from: { empty: :empty, omitted: :omitted, nil: :nil },
        to: { empty: :empty, omitted: :omitted, nil: :nil },
      }
      map_attribute "href", to: :href
    end
  end
end
