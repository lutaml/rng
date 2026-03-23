# frozen_string_literal: true

module Rng
  # Container for namespace and datatype declarations in RNC schema
  #
  # Provides structured access to schema metadata that appears at the top
  # of RNC files before the grammar content.
  #
  # @example Building a preamble
  #   preamble = SchemaPreamble.new
  #   preamble.add_namespace(
  #     NamespaceDeclaration.new(uri: "http://example.com", is_default: true)
  #   )
  #   preamble.add_datatype(
  #     DatatypeDeclaration.new(prefix: "xsd", uri: "http://www.w3.org/2001/XMLSchema-datatypes")
  #   )
  #
  class SchemaPreamble
    attr_reader :namespaces, :datatypes

    # Initialize an empty preamble
    def initialize
      @namespaces = []
      @datatypes = []
    end

    # Add a namespace declaration
    #
    # @param declaration [NamespaceDeclaration] Namespace declaration to add
    def add_namespace(declaration)
      @namespaces << declaration
    end

    # Add a datatype declaration
    #
    # @param declaration [DatatypeDeclaration] Datatype declaration to add
    def add_datatype(declaration)
      @datatypes << declaration
    end

    # Get the default namespace URI
    #
    # @return [String, nil] Default namespace URI or nil if none
    def default_namespace
      @namespaces.find(&:default?)&.uri
    end

    # Get a map of namespace prefixes to URIs
    #
    # @return [Hash<String, String>] Map of prefix => URI
    def namespace_map
      @namespaces.select(&:prefixed?).each_with_object({}) do |ns, map|
        map[ns.prefix] = ns.uri
      end
    end

    # Get a map of datatype prefixes to URIs
    #
    # @return [Hash<String, String>] Map of prefix => URI
    def datatype_map
      @datatypes.each_with_object({}) do |dt, map|
        map[dt.prefix] = dt.uri
      end
    end

    # Check if preamble is empty
    #
    # @return [Boolean]
    def empty?
      @namespaces.empty? && @datatypes.empty?
    end
  end
end
