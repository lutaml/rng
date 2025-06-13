# frozen_string_literal: true

require "lutaml/model"
require "lutaml/model/xml_adapter/nokogiri_adapter"

Lutaml::Model::Config.configure do |config|
  config.xml_adapter = Lutaml::Model::XmlAdapter::NokogiriAdapter
end

module Rng
  class Error < StandardError; end

  autoload :AnyName, "rng/any_name"
  autoload :Attribute, "rng/attribute"
  autoload :Choice, "rng/choice"
  autoload :Data, "rng/data"
  autoload :Define, "rng/define"
  autoload :Element, "rng/element"
  autoload :Empty, "rng/empty"
  autoload :Except, "rng/except"
  autoload :ExternalRef, "rng/external_ref"
  autoload :Grammar, "rng/grammar"
  autoload :Group, "rng/group"
  autoload :Include, "rng/include"
  autoload :Interleave, "rng/interleave"
  autoload :List, "rng/list"
  autoload :Mixed, "rng/mixed"
  autoload :Name, "rng/name"
  autoload :NotAllowed, "rng/not_allowed"
  autoload :NsName, "rng/ns_name"
  autoload :OneOrMore, "rng/one_or_more"
  autoload :Optional, "rng/optional"
  autoload :Param, "rng/param"
  autoload :ParentRef, "rng/parent_ref"
  autoload :ParseRnc, "rng/parse_rnc"
  autoload :Pattern, "rng/pattern"
  autoload :Ref, "rng/ref"
  autoload :RncParser, "rng/rnc_parser"
  autoload :Start, "rng/start"
  autoload :Text, "rng/text"
  autoload :ToRnc, "rng/to_rnc"
  autoload :Value, "rng/value"
  autoload :Version, "rng/version"
  autoload :ZeroOrMore, "rng/zero_or_more"
end

module Rng
  module_function

  def parse(rng, location: nil, nested_schema: false)
    Grammar.from_xml(rng)
  end

  def parse_rnc(rnc)
    # Parse RNC and convert to RNG
    ParseRnc.parse(rnc)
  end

  def to_rnc(schema)
    # Convert RNG schema to RNC
    ToRnc.convert(schema)
  end
end
