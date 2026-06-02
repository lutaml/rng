# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rng::Grammar do
  describe 'RNG parsing' do
    let(:rng_input) do
      File.read('spec/fixtures/rng/address_book.rng')
    end

    it 'correctly parses RNG' do
      parsed = Rng.parse(rng_input)
      expect(parsed).to be_a(described_class)
      expect(parsed.element).to be_empty
      expect(parsed.start.first.element.attr_name).to eq('addressBook')
    end
  end

  describe 'Round-trip testing RNG' do
    # Address Book Tests
    let(:address_book_rng) do
      File.read('spec/fixtures/rng/address_book.rng')
    end

    # Test Suite Schema Tests
    let(:test_suite_rng) do
      File.read('spec/fixtures/rng/testSuite.rng')
    end
    # RELAX NG Schema Tests
    let(:relaxng_schema) do
      File.read('spec/fixtures/rng/relaxng.rng')
    end

    it 'correctly round-trips address_book.rng (analogous comparison)' do
      parsed = described_class.from_xml(address_book_rng)
      regenerated = parsed.to_xml
      expect(regenerated.gsub(/<!--.*?-->/m, '')).to be_xml_equivalent_to(address_book_rng.gsub(/<!--.*?-->/m, ''))
    end

    it 'correctly round-trips address_book.rng (formatted equivalent comparison)' do
      parsed = described_class.from_xml(address_book_rng)
      regenerated = parsed.to_xml
      expect(regenerated).to be_xml_equivalent_to(address_book_rng)
    end

    it 'correctly round-trips relaxng.rng (analogous comparison)' do
      parsed = described_class.from_xml(relaxng_schema)
      regenerated = parsed.to_xml
      # Strip comments for comparison since Lutaml doesn't preserve them
      expect(regenerated.gsub(/<!--.*?-->/m, '')).to be_xml_equivalent_to(relaxng_schema.gsub(/<!--.*?-->/m, ''))
    end

    it 'correctly round-trips relaxng.rng (formatted equivalent comparison)' do
      parsed = described_class.from_xml(relaxng_schema)
      regenerated = parsed.to_xml
      expect(regenerated.gsub(/<!--.*?-->/m, '')).to be_xml_equivalent_to(relaxng_schema.gsub(/<!--.*?-->/m, ''))
    end

    it 'correctly round-trips testSuite.rng (analogous comparison)' do
      parsed = described_class.from_xml(test_suite_rng)
      regenerated = parsed.to_xml
      expect(regenerated.gsub(/<!--.*?-->/m, '')).to be_xml_equivalent_to(test_suite_rng.gsub(/<!--.*?-->/m, ''))
    end

    it 'correctly round-trips testSuite.rng (formatted equivalent comparison)' do
      parsed = described_class.from_xml(test_suite_rng)
      regenerated = parsed.to_xml
      expect(regenerated.gsub(/<!--.*?-->/m, '')).to be_xml_equivalent_to(test_suite_rng.gsub(/<!--.*?-->/m, ''))
    end
  end

  describe 'RNC parsing' do
    let(:rnc_input) do
      File.read('spec/fixtures/rnc/address_book.rnc')
    end

    it 'correctly parses RNC' do
      parsed = Rng.parse_rnc(rnc_input)
      expect(parsed).to be_a(described_class)
      start_element = parsed.start.first.element
      expect(start_element).to be_a(Rng::Element)
      expect(start_element.attr_name).to eq('addressBook')
    end

    it 'resolves includes for in-memory RNC when location is provided' do
      main_path = File.expand_path('spec/fixtures/rnc/main_with_include.rnc')
      parsed = Rng.parse_rnc(File.read(main_path), location: main_path)

      expect(parsed).to be_a(described_class)
      expect(parsed.define.map(&:name)).to include('BasePattern', 'ExtendedPattern')
      expect(parsed.start.first.element.attr_name).to eq('doc')
    end

    it 'matches parse_file include resolution for in-memory RNC when location is provided' do
      main_path = File.expand_path('spec/fixtures/rnc/main_include_trailing.rnc')
      from_memory = Rng.parse_rnc(File.read(main_path), location: main_path)
      from_file = Rng.parse_file(main_path)

      expect(from_memory.start.first.element.attr_name).to eq(from_file.start.first.element.attr_name)
      expect(from_memory.define.map(&:name).sort).to eq(from_file.define.map(&:name).sort)
    end
  end

  describe 'RNG to RNC conversion' do
    let(:rng_input) do
      File.read('spec/fixtures/rng/address_book.rng')
    end

    it 'correctly converts RNG to RNC' do
      parsed = Rng.parse(rng_input)
      rnc = Rng.to_rnc(parsed)
      expect(rnc).to include('element addressBook')
      expect(rnc).to include('element card')
      expect(rnc).to include('element name')
      expect(rnc).to include('element email')
    end
  end

  describe 'RNC to RNG conversion' do
    let(:rnc_input) do
      File.read('spec/fixtures/rnc/address_book.rnc')
    end

    it 'correctly converts RNC to RNG' do
      parsed = Rng.parse_rnc(rnc_input)
      expect(parsed).to be_a(described_class)
      start_element = parsed.start.first.element
      expect(start_element).to be_a(Rng::Element)
      expect(start_element.attr_name).to eq('addressBook')
    end
  end

  describe 'Round-trip testing RNG/RNC' do
    let(:rng_input) do
      File.read('spec/fixtures/rng/address_book.rng')
    end

    let(:rnc_input) do
      File.read('spec/fixtures/rnc/address_book.rnc')
    end

    it 'correctly round-trips RNG to RNC and back' do
      parsed_rng = Rng.parse(rng_input)
      rnc = Rng.to_rnc(parsed_rng)
      parsed_rnc = Rng.parse_rnc(rnc)

      # Compare key properties
      rng_start_elem = parsed_rng.start.first.element
      rnc_start_elem = parsed_rnc.start.first.element
      expect(rnc_start_elem.attr_name).to eq(rng_start_elem.attr_name)
    end

    it 'correctly round-trips RNC to RNG and back' do
      parsed_rnc = Rng.parse_rnc(rnc_input)
      rng_xml = parsed_rnc.to_xml
      parsed_rng = Rng.parse(rng_xml)

      # Compare key properties
      rng_start_elem = parsed_rng.start.first.element
      rnc_start_elem = parsed_rnc.start.first.element
      expect(rng_start_elem.attr_name).to eq(rnc_start_elem.attr_name)
    end
  end
end
