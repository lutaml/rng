require "lutaml/model"
require_relative "start"
require_relative "define"

module Rng
  class Schema < Lutaml::Model::Serializable
    attribute :start, Start
    attribute :define, Define, collection: true

    xml do
      root "grammar"
      namespace "http://relaxng.org/ns/structure/1.0"

      map_element "start", to: :start
      map_element "define", to: :define
    end
  end
end
