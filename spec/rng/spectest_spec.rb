# frozen_string_literal: true

require "spec_helper"
require "nokogiri"

# Load the test suite XML file once for all tests
SPEC_TEST_XML_PATH = "spec/fixtures/spectest.xml"
SPEC_TEST_XML = Nokogiri::XML(File.read(SPEC_TEST_XML_PATH))

# This helper function processes a test suite recursively and generates tests
def process_test_suite(suite_element, context_description = "")
  # Get documentation or section number for the context description
  documentation = suite_element.xpath("./documentation").text.strip
  section = suite_element.xpath("./section").text.strip

  # Build context description
  context_desc = context_description
  if documentation.length > 0
    context_desc = context_desc.empty? ? documentation : "#{context_desc}: #{documentation}"
  elsif section.length > 0
    context_desc = context_desc.empty? ? "Section #{section}" : "#{context_desc} Section #{section}"
  end

  # Use a non-empty description
  context_desc = "RELAX NG Test Suite" if context_desc.empty?

  # Generate tests within a context
  context(context_desc) do
    # Process all test cases in this suite
    suite_element.xpath("./testCase").each do |test_case|
      test_documentation = test_case.xpath("./documentation").text.strip
      test_section = test_case.xpath("./section").text.strip

      # Create descriptive test name
      test_desc = if test_documentation.length > 0
                    test_documentation
                  elsif test_section.length > 0
                    "Section #{test_section} compliance"
                  else
                    "Schema validation"
                  end

      # Variable to store the last correct schema XML for validation tests
      last_correct_schema_xml = nil

      # Test correct schemas
      test_case.xpath("./correct").each do |correct_schema|
        schema_xml = correct_schema.inner_html.strip

        # Skip empty schemas
        next if schema_xml.empty?

        # Store for validation tests
        last_correct_schema_xml = schema_xml

        it "#{test_desc} - correct schema parsing" do
          schema = Rng::Grammar.from_xml(schema_xml)
          expect(schema).not_to be_nil
        rescue StandardError => e
          raise "Expected schema to be valid but got: #{e.message}\nSchema:\n#{schema_xml}"
        end

        # Add round-trip test
        it "#{test_desc} - correct schema round-trip" do
          # Parse the XML into a schema
          # Parse the XML to determine the root element name
          xml_doc = Nokogiri::XML(schema_xml)
          root_element_name = xml_doc.root&.name

          # Choose the appropriate class based on the root element name
          schema = if root_element_name == "grammar"
                     Rng::Grammar.from_xml(schema_xml)
                   elsif root_element_name == "element"
                     Rng::Element.from_xml(schema_xml)
                   else
                     # Default to Schema for other cases
                     raise "Unknown root element: #{root_element_name}"
                   end

          # Convert the schema back to XML
          regenerated = schema.to_xml

          # Verify the regenerated XML matches the original
          expect(regenerated).to be_equivalent_to_xml(schema_xml)
        end
      end

      # Test incorrect schemas
      test_case.xpath("./incorrect").each do |incorrect_schema|
        schema_xml = incorrect_schema.inner_html.strip

        # Skip empty schemas
        next if schema_xml.empty?

        it "#{test_desc} - incorrect schema" do
          skip "Schema validation not yet implemented"
          # Once validation is implemented, uncomment:
          # expect { Rng::Grammar.from_xml(schema_xml) }.to raise_error
        end
      end

      # Test valid XML examples (for validation)
      next unless last_correct_schema_xml

      test_case.xpath("./valid").each do |valid_xml|
        xml_content = valid_xml.inner_text.strip

        # Skip empty XML
        next if xml_content.empty?

        it "#{test_desc} - valid XML example" do
          skip "XML validation not yet implemented"
          # Once validation is implemented, uncomment:
          # schema = Rng::Grammar.from_xml(last_correct_schema_xml)
          # expect(schema.valid?(xml_content)).to be true
        end
      end

      # Test invalid XML examples (for validation)
      test_case.xpath("./invalid").each do |invalid_xml|
        xml_content = invalid_xml.inner_text.strip

        # Skip empty XML
        next if xml_content.empty?

        it "#{test_desc} - invalid XML example" do
          skip "XML validation not yet implemented"
          # Once validation is implemented, uncomment:
          # schema = Rng::Grammar.from_xml(last_correct_schema_xml)
          # expect(schema.valid?(xml_content)).to be false
        end
      end
    end

    # Process nested test suites recursively
    suite_element.xpath("./testSuite").each do |nested_suite|
      process_test_suite(nested_suite, context_desc)
    end
  end
end

RSpec.describe "RELAX NG Specification Tests" do
  # First, confirm the test file exists
  it "finds the spectest.xml file" do
    expect(File.exist?(SPEC_TEST_XML_PATH)).to be true
  end

  # Generate a summary of the test suite
  describe "Test Suite Summary" do
    it "contains test cases organized by section" do
      sections = SPEC_TEST_XML.xpath("//section").map(&:text).uniq
      puts "Found #{sections.length} sections with tests"

      correct_count = SPEC_TEST_XML.xpath("//correct").count
      incorrect_count = SPEC_TEST_XML.xpath("//incorrect").count
      valid_count = SPEC_TEST_XML.xpath("//valid").count
      invalid_count = SPEC_TEST_XML.xpath("//invalid").count

      puts "Test suite contains:"
      puts "- #{correct_count} correct schemas"
      puts "- #{incorrect_count} incorrect schemas"
      puts "- #{valid_count} valid XML examples"
      puts "- #{invalid_count} invalid XML examples"

      total = correct_count + incorrect_count
      expect(total).to be > 0
    end
  end

  # Start processing from the root test suite
  process_test_suite(SPEC_TEST_XML.xpath("/testSuite").first)
end
