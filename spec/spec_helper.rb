# frozen_string_literal: true

require "rng"
require "xml/c14n"
require "equivalent-xml"
require "nokogiri"
require "diffy"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Add helper method for XML comparison
  config.include(Module.new do
    def normalize_xml(xml)
      Xml::C14n.format(xml)
    end

    def format_xml(xml_string)
      # Use Nokogiri to parse and format the XML
      # Strip comments for comparison purposes - we care about structure, not documentation
      doc = Nokogiri::XML(xml_string, &:noblanks)

      # Remove all comment nodes before comparison
      doc.xpath("//comment()").remove

      doc.to_xml(indent: 2)
    end

    def diff_xml(actual, expected)
      # Generate a readable diff between the formatted XML strings
      Diffy::Diff.new(expected, actual, context: 3).to_s
    end
  end)

  # Add custom matchers for XML comparison
  RSpec::Matchers.define :be_equivalent_to_xml do |expected|
    match do |actual|
      @actual_formatted = format_xml(actual.to_s)
      @expected_formatted = format_xml(expected.to_s)
      EquivalentXml.equivalent?(@actual_formatted, @expected_formatted)
    end

    failure_message do
      diff = diff_xml(@actual_formatted, @expected_formatted)
      "Expected XML to be equivalent, but it wasn't.\n\nDiff:\n#{diff}"
    end
  end
end
