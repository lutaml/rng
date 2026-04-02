# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rng::Div do
  describe "Div pattern parsing and generation" do
    let(:rng_with_div) do
      <<~RNG
        <?xml version="1.0" encoding="UTF-8"?>
        <grammar xmlns="http://relaxng.org/ns/structure/1.0">
          <start>
            <element name="doc">
              <text/>
            </element>
          </start>
        #{'  '}
          <div>
            <define name="section">
              <element name="section">
                <ref name="title"/>
                <ref name="content"/>
              </element>
            </define>
        #{'    '}
            <define name="title">
              <element name="title">
                <text/>
              </element>
            </define>
          </div>
        #{'  '}
          <div>
            <define name="content">
              <element name="content">
                <text/>
              </element>
            </define>
          </div>
        </grammar>
      RNG
    end

    it "parses RNG with div blocks" do
      parsed = Rng::Grammar.from_xml(rng_with_div)

      expect(parsed).to be_a(Rng::Grammar)
      expect(parsed.div).not_to be_empty
      expect(parsed.div.length).to eq(2)

      # First div should have 2 defines
      first_div = parsed.div[0]
      expect(first_div).to be_a(described_class)
      expect(first_div.define.length).to eq(2)
      expect(first_div.define[0].name).to eq("section")
      expect(first_div.define[1].name).to eq("title")

      # Second div should have 1 define
      second_div = parsed.div[1]
      expect(second_div.define.length).to eq(1)
      expect(second_div.define[0].name).to eq("content")
    end

    it "correctly round-trips RNG with div blocks" do
      parsed = Rng::Grammar.from_xml(rng_with_div)
      regenerated = parsed.to_xml

      expect(regenerated).to be_xml_equivalent_to(rng_with_div)
    end

    it "generates RNC with div blocks" do
      parsed = Rng::Grammar.from_xml(rng_with_div)
      rnc = Rng.to_rnc(parsed)

      expect(rnc).to include("div {")
      expect(rnc).to include("section =")
      expect(rnc).to include("title =")
      expect(rnc).to include("content =")
    end
  end

  describe "Nested div patterns" do
    let(:rng_with_nested_div) do
      <<~RNG
        <?xml version="1.0" encoding="UTF-8"?>
        <grammar xmlns="http://relaxng.org/ns/structure/1.0">
          <start>
            <element name="doc">
              <text/>
            </element>
          </start>
        #{'  '}
          <div>
            <define name="outer">
              <element name="outer">
                <text/>
              </element>
            </define>
        #{'    '}
            <div>
              <define name="inner">
                <element name="inner">
                  <text/>
                </element>
              </define>
            </div>
          </div>
        </grammar>
      RNG
    end

    it "parses nested div blocks" do
      parsed = Rng::Grammar.from_xml(rng_with_nested_div)

      expect(parsed.div.length).to eq(1)

      outer_div = parsed.div[0]
      expect(outer_div.define.length).to eq(1)
      expect(outer_div.define[0].name).to eq("outer")

      # Check nested div
      expect(outer_div.div.length).to eq(1)
      inner_div = outer_div.div[0]
      expect(inner_div.define.length).to eq(1)
      expect(inner_div.define[0].name).to eq("inner")
    end

    it "correctly round-trips nested div blocks" do
      parsed = Rng::Grammar.from_xml(rng_with_nested_div)
      regenerated = parsed.to_xml

      expect(regenerated).to be_xml_equivalent_to(rng_with_nested_div)
    end
  end

  describe "Div with start pattern" do
    let(:rng_with_div_start) do
      <<~RNG
        <?xml version="1.0" encoding="UTF-8"?>
        <grammar xmlns="http://relaxng.org/ns/structure/1.0">
          <div>
            <start>
              <element name="doc">
                <text/>
              </element>
            </start>
        #{'    '}
            <define name="helper">
              <element name="helper">
                <text/>
              </element>
            </define>
          </div>
        </grammar>
      RNG
    end

    it "parses div with start pattern" do
      parsed = Rng::Grammar.from_xml(rng_with_div_start)

      expect(parsed.div.length).to eq(1)

      div = parsed.div[0]
      expect(div.start).not_to be_empty
      expect(div.start[0].element.attr_name).to eq("doc")
      expect(div.define.length).to eq(1)
      expect(div.define[0].name).to eq("helper")
    end
  end

  describe "Div attributes" do
    let(:rng_with_div_attrs) do
      <<~RNG
        <?xml version="1.0" encoding="UTF-8"?>
        <grammar xmlns="http://relaxng.org/ns/structure/1.0">
          <start>
            <element name="doc">
              <text/>
            </element>
          </start>
        #{'  '}
          <div id="section-div" ns="http://example.com/ns">
            <define name="section">
              <element name="section">
                <text/>
              </element>
            </define>
          </div>
        </grammar>
      RNG
    end

    it "parses div with id and ns attributes" do
      parsed = Rng::Grammar.from_xml(rng_with_div_attrs)

      div = parsed.div[0]
      expect(div.id).to eq("section-div")
      expect(div.ns).to eq("http://example.com/ns")
    end

    it "correctly round-trips div with attributes" do
      parsed = Rng::Grammar.from_xml(rng_with_div_attrs)
      regenerated = parsed.to_xml

      expect(regenerated).to be_xml_equivalent_to(rng_with_div_attrs)
    end
  end
end
