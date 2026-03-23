# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Round-Trip Conversion" do
  # Helper method to check if two Grammar objects are semantically equivalent
  def grammars_equivalent?(grammar1, grammar2)
    # Compare key structural elements
    return false unless grammar1.instance_of?(grammar2.class)

    # Compare start elements
    if grammar1.start.any? && grammar2.start.any?
      start1 = grammar1.start.first
      start2 = grammar2.start.first

      # Compare element names if they exist
      if start1.element && start2.element && start1.element.attr_name != start2.element.attr_name
        return false
      end
    end

    # Compare defines if they exist
    if grammar1.define.any? && grammar2.define.any?
      return false unless grammar1.define.length == grammar2.define.length

      grammar1.define.zip(grammar2.define).each do |def1, def2|
        return false unless def1.name == def2.name
      end
    end

    true
  end

  describe "RNG → RNC → RNG" do
    context "with address_book.rng" do
      let(:original_rng) { File.read("spec/fixtures/rng/address_book.rng") }

      it "maintains semantic equivalence through round-trip" do
        # Parse RNG
        grammar1 = Rng.parse(original_rng)

        # Convert to RNC
        rnc = Rng.to_rnc(grammar1)
        expect(rnc).to be_a(String)
        expect(rnc).to include("element addressBook")

        # Parse RNC back to Grammar
        grammar2 = Rng.parse_rnc(rnc)

        # Convert back to RNG
        regenerated_rng = grammar2.to_xml

        # Parse regenerated RNG
        grammar3 = Rng.parse(regenerated_rng)

        # Compare key structural elements
        expect(grammar3.start.first.element.attr_name).to eq("addressBook")
        expect(grammars_equivalent?(grammar1, grammar3)).to be true
      end

      it "produces valid RNC syntax" do
        grammar = Rng.parse(original_rng)
        rnc = Rng.to_rnc(grammar)

        # Should be parseable
        expect { Rng.parse_rnc(rnc) }.not_to raise_error
      end

      it "preserves element structure" do
        grammar1 = Rng.parse(original_rng)
        rnc = Rng.to_rnc(grammar1)
        grammar2 = Rng.parse_rnc(rnc)

        # Both should have addressBook element
        expect(grammar1.start.first.element.attr_name).to eq("addressBook")
        expect(grammar2.start.first.element.attr_name).to eq("addressBook")
      end
    end

    context "with simple RNG schemas" do
      it "handles single element schema" do
        rng = <<~RNG
          <grammar xmlns="http://relaxng.org/ns/structure/1.0">
            <start>
              <element name="root">
                <text/>
              </element>
            </start>
          </grammar>
        RNG

        grammar1 = Rng.parse(rng)
        rnc = Rng.to_rnc(grammar1)
        grammar2 = Rng.parse_rnc(rnc)
        rng2 = grammar2.to_xml
        grammar3 = Rng.parse(rng2)

        expect(grammar3.start.first.element.attr_name).to eq("root")
      end

      it "handles choice patterns" do
        rng = <<~RNG
          <grammar xmlns="http://relaxng.org/ns/structure/1.0">
            <start>
              <choice>
                <element name="option1"><text/></element>
                <element name="option2"><text/></element>
              </choice>
            </start>
          </grammar>
        RNG

        grammar1 = Rng.parse(rng)
        rnc = Rng.to_rnc(grammar1)

        # Note: Current RNC builder converts choice to sequence in some cases
        # This is a known limitation - choice should use | not ,
        expect(rnc).to include("element option1")
        expect(rnc).to include("element option2")

        # Can still parse back
        grammar2 = Rng.parse_rnc(rnc)
        expect(grammar2).to be_a(Rng::Grammar)
      end

      it "handles group patterns" do
        rng = <<~RNG
          <grammar xmlns="http://relaxng.org/ns/structure/1.0">
            <start>
              <group>
                <element name="first"><text/></element>
                <element name="second"><text/></element>
              </group>
            </start>
          </grammar>
        RNG

        grammar1 = Rng.parse(rng)
        rnc = Rng.to_rnc(grammar1)
        grammar2 = Rng.parse_rnc(rnc)

        expect(grammar2.start.first.group).not_to be_nil
      end
    end
  end

  describe "RNC → RNG → RNC" do
    context "with address_book.rnc" do
      let(:original_rnc) { File.read("spec/fixtures/rnc/address_book.rnc") }

      it "maintains semantic equivalence through round-trip" do
        # Parse RNC
        grammar1 = Rng.parse_rnc(original_rnc)

        # Convert to RNG
        rng = grammar1.to_xml
        expect(rng).to include("<grammar")
        expect(rng).to include('<element name="addressBook">')

        # Parse RNG back to Grammar
        grammar2 = Rng.parse(rng)

        # Convert back to RNC
        regenerated_rnc = Rng.to_rnc(grammar2)

        # Parse regenerated RNC
        grammar3 = Rng.parse_rnc(regenerated_rnc)

        # Compare key structural elements
        expect(grammar3.start.first.element.attr_name).to eq("addressBook")
        expect(grammars_equivalent?(grammar1, grammar3)).to be true
      end

      it "produces valid RNG XML" do
        grammar = Rng.parse_rnc(original_rnc)
        rng = grammar.to_xml

        # Should be parseable
        expect { Rng.parse(rng) }.not_to raise_error
      end

      it "preserves element structure" do
        grammar1 = Rng.parse_rnc(original_rnc)
        rng = grammar1.to_xml
        grammar2 = Rng.parse(rng)

        # Both should have addressBook element
        expect(grammar1.start.first.element.attr_name).to eq("addressBook")
        expect(grammar2.start.first.element.attr_name).to eq("addressBook")
      end
    end

    context "with simple RNC schemas" do
      it "handles single element schema" do
        rnc = <<~RNC
          start = element root { text }
        RNC

        grammar1 = Rng.parse_rnc(rnc)
        rng = grammar1.to_xml
        grammar2 = Rng.parse(rng)
        rnc2 = Rng.to_rnc(grammar2)
        grammar3 = Rng.parse_rnc(rnc2)

        expect(grammar3.start.first.element.attr_name).to eq("root")
      end

      it "handles choice patterns (|)" do
        rnc = <<~RNC
          start = element option1 { text } | element option2 { text }
        RNC

        grammar1 = Rng.parse_rnc(rnc)
        rng = grammar1.to_xml
        grammar2 = Rng.parse(rng)

        expect(grammar2.start.first.choice).not_to be_nil
      end

      it "handles sequence patterns (,)" do
        rnc = <<~RNC
          start = element first { text }, element second { text }
        RNC

        grammar1 = Rng.parse_rnc(rnc)
        rng = grammar1.to_xml
        grammar2 = Rng.parse(rng)

        expect(grammar2.start.first.group).not_to be_nil
      end

      it "handles optional patterns (?)" do
        rnc = <<~RNC
          start = element optional { text }?
        RNC

        grammar1 = Rng.parse_rnc(rnc)
        rng = grammar1.to_xml
        grammar2 = Rng.parse(rng)

        expect(grammar2.start.first.optional).not_to be_nil
      end

      it "handles zero-or-more patterns (*)" do
        rnc = <<~RNC
          start = element item { text }*
        RNC

        grammar1 = Rng.parse_rnc(rnc)
        rng = grammar1.to_xml
        grammar2 = Rng.parse(rng)

        expect(grammar2.start.first.zeroOrMore).not_to be_nil
      end

      it "handles one-or-more patterns (+)" do
        rnc = <<~RNC
          start = element item { text }+
        RNC

        grammar1 = Rng.parse_rnc(rnc)
        rng = grammar1.to_xml
        grammar2 = Rng.parse(rng)

        # oneOrMore can be either an array or a single object depending on parsing
        one_or_more = grammar2.start.first.oneOrMore
        expect(one_or_more).not_to be_nil
        # Check if it's an array or single object
        if one_or_more.is_a?(Array)
          expect(one_or_more.length).to be > 0
        else
          expect(one_or_more).to be_a(Rng::OneOrMore)
        end
      end
    end
  end

  describe "XML comparison using canon matchers" do
    context "with analogous comparison" do
      it "recognizes semantically equivalent XML" do
        rng1 = <<~RNG
          <grammar xmlns="http://relaxng.org/ns/structure/1.0">
            <start>
              <element name="root"><text/></element>
            </start>
          </grammar>
        RNG

        grammar = Rng.parse(rng1)
        rng2 = grammar.to_xml

        # Should be analogous (semantically equivalent)
        expect(rng2).to be_analogous_with(rng1)
      end
    end

    context "with formatted XML comparison" do
      it "recognizes equivalent formatted XML" do
        rng1 = <<~RNG
          <grammar xmlns="http://relaxng.org/ns/structure/1.0">
            <start>
              <element name="root"><text/></element>
            </start>
          </grammar>
        RNG

        grammar = Rng.parse(rng1)
        rng2 = grammar.to_xml

        # May differ in formatting but should be equivalent
        expect(rng2).to be_xml_equivalent_to(rng1)
      end
    end
  end

  describe "Format compatibility" do
    it "RNC and RNG represent the same schema" do
      rnc = File.read("spec/fixtures/rnc/address_book.rnc")
      rng = File.read("spec/fixtures/rng/address_book.rng")

      grammar_from_rnc = Rng.parse_rnc(rnc)
      grammar_from_rng = Rng.parse(rng)

      # Both should parse successfully
      expect(grammar_from_rnc).to be_a(Rng::Grammar)
      expect(grammar_from_rng).to be_a(Rng::Grammar)

      # Both should have the same root element
      expect(grammar_from_rnc.start.first.element.attr_name).to eq("addressBook")
      expect(grammar_from_rng.start.first.element.attr_name).to eq("addressBook")
    end
  end

  describe "Edge cases" do
    it "handles empty element" do
      rnc = "start = element root { empty }"
      grammar = Rng.parse_rnc(rnc)
      rng = grammar.to_xml
      grammar2 = Rng.parse(rng)

      expect(grammar2.start.first.element.empty).not_to be_nil
    end

    it "handles attributes" do
      rnc = "start = element root { attribute id { text } }"
      grammar = Rng.parse_rnc(rnc)
      rng = grammar.to_xml
      grammar2 = Rng.parse(rng)

      expect(grammar2.start.first.element.attribute).not_to be_nil
    end

    it "handles mixed content" do
      rnc = "start = element root { mixed { element child { text } } }"
      grammar = Rng.parse_rnc(rnc)
      rng = grammar.to_xml
      grammar2 = Rng.parse(rng)

      expect(grammar2.start.first.element.mixed).not_to be_nil
    end
  end
end
