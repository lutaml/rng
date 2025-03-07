require "spec_helper"

RSpec.describe Rng::Schema do
  describe "RNG parsing" do
    let(:rng_input) do
      File.read("spec/fixtures/rng/address_book.rng")
    end

    it "correctly parses RNG" do
      parsed = Rng.parse(rng_input)
      expect(parsed).to be_a(Rng::Schema)
      expect(parsed.element).to be_empty
      expect(parsed.start.element.first.name).to eq("addressBook")
    end
  end

  describe "Round-trip testing RNG" do
    let(:rng_input) do
      File.read("spec/fixtures/rng/address_book.rng")
    end

    it "correctly round-trips RNG to model and back" do
      # Parse the input RNG directly using Schema.from_xml
      parsed = Rng::Schema.from_xml(rng_input)

      # Generate XML from the model (using lutaml-model's existing functionality)
      regenerated = parsed.to_xml

      puts "Regenerated XML:"
      puts regenerated
      puts "Original RNG:"
      puts rng_input

      # Compare using the be_analogous_with matcher
      expect(regenerated).to be_analogous_with(rng_input)
    end

    let(:complex_rng_input) do
      File.read("spec/fixtures/rng/complex_example.rng")
    end

    it "correctly round-trips complex RNG to model and back" do
      parsed = Rng::Schema.from_xml(complex_rng_input)
      regenerated = parsed.to_xml
      expect(regenerated).to be_analogous_with(complex_rng_input)
    end
  end

  describe "Round-trip testing for complex RNG schemas" do
    let(:relaxng_schema_input) do
      File.read("spec/fixtures/rng/relaxng.rng")
    end

    it "correctly round-trips the RELAX NG schema itself" do
      parsed = Rng::Schema.from_xml(relaxng_schema_input)
      regenerated = parsed.to_xml
      expect(regenerated).to be_analogous_with(relaxng_schema_input)
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
