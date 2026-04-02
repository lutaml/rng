# frozen_string_literal: true

require "spec_helper"

RSpec.describe "RNG to RNC Round-trip Tests" do
  describe "RNC Parser" do
    it "exists as a class" do
      expect(defined?(Rng::RncParser)).to eq("constant")
    end

    it "has a parse method" do
      expect(Rng::RncParser).to respond_to(:parse)
    end
  end

  describe "RNG to RNC Conversion" do
    context "with the address book schema" do
      let(:address_book_rng) do
        File.read("spec/fixtures/rng/address_book.rng")
      end

      let(:address_book_rnc) do
        File.read("spec/fixtures/rnc/address_book.rnc")
      end

      it "can convert RNG to RNC" do
        rng_schema = Rng.parse(address_book_rng)
        expect(rng_schema).not_to be_nil

        rnc = Rng.to_rnc(rng_schema)
        expect(rnc).to include("element addressBook")
        expect(rnc).to include("element card")
        expect(rnc).to include("element name")
      end

      it "can parse RNC back to RNG" do
        rng_schema = Rng.parse_rnc(address_book_rnc)
        expect(rng_schema).to be_a(Rng::Grammar)

        xml = rng_schema.to_xml
        expect(xml).to include("<grammar")
        expect(xml).to include('name="addressBook"')
      end

      it "supports round-trip conversion" do
        rng_schema = Rng.parse(address_book_rng)
        rnc = Rng.to_rnc(rng_schema)
        rng_schema_from_rnc = Rng.parse_rnc(rnc)

        expect(rng_schema_from_rnc).to be_a(Rng::Grammar)

        xml = rng_schema_from_rnc.to_xml
        expect(xml).to include('name="addressBook"')
        expect(xml).to include('name="card"')
      end
    end
  end

  describe "RNC to RNG Conversion" do
    context "with the address book example" do
      it "can convert RNC to RNG" do
        rnc = File.read("spec/fixtures/rnc/address_book.rnc")
        xml_output = Rng.parse_rnc(rnc).to_xml
        expect(xml_output).to include("<grammar")
        expect(xml_output).to include('xmlns="http://relaxng.org/ns/structure/1.0"')

        # Verify it produces parseable RNG XML
        rng_schema = Rng.parse(xml_output)
        expect(rng_schema).to be_a(Rng::Grammar)
      end
    end
  end

  describe "Round-trip with complex features" do
    describe "RELAX NG pattern features" do
      it "preserves attribute definitions" do
        rnc = <<~RNC
          start = element foo {
            attribute bar { text },
            element baz { text }
          }
        RNC
        grammar = Rng.parse_rnc(rnc)
        xml = grammar.to_xml
        expect(xml).to include("<attribute")
        expect(xml).to include('name="bar"')
      end

      it "preserves choices" do
        rnc = <<~RNC
          start = element foo {
            (element a { text } | element b { text })
          }
        RNC
        grammar = Rng.parse_rnc(rnc)
        xml = grammar.to_xml
        expect(xml).to include("<choice")
      end

      it "preserves interleave" do
        rnc = <<~RNC
          start = element foo {
            element a { text } & element b { text }
          }
        RNC
        grammar = Rng.parse_rnc(rnc)
        xml = grammar.to_xml
        expect(xml).to include("<interleave")
      end

      it "preserves data types" do
        rnc = <<~RNC
          start = element foo {
            attribute count { xsd:integer }
          }
        RNC
        grammar = Rng.parse_rnc(rnc)
        xml = grammar.to_xml
        expect(xml).to include("<data")
        expect(xml).to include("integer")
      end

      it "preserves namespaces" do
        rnc = <<~RNC
          default namespace = "http://example.org"
          start = element foo { text }
        RNC
        grammar = Rng.parse_rnc(rnc)
        xml = grammar.to_xml
        expect(xml).to include("<grammar")
        expect(grammar.ns).to eq("http://example.org")
      end
    end
  end
end
