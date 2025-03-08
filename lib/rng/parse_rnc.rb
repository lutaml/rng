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
        # This is a placeholder implementation
        # The actual parsing logic would need to be implemented

        # For now, we delegate to RncParser which is our internal implementation
        # In the future, this could be expanded with additional functionality
        RncParser.parse(rnc_string)
      end
    end
  end

  # Add class-level parsing method
  def self.parse_rnc(rnc_string)
    ParseRnc.parse(rnc_string)
  end
end
