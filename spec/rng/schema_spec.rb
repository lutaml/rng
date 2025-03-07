require "spec_helper"

RSpec.describe Rng::Schema do
  describe "RNG parsing" do
    let(:rng_input) do
      File.read("spec/fixtures/rng/address_book.rng")
    end

    it "correctly parses RNG" do
      parsed = Rng.parse(rng_input)
      expect(parsed).to be_a(Rng::Schema)
      expect(parsed.element).to be_a(Rng::Element)
      expect(parsed.element.name).to eq("addressBook")
    end
  end

  xdescribe "RNC parsing" do
    let(:rnc_input) do
      File.read("spec/fixtures/rnc/address_book.rnc")
    end

    it "correctly parses RNC" do
      parsed = Rng.parse_rnc(rnc_input)
      expect(parsed).to be_a(Rng::Schema)
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
      expect(parsed).to be_a(Rng::Schema)
      expect(parsed.element).to be_a(Rng::Element)
      expect(parsed.element.name).to eq("addressBook")
    end
  end

  describe "Complex schema parsing" do
    let(:complex_rng_input) do
      File.read("spec/fixtures/rng/complex_example.rng")
    end

    it "correctly parses complex RNG" do
      parsed = Rng.parse(complex_rng_input)
      expect(parsed).to be_a(Rng::Schema)
      expect(parsed.datatypeLibrary).to eq("http://www.w3.org/2001/XMLSchema-datatypes")
      expect(parsed.start).to be_a(Rng::Start)
      expect(parsed.start.element).to be_a(Rng::Element)
      expect(parsed.start.element.name).to eq("document")
    end
  end

  describe "Grammar with named patterns" do
    let(:grammar_rng_input) do
      File.read("spec/fixtures/rng/address_book_grammar.rng")
    end

    it "correctly parses grammar with named patterns" do
      parsed = Rng.parse(grammar_rng_input)
      expect(parsed).to be_a(Rng::Schema)
      expect(parsed.start).to be_a(Rng::Start)
      expect(parsed.define).to be_a(Array)
      expect(parsed.define.size).to eq(1)
      expect(parsed.define.first.name).to eq("cardContent")
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
      rnc = Rng.to_rnc(parsed_rng)

      # Compare key properties
      expect(parsed_rng.element.name).to eq(parsed_rnc.element.name)
    end
  end
end
