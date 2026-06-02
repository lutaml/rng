# frozen_string_literal: true

require 'lutaml/model'

module Rng
  class Error < StandardError; end

  autoload :Namespaces, File.expand_path('rng/namespaces', __dir__)

  # Autoload all model classes - avoids circular dependency issues
  autoload :Pattern, File.expand_path('rng/pattern', __dir__)
  autoload :Text, File.expand_path('rng/text', __dir__)
  autoload :Empty, File.expand_path('rng/empty', __dir__)
  autoload :Value, File.expand_path('rng/value', __dir__)
  autoload :Param, File.expand_path('rng/param', __dir__)
  autoload :NotAllowed, File.expand_path('rng/not_allowed', __dir__)
  autoload :Name, File.expand_path('rng/name', __dir__)
  autoload :AnyName, File.expand_path('rng/any_name', __dir__)
  autoload :NsName, File.expand_path('rng/ns_name', __dir__)
  autoload :Except, File.expand_path('rng/except', __dir__)
  autoload :Data, File.expand_path('rng/data', __dir__)
  autoload :List, File.expand_path('rng/list', __dir__)
  autoload :Ref, File.expand_path('rng/ref', __dir__)
  autoload :ParentRef, File.expand_path('rng/parent_ref', __dir__)
  autoload :ExternalRef, File.expand_path('rng/external_ref', __dir__)
  autoload :Optional, File.expand_path('rng/optional', __dir__)
  autoload :ZeroOrMore, File.expand_path('rng/zero_or_more', __dir__)
  autoload :OneOrMore, File.expand_path('rng/one_or_more', __dir__)
  autoload :Choice, File.expand_path('rng/choice', __dir__)
  autoload :Group, File.expand_path('rng/group', __dir__)
  autoload :Interleave, File.expand_path('rng/interleave', __dir__)
  autoload :Mixed, File.expand_path('rng/mixed', __dir__)
  autoload :Attribute, File.expand_path('rng/attribute', __dir__)
  autoload :Element, File.expand_path('rng/element', __dir__)
  autoload :Define, File.expand_path('rng/define', __dir__)
  autoload :Start, File.expand_path('rng/start', __dir__)
  autoload :Div, File.expand_path('rng/div', __dir__)
  autoload :Include, File.expand_path('rng/include', __dir__)
  autoload :Grammar, File.expand_path('rng/grammar', __dir__)
  autoload :Documentation, File.expand_path('rng/documentation', __dir__)
  autoload :TestSuiteParser, File.expand_path('rng/test_suite_parser', __dir__)
  autoload :Value, File.expand_path('rng/value', __dir__)

  # Autoload parser support classes
  autoload :ParseTreeProcessor, File.expand_path('rng/parse_tree_processor', __dir__)
  autoload :RncToRngConverter, File.expand_path('rng/rnc_to_rng_converter', __dir__)
  autoload :SchemaPreamble, File.expand_path('rng/schema_preamble', __dir__)
  autoload :NamespaceDeclaration, File.expand_path('rng/namespace_declaration', __dir__)
  autoload :DatatypeDeclaration, File.expand_path('rng/datatype_declaration', __dir__)

  # Schema validation
  autoload :SchemaValidator, File.expand_path('rng/schema_validator', __dir__)
  autoload :SchemaValidationError, File.expand_path('rng/schema_validator', __dir__)

  # External reference resolution
  autoload :ExternalRefResolver, File.expand_path('rng/external_ref_resolver', __dir__)

  # Autoload parsers and builders
  autoload :RncParser, File.expand_path('rng/rnc_parser', __dir__)
  autoload :ParseRnc, File.expand_path('rng/parse_rnc', __dir__)
  autoload :ToRnc, File.expand_path('rng/to_rnc', __dir__)
  autoload :RncBuilder, File.expand_path('rng/rnc_builder', __dir__)
  autoload :IncludeProcessor, File.expand_path('rng/include_processor', __dir__)

  module_function

  def parse(rng, location: nil, nested_schema: false, validate: false, resolve_external: false)
    SchemaValidator.validate(rng) if validate && !nested_schema
    grammar = Grammar.from_xml(rng)
    return grammar unless resolve_external

    ExternalRefResolver.new(grammar, location: location).resolve
  end

  def self.parse_rnc(rnc, location: nil)
    return RncParser.parse(rnc) unless location

    IncludeProcessor.new.parse_content(rnc, location: location)
  end

  def self.parse_file(file_path)
    RncParser.parse_file(file_path)
  end

  def self.to_rnc(schema)
    # Convert RNG schema to RNC
    ToRnc.convert(schema)
  end
end
