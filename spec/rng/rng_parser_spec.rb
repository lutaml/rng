require "spec_helper"

RSpec.describe Rng::RngParser do
  let(:parser) { described_class.new }

  describe "#parse" do
    context "with a simple RNG schema" do
      let(:input) do
        <<~RNG
          <grammar xmlns="http://relaxng.org/ns/structure/1.0">
            <start>
              <element name="addressBook">
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
            </start>
          </grammar>
        RNG
      end

      it "correctly parses the schema" do
        result = parser.parse(input)
        expect(result).to be_a(Rng::Schema)
        expect(result.start.elements.first.name).to eq("addressBook")
        expect(result.start.elements.first.zero_or_more.first.name).to eq("card")
        expect(result.start.elements.first.zero_or_more.first.elements.map(&:name)).to eq(["name", "email"])
      end
    end

    context "with a complex RNG schema" do
      let(:input) do
        <<~RNG
          <grammar xmlns="http://relaxng.org/ns/structure/1.0">
            <start>
              <ref name="addressBook"/>
            </start>
            <define name="addressBook">
              <element name="addressBook">
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
            </define>
          </grammar>
        RNG
      end

      it "correctly parses the schema" do
        result = parser.parse(input)
        expect(result).to be_a(Rng::Schema)
        expect(result.start.ref).to eq("addressBook")
        expect(result.define.first.name).to eq("addressBook")
        expect(result.define.first.elements.first.name).to eq("addressBook")
      end
    end

    context "with attributes" do
      let(:input) do
        <<~RNG
          <grammar xmlns="http://relaxng.org/ns/structure/1.0">
            <start>
              <element name="person">
                <attribute name="id">
                  <data type="ID"/>
                </attribute>
                <element name="name">
                  <text/>
                </element>
              </element>
            </start>
          </grammar>
        RNG
      end

      it "correctly parses attributes" do
        result = parser.parse(input)
        expect(result.start.elements.first.attributes.first.name).to eq("id")
        expect(result.start.elements.first.attributes.first.type).to eq(["ID"])
      end
    end
  end
end
