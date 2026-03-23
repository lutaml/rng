# frozen_string_literal: true

module Rng
  class Data < Lutaml::Model::Serializable
    attribute :id, :string
    attribute :ns, :string
    attribute :datatypeLibrary, :string
    attribute :type, :string
    attribute :param, Param, collection: true, initialize_empty: true
    attribute :except, Except

    xml do
      element "data"
      ordered

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
      map_attribute "type", to: :type
      map_element "param", to: :param
      map_element "except", to: :except
    end
  end
end
