# frozen_string_literal: true

require 'nokogiri'

module Rng
  # Parses RELAX NG test suite XML files (like compacttest.xml)
  class TestSuiteParser
    # Represents a single test case with RNC and RNG versions
    class TestCase
      attr_reader :id, :compact_correct, :compact_incorrect,
                  :xml_correct, :xml_incorrect,
                  :compact_resources, :xml_resources

      def initialize(id:)
        @id = id
        @compact_correct = nil
        @compact_incorrect = nil
        @xml_correct = nil
        @xml_incorrect = nil
        @compact_resources = {}
        @xml_resources = {}
      end

      def valid_rnc?
        !compact_correct.nil?
      end

      def invalid_rnc?
        !compact_incorrect.nil?
      end

      def valid_rng?
        !xml_correct.nil?
      end

      def has_resources?
        !compact_resources.empty? || !xml_resources.empty?
      end

      def description
        if valid_rnc? && valid_rng?
          'RNC ↔ RNG conversion'
        elsif valid_rnc?
          'Valid RNC parsing'
        elsif invalid_rnc?
          'Invalid RNC rejection'
        else
          'Test case'
        end
      end
    end

    attr_reader :test_cases

    def initialize(xml_content)
      @doc = Nokogiri::XML(xml_content)
      @test_cases = []
      parse_test_cases
    end

    # Load test suite from file path
    def self.load(file_path)
      content = File.read(file_path)
      new(content)
    end

    # Get test cases with valid RNC that should parse
    def valid_rnc_cases
      test_cases.select(&:valid_rnc?)
    end

    # Get test cases with invalid RNC that should fail
    def invalid_rnc_cases
      test_cases.select(&:invalid_rnc?)
    end

    # Get test cases with both RNC and RNG for round-trip testing
    def roundtrip_cases
      test_cases.select { |tc| tc.valid_rnc? && tc.valid_rng? }
    end

    # Get test cases with resources (external files)
    def resource_cases
      test_cases.select(&:has_resources?)
    end

    private

    def parse_test_cases
      @doc.xpath('//testCase').each_with_index do |test_node, index|
        test_case = TestCase.new(id: index + 1)

        # Parse compact syntax (RNC)
        parse_compact_section(test_node, test_case)

        # Parse XML syntax (RNG)
        parse_xml_section(test_node, test_case)

        @test_cases << test_case
      end
    end

    def parse_compact_section(test_node, test_case)
      compact_node = test_node.at_xpath('compact')
      return unless compact_node

      # Parse resources
      compact_node.xpath('resource').each do |resource_node|
        name = resource_node['name']
        content = resource_node.text.strip
        test_case.compact_resources[name] = content
      end

      # Parse correct RNC
      correct_node = compact_node.at_xpath('correct')
      if correct_node
        test_case.instance_variable_set(
          :@compact_correct,
          correct_node.text.strip
        )
      end

      # Parse incorrect RNC
      incorrect_node = compact_node.at_xpath('incorrect')
      return unless incorrect_node

      test_case.instance_variable_set(
        :@compact_incorrect,
        incorrect_node.text.strip
      )
    end

    def parse_xml_section(test_node, test_case)
      xml_node = test_node.at_xpath('xml')
      return unless xml_node

      # Parse resources
      xml_node.xpath('resource').each do |resource_node|
        name = resource_node['name']
        # Get the first element child as RNG content
        content_node = resource_node.elements.first
        content = content_node ? content_node.to_xml : ''
        test_case.xml_resources[name] = content
      end

      # Parse correct RNG
      correct_node = xml_node.at_xpath('correct')
      if correct_node
        # Get the first element child as RNG content
        rng_node = correct_node.elements.first
        test_case.instance_variable_set(
          :@xml_correct,
          rng_node ? rng_node.to_xml : ''
        )
      end

      # Parse incorrect RNG (if any)
      incorrect_node = xml_node.at_xpath('incorrect')
      return unless incorrect_node

      rng_node = incorrect_node.elements.first
      test_case.instance_variable_set(
        :@xml_incorrect,
        rng_node ? rng_node.to_xml : ''
      )
    end
  end
end
