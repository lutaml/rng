require "spec_helper"

RSpec.describe Rng::RncParser do
  let(:parser) { described_class.new }

  describe "#parse" do
    context "with a simple RNC schema" do
      let(:input) do
        <<~RNC
          element addressBook {
            element card {
              element name { text },
              element email { text }
            }*
          }
        RNC
      end

      it "correctly parses the schema" do
        result = parser.parse(input)
        expect(result).to be_a(Rng::Schema)
        expect(result.start.elements.first.name).to eq("addressBook")
        expect(result.start.elements.first.elements.first.name).to eq("card")
        expect(result.start.elements.first.elements.first.elements.map(&:name)).to eq(["name", "email"])
      end
    end

    context "with attributes" do
      let(:input) do
        <<~RNC
          element person {
            attribute id { text },
            element name { text }
          }
        RNC
      end

      it "correctly parses attributes" do
        result = parser.parse(input)
        expect(result.start.elements.first.name).to eq("person")
        expect(result.start.elements.first.elements.first).to be_a(Rng::Attribute)
        expect(result.start.elements.first.elements.first.name).to eq("id")
      end
    end

    context "with nested elements" do
      let(:input) do
        <<~RNC
          element root {
            element child1 {
              element grandchild { text }
            },
            element child2 { text }
          }
        RNC
      end

      it "correctly parses nested elements" do
        result = parser.parse(input)
        expect(result.start.elements.first.name).to eq("root")
        expect(result.start.elements.first.elements.map(&:name)).to eq(["child1", "child2"])
        expect(result.start.elements.first.elements.first.elements.first.name).to eq("grandchild")
      end
    end
  end
end
