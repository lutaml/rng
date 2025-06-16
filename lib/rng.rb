# frozen_string_literal: true

require "lutaml/model"

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
