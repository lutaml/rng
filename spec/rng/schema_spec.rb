# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rng::Grammar do
  describe "RNG parsing" do
    let(:rng_input) do
      File.read("spec/fixtures/rng/address_book.rng")
    end

    it "correctly parses RNG" do
      parsed = Rng.parse(rng_input)
      expect(parsed).to be_a(Rng::Grammar)
      expect(parsed.element).to be_empty
      expect(parsed.start.element.attr_name).to eq("addressBook")
    end
  end

  describe "Round-trip testing RNG" do
    # Address Book Tests
    let(:address_book_rng) do
      File.read("spec/fixtures/rng/address_book.rng")
    end

    it "correctly round-trips address_book.rng (analogous comparison)" do
      parsed = Rng::Grammar.from_xml(address_book_rng)
      regenerated = parsed.to_xml
      expect(regenerated).to be_analogous_with(address_book_rng)
    end

    it "correctly round-trips address_book.rng (formatted equivalent comparison)" do
      parsed = Rng::Grammar.from_xml(address_book_rng)
      regenerated = parsed.to_xml
      expect(regenerated).to be_equivalent_to_xml(address_book_rng)
    end

    # RELAX NG Schema Tests
    let(:relaxng_schema) do
      File.read("spec/fixtures/rng/relaxng.rng")
    end

    it "correctly round-trips relaxng.rng (analogous comparison)" do
      parsed = Rng::Grammar.from_xml(relaxng_schema)
      regenerated = parsed.to_xml
      expect(regenerated).to be_analogous_with(relaxng_schema)
    end

    it "correctly round-trips relaxng.rng (formatted equivalent comparison)" do
      parsed = Rng::Grammar.from_xml(relaxng_schema)
      regenerated = parsed.to_xml
      expect(regenerated).to be_equivalent_to_xml(relaxng_schema)
    end

    # Test Suite Schema Tests
    let(:test_suite_rng) do
      File.read("spec/fixtures/rng/testSuite.rng")
    end

    it "correctly round-trips testSuite.rng (analogous comparison)" do
      parsed = Rng::Grammar.from_xml(test_suite_rng)
      regenerated = parsed.to_xml
      expect(regenerated).to be_analogous_with(test_suite_rng)
    end

    it "correctly round-trips testSuite.rng (formatted equivalent comparison)" do
      parsed = Rng::Grammar.from_xml(test_suite_rng)
      regenerated = parsed.to_xml
      expect(regenerated).to be_equivalent_to_xml(test_suite_rng)
    end
  end

  xdescribe "RNC parsing" do
    let(:rnc_input) do
      File.read("spec/fixtures/rnc/address_book.rnc")
    end

    it "correctly parses RNC" do
      parsed = Rng.parse_rnc(rnc_input)
      expect(parsed).to be_a(Rng::Grammar)
      expect(parsed.element).to be_a(Rng::Element)
      expect(parsed.element.name).to eq("addressBook")
    end
  end

  xdescribe "RNG to RNC conversion" do
    let(:rng_input) do
      File.read("spec/fixtures/rng/address_book.rng")
    end

    it "correctly converts RNG to RNC" do
      parsed = Rng.parse(rng_input)
      rnc = Rng.to_rnc(parsed)
      expect(rnc).to include("element addressBook")
      expect(rnc).to include("element card")
      expect(rnc).to include("element name { text }")
      expect(rnc).to include("element email { text }")
      expect(rnc).to include("element note { text }?")
    end
  end

  xdescribe "RNC to RNG conversion" do
    let(:rnc_input) do
      File.read("spec/fixtures/rnc/address_book.rnc")
    end

    it "correctly converts RNC to RNG" do
      parsed = Rng.parse_rnc(rnc_input)
      expect(parsed).to be_a(Rng::Grammar)
      expect(parsed.element).to be_a(Rng::Element)
      expect(parsed.element.name).to eq("addressBook")
    end
  end

  xdescribe "Round-trip testing RNG/RNC" do
    let(:rng_input) do
      File.read("spec/fixtures/rng/address_book.rng")
    end

    let(:rnc_input) do
      File.read("spec/fixtures/rnc/address_book.rnc")
    end

    it "correctly round-trips RNG to RNC and back" do
      parsed_rng = Rng.parse(rng_input)
      rnc = Rng.to_rnc(parsed_rng)
      parsed_rnc = Rng.parse_rnc(rnc)

      # Compare key properties
      expect(parsed_rnc.element.name).to eq(parsed_rng.element.name)
    end

    it "correctly round-trips RNC to RNG and back" do
      parsed_rnc = Rng.parse_rnc(rnc_input)
      rng_xml = Rng::RncParser.parse(rnc_input)
      parsed_rng = Rng.parse(rng_xml)
      Rng.to_rnc(parsed_rng)

      # Compare key properties
      expect(parsed_rng.element.name).to eq(parsed_rnc.element.name)
    end
  end
end
