# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Namespace Support" do
  describe "legacy compatibility" do
    it "parses default namespace (old format)" do
      rnc = 'default namespace = "http://example.com"
element foo { empty }'
      grammar = Rng.parse_rnc(rnc)
      expect(grammar).to be_a(Rng::Grammar)
      expect(grammar.start).not_to be_nil
    end

    it "generates RNG XML with default namespace" do
      rnc = 'default namespace = "http://example.com"
element foo { empty }'
      grammar = Rng.parse_rnc(rnc)
      xml = grammar.to_xml

      expect(xml).to include('ns="http://example.com"')
    end

    it "preserves namespace in element" do
      rnc = 'default namespace = "http://example.com"
element foo { empty }'
      grammar = Rng.parse_rnc(rnc)
      xml = grammar.to_xml

      expect(xml).to include("<grammar")
      expect(xml).to include('ns="http://example.com"')
    end
  end

  describe "new namespace declarations" do
    it "parses prefixed namespace" do
      rnc = 'namespace eg = "http://example.com"
element foo { empty }'
      grammar = Rng.parse_rnc(rnc)
      expect(grammar).to be_a(Rng::Grammar)
    end

    it "parses default namespace with prefix" do
      rnc = 'default namespace rng = "http://relaxng.org/ns/structure/1.0"
element foo { empty }'
      grammar = Rng.parse_rnc(rnc)
      expect(grammar).to be_a(Rng::Grammar)
    end

    it "parses multiple namespace declarations" do
      rnc = <<~RNC
        default namespace rng = "http://relaxng.org/ns/structure/1.0"
        namespace local = ""
        namespace eg = "http://example.com"

        start = element foo { empty }
      RNC
      grammar = Rng.parse_rnc(rnc)
      expect(grammar).to be_a(Rng::Grammar)
      expect(grammar.start).not_to be_nil
    end

    it "generates RNG XML with prefixed namespaces" do
      rnc = 'namespace eg = "http://example.com"
element eg:foo { empty }'
      grammar = Rng.parse_rnc(rnc)
      xml = grammar.to_xml

      expect(xml).to include('ns="http://example.com"')
      expect(xml).to include('name="foo"')
    end

    it "resolves namespace prefix to URI in elements" do
      rnc = 'namespace eg = "http://example.com"
element eg:bar { empty }'
      grammar = Rng.parse_rnc(rnc)
      xml = grammar.to_xml

      expect(xml).to include('ns="http://example.com"')
      expect(xml).not_to include('ns="eg"')
    end

    it "resolves namespace prefix to URI in attributes" do
      rnc = 'namespace eg = "http://example.com"
element foo { attribute eg:bar { text } }'
      grammar = Rng.parse_rnc(rnc)
      xml = grammar.to_xml

      expect(xml).to include('ns="http://example.com"')
      expect(xml).to include('name="bar"')
      expect(xml).not_to include('ns="eg"')
    end
  end

  describe "datatype library support" do
    it "parses datatype library declaration" do
      rnc = 'datatypes xsd = "http://www.w3.org/2001/XMLSchema-datatypes"
element foo { xsd:string }'
      grammar = Rng.parse_rnc(rnc)
      expect(grammar).to be_a(Rng::Grammar)
    end

    it "generates RNG XML with datatype library" do
      rnc = 'datatypes xsd = "http://www.w3.org/2001/XMLSchema-datatypes"
element foo { xsd:string }'
      grammar = Rng.parse_rnc(rnc)
      xml = grammar.to_xml

      expect(xml).to include('datatypeLibrary="http://www.w3.org/2001/XMLSchema-datatypes"')
    end

    it "applies datatype library to data elements" do
      rnc = 'datatypes xsd = "http://www.w3.org/2001/XMLSchema-datatypes"
element foo { attribute bar { xsd:integer } }'
      grammar = Rng.parse_rnc(rnc)
      xml = grammar.to_xml

      expect(xml).to include('type="integer"')
      expect(xml).to include('datatypeLibrary="http://www.w3.org/2001/XMLSchema-datatypes"')
    end
  end

  describe "combined declarations" do
    it "handles namespace and datatype together" do
      rnc = <<~RNC
        namespace eg = "http://example.com"
        datatypes xsd = "http://www.w3.org/2001/XMLSchema-datatypes"

        start = element eg:person {
          attribute age { xsd:integer }
        }
      RNC
      grammar = Rng.parse_rnc(rnc)
      expect(grammar).to be_a(Rng::Grammar)
      expect(grammar.start).not_to be_nil
    end

    it "generates complete RNG XML with multiple declarations" do
      rnc = <<~RNC
        namespace eg = "http://example.com"
        datatypes xsd = "http://www.w3.org/2001/XMLSchema-datatypes"

        start = element eg:person { empty }
      RNC
      grammar = Rng.parse_rnc(rnc)
      xml = grammar.to_xml

      expect(xml).to include('ns="http://example.com"')
      expect(xml).to include('datatypeLibrary="http://www.w3.org/2001/XMLSchema-datatypes"')
    end

    it "handles multiple prefixed namespaces" do
      rnc = <<~RNC
        namespace eg1 = "http://example.com/ns1"
        namespace eg2 = "http://example.com/ns2"

        start = element eg1:foo {
          element eg2:bar { empty }
        }
      RNC
      grammar = Rng.parse_rnc(rnc)
      xml = grammar.to_xml

      expect(xml).to include('ns="http://example.com/ns1"')
      expect(xml).to include('ns="http://example.com/ns2"')
    end
  end

  describe "edge cases" do
    it "handles empty namespace URI" do
      rnc = 'namespace local = ""
element local:foo { empty }'
      grammar = Rng.parse_rnc(rnc)
      xml = grammar.to_xml

      expect(xml).to include('ns=""')
    end

    it "handles schemas with only preamble" do
      rnc = <<~RNC
        namespace eg = "http://example.com"
        datatypes xsd = "http://www.w3.org/2001/XMLSchema-datatypes"

        element foo { empty }
      RNC
      grammar = Rng.parse_rnc(rnc)
      expect(grammar).to be_a(Rng::Grammar)
    end

    it "handles default namespace without elements using prefix" do
      rnc = 'default namespace = "http://example.com"
element foo { attribute bar { text } }'
      grammar = Rng.parse_rnc(rnc)
      xml = grammar.to_xml

      expect(xml).to include('ns="http://example.com"')
    end
  end
end
