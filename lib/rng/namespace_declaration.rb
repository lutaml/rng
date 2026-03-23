# frozen_string_literal: true

module Rng
  # Represents a namespace declaration in RNC
  #
  # Supports both default and prefixed namespace declarations:
  # - default namespace = "uri"
  # - default namespace prefix = "uri"
  # - namespace prefix = "uri"
  #
  # @example Default namespace
  #   decl = NamespaceDeclaration.new(uri: "http://example.com", is_default: true)
  #   decl.default? #=> true
  #
  # @example Prefixed namespace
  #   decl = NamespaceDeclaration.new(prefix: "eg", uri: "http://example.com")
  #   decl.prefixed? #=> true
  #
  class NamespaceDeclaration
    attr_reader :prefix, :uri, :is_default

    # Initialize a namespace declaration
    #
    # @param prefix [String, nil] Namespace prefix (nil for unprefixed default)
    # @param uri [String] Namespace URI
    # @param is_default [Boolean] Whether this is the default namespace
    def initialize(uri:, prefix: nil, is_default: false)
      @prefix = prefix
      @uri = uri
      @is_default = is_default
    end

    # Check if this is the default namespace
    #
    # @return [Boolean]
    def default?
      @is_default
    end

    # Check if this namespace has a prefix
    #
    # @return [Boolean]
    def prefixed?
      !@prefix.nil?
    end
  end
end
