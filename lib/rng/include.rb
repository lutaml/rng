# frozen_string_literal: true

module Rng
  class Include < Lutaml::Model::Serializable
    attribute :href, :string
    attribute :ns, :string
    attribute :define, Define
    attribute :grammar, Grammar

    xml do
      element 'include'
      namespace ::Rng::Namespaces::RngNamespace

      map_attribute 'href', to: :href
      map_attribute 'ns', to: :ns, value_map: {
        from: { empty: :empty, omitted: :omitted, nil: :nil },
        to: { empty: :empty, omitted: :omitted, nil: :nil }
      }
      map_content to: :grammar
      map_element 'define', to: :define
    end
  end
end
