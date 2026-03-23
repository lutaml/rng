# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/rng/datatype_declaration"

RSpec.describe Rng::DatatypeDeclaration do
  describe "#initialize" do
    it "creates a datatype declaration with prefix and URI" do
      decl = described_class.new(
        prefix: "xsd",
        uri: "http://www.w3.org/2001/XMLSchema-datatypes",
      )

      expect(decl.prefix).to eq("xsd")
      expect(decl.uri).to eq("http://www.w3.org/2001/XMLSchema-datatypes")
    end

    it "creates a datatype declaration with custom prefix" do
      decl = described_class.new(
        prefix: "custom",
        uri: "http://example.com/datatypes",
      )

      expect(decl.prefix).to eq("custom")
      expect(decl.uri).to eq("http://example.com/datatypes")
    end
  end
end
