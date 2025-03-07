# frozen_string_literal: true

require "lutaml/model"
require "lutaml/model/xml_adapter/nokogiri_adapter"
Lutaml::Model::Config.xml_adapter_type = :nokogiri

module Rng
  class Error < StandardError; end
end

require "zeitwerk"
loader = Zeitwerk::Loader.for_gem
loader.setup # ready!

loader.eager_load

module Rng
  module_function

  def parse(rng, location: nil, nested_schema: false)
    Schema.from_xml(rng)
  end

  def parse_rnc(rnc)
    # Parse RNC and convert to RNG
    rng_xml = RncParser.parse(rnc)
    parse(rng_xml)
  end

  def to_rnc(schema)
    # Convert RNG schema to RNC
    RncParser.to_rnc(schema)
  end
end
