require "spec_helper"

RSpec.describe Rng::Schema do
  let(:rng_parser) { Rng::RngParser.new }
  let(:rnc_parser) { Rng::RncParser.new }
  let(:builder) { Rng::Builder.new }

  describe "RNG parsing and building" do
    let(:rng_input) do
      <<~RNG
        <element name="addressBook" xmlns="http://relaxng.org/ns/structure/1.0">
          <zeroOrMore>
            <element name="card">
              <element name="name">
                <text/>
              </element>
              <element name="email">
                <text/>
              </element>
              <optional>
                <element name="note">
                  <text/>
                </element>
              </optional>
            </element>
          </zeroOrMore>
        </element>
      RNG
    end

    it "correctly parses and rebuilds RNG" do
      parsed = rng_parser.parse(rng_input)
      rebuilt = builder.build(parsed, format: :rng)
      expect(rebuilt.gsub(/\s+/, "")).to eq(rng_input.gsub(/\s+/, ""))
    end
  end

  describe "RNC parsing and building" do
    let(:rnc_input) do
      <<~RNC
        element addressBook {
          element card {
            element name { text },
            element email { text },
            element note { text }?
          }*
        }
      RNC
    end

    it "correctly parses and rebuilds RNC" do
      parsed = rnc_parser.parse(rnc_input)
      rebuilt = builder.build(parsed, format: :rnc)
      expect(rebuilt.gsub(/\s+/, "")).to eq(rnc_input.gsub(/\s+/, ""))
    end
  end

  describe "RNG to RNC conversion" do
    let(:rng_input) do
      <<~RNG
        <element name="addressBook" xmlns="http://relaxng.org/ns/structure/1.0">
          <zeroOrMore>
            <element name="card">
              <element name="name">
                <text/>
              </element>
              <element name="email">
                <text/>
              </element>
            </element>
          </zeroOrMore>
        </element>
      RNG
    end

    let(:expected_rnc) do
      <<~RNC
        element addressBook {
          element card {
            element name { text },
            element email { text }
          }*
        }
      RNC
    end

    it "correctly converts RNG to RNC" do
      parsed = rng_parser.parse(rng_input)
      rnc = builder.build(parsed, format: :rnc)
      expect(rnc.gsub(/\s+/, "")).to eq(expected_rnc.gsub(/\s+/, ""))
    end
  end

  describe "RNC to RNG conversion" do
    let(:rnc_input) do
      <<~RNC
        element addressBook {
          element card {
            element name { text },
            element email { text }
          }*
        }
      RNC
    end

    let(:expected_rng) do
      <<~RNG
        <element name="addressBook" xmlns="http://relaxng.org/ns/structure/1.0">
          <zeroOrMore>
            <element name="card">
              <element name="name">
                <text/>
              </element>
              <element name="email">
                <text/>
              </element>
            </element>
          </zeroOrMore>
        </element>
      RNG
    end

    it "correctly converts RNC to RNG" do
      parsed = rnc_parser.parse(rnc_input)
      rng = builder.build(parsed, format: :rng)
      expect(rng.gsub(/\s+/, "")).to eq(expected_rng.gsub(/\s+/, ""))
    end
  end

  describe "Complex schema parsing and building" do
    let(:complex_rng_input) do
      <<~RNG
        <grammar xmlns="http://relaxng.org/ns/structure/1.0">
          <start>
            <ref name="addressBook"/>
          </start>

          <define name="addressBook">
            <element name="addressBook">
              <zeroOrMore>
                <ref name="card"/>
              </zeroOrMore>
            </element>
          </define>

          <define name="card">
            <element name="card">
              <ref name="name"/>
              <ref name="email"/>
              <optional>
                <ref name="note"/>
              </optional>
            </element>
          </define>

          <define name="name">
            <element name="name">
              <text/>
            </element>
          </define>

          <define name="email">
            <element name="email">
              <text/>
            </element>
          </define>

          <define name="note">
            <element name="note">
              <text/>
            </element>
          </define>
        </grammar>
      RNG
    end

    it "correctly parses and rebuilds complex RNG" do
      parsed = rng_parser.parse(complex_rng_input)
      rebuilt = builder.build(parsed, format: :rng)
      expect(rebuilt.gsub(/\s+/, "")).to eq(complex_rng_input.gsub(/\s+/, ""))
    end

    it "correctly converts complex RNG to RNC" do
      parsed = rng_parser.parse(complex_rng_input)
      rnc = builder.build(parsed, format: :rnc)
      reparsed = rnc_parser.parse(rnc)
      rng_again = builder.build(reparsed, format: :rng)
      expect(rng_again.gsub(/\s+/, "")).to eq(complex_rng_input.gsub(/\s+/, ""))
    end
  end
end
