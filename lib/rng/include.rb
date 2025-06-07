# frozen_string_literal: true

require "lutaml/model"

module Rng
  class Include < Lutaml::Model::Serializable
    attribute :href, :string
    attribute :ns, :string
    attribute :grammar, Grammar

    xml do
      root "include"

      map_attribute "href", to: :href
      map_attribute "ns", to: :ns, value_map: {
        from: { empty: :empty, omitted: :omitted, nil: :nil },
        to: { empty: :empty, omitted: :omitted, nil: :nil }
      }
      map_content to: :grammar
    end
  end
end
