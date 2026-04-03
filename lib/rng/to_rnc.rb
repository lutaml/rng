# frozen_string_literal: true

require_relative 'rnc_parser'

module Rng
  # RNG to RNC converter module
  # Provides functionality to convert RELAX NG XML Schema (RNG) to RELAX NG Compact Syntax (RNC)
  module ToRnc
    class << self
      # Convert an RNG schema object to RNC syntax
      # @param schema [Rng::Grammar] The schema to convert
      # @return [String] The RNC representation of the schema
      def convert(schema)
        # Delegate to RncParser which has the actual implementation via RncBuilder
        RncParser.to_rnc(schema)
      end
    end
  end

  # Add class-level conversion method
  def self.to_rnc(schema)
    ToRnc.convert(schema)
  end
end
