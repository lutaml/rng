# frozen_string_literal: true

module Rng
  module Namespaces
    class RngNamespace < Lutaml::Xml::Namespace
      uri "http://relaxng.org/ns/structure/1.0"
      prefix_default "rng"
    end

    class AnnotationNamespace < Lutaml::Xml::Namespace
      uri "http://relaxng.org/ns/compatibility/annotations/1.0"
      prefix_default "a"
    end
  end
end
