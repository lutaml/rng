# frozen_string_literal: true

module Rng
  # Represents a datatype library declaration in RNC
  #
  # Example: datatypes xsd = "http://www.w3.org/2001/XMLSchema-datatypes"
  #
  # @example Creating a datatype declaration
  #   decl = DatatypeDeclaration.new(
  #     prefix: "xsd",
  #     uri: "http://www.w3.org/2001/XMLSchema-datatypes"
  #   )
  #
  class DatatypeDeclaration
    attr_reader :prefix, :uri

    # Initialize a datatype library declaration
    #
    # @param prefix [String] Datatype library prefix
    # @param uri [String] Datatype library URI
    def initialize(prefix:, uri:)
      @prefix = prefix
      @uri = uri
    end
  end
end
