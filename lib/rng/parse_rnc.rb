# frozen_string_literal: true

module Rng
  # RNC Parser module
  # Provides functionality to parse RELAX NG Compact Syntax (RNC) files
  module ParseRnc
    class << self
      # Parse RNC syntax and return an RNG schema object
      # @param rnc_string [String] The RNC content to parse
      # @return [Rng::Grammar] The parsed schema object
      def parse(rnc_string)
        RncParser.parse(rnc_string)
      end
    end
  end
end
