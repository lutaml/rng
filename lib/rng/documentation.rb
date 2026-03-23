# frozen_string_literal: true

module Rng
  class Documentation < Lutaml::Model::Type::String
    xml do
      namespace ::Rng::Namespaces::AnnotationNamespace
    end
  end
end
