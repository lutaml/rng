#!/usr/bin/env ruby
# frozen_string_literal: true

# Extracts external test resources from Jing-Trang's spectest.xml
# and creates fixture files for testing external href resolution.
#
# Creates:
#   spec/fixtures/spectest_external/  - extracted resources organized by test case
#   spec/fixtures/spectest_external/resources.json - mapping of test indices to files

require 'fileutils'
require 'json'
require 'nokogiri'

SPECTEST_XML = File.expand_path('~/src/external/jing-trang/mod/rng-validate/test/spectest.xml')
OUTPUT_DIR = 'spec/fixtures/spectest_external'
MAPPING_FILE = File.join(OUTPUT_DIR, 'resources.json')

def extract_resources
  unless File.exist?(SPECTEST_XML)
    puts "Error: spectest.xml not found at #{SPECTEST_XML}"
    puts 'Please ensure Jing-Trang is checked out at ~/src/external/jing-trang'
    exit 1
  end

  doc = Nokogiri::XML(File.read(SPECTEST_XML))

  # Clean up existing fixtures
  FileUtils.rm_rf(OUTPUT_DIR)
  FileUtils.mkdir_p(OUTPUT_DIR)

  # Find all test cases with resources
  test_cases = doc.xpath('//testCase[resource]')

  puts "Found #{test_cases.count} test cases with resources"
  puts "Extracting to #{OUTPUT_DIR}..."

  mapping = {}

  test_cases.each_with_index do |tc, idx|
    case_num = idx + 1
    section = tc.at_xpath('section')&.text || 'unknown'
    documentation = tc.at_xpath('documentation')&.text || ''

    case_dir = File.join(OUTPUT_DIR, "case_#{case_num}_#{section}")
    mapping[case_num] = {
      section: section,
      documentation: documentation,
      resources: []
    }

    # Handle resources in directories
    FileUtils.mkdir_p(case_dir)
    tc.xpath('.//dir').each do |dir|
      dir_name = dir['name']
      dir_path = File.join(case_dir, dir_name)
      FileUtils.mkdir_p(dir_path)

      dir.xpath('.//resource').each do |res|
        resource_name = res['name']
        content = res.inner_html.strip
        next if content.empty?

        resource_path = File.join(dir_path, resource_name)
        File.write(resource_path, content)
        mapping[case_num][:resources] << "#{dir_name}/#{resource_name}"
      end
    end

    # Handle resources at root level
    tc.xpath('./resource').each do |res|
      resource_name = res['name']
      content = res.inner_html.strip
      next if content.empty?

      resource_path = File.join(case_dir, resource_name)
      File.write(resource_path, content)
      mapping[case_num][:resources] << resource_name
    end
  end

  # Write mapping file
  File.write(MAPPING_FILE, JSON.pretty_generate(mapping))

  puts "\nExtracted #{test_cases.count} test cases to #{OUTPUT_DIR}"
  puts "Created mapping file: #{MAPPING_FILE}"

  puts "\nDirectory structure:"
  Dir.glob("#{OUTPUT_DIR}/**/*").reject { |f| File.directory?(f) }.sort.each { |f| puts "  #{f}" }

  puts "\nTo use these fixtures, update spectest_spec.rb to use resolve_external: true"
  puts 'and reference the case_N directories when resolving external refs.'
end

# Run if called directly
extract_resources if __FILE__ == $PROGRAM_NAME
