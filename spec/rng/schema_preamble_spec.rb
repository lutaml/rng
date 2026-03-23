# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/rng/schema_preamble"

RSpec.describe Rng::SchemaPreamble do
  describe "#initialize" do
    it "creates an empty preamble" do
      preamble = described_class.new

      expect(preamble.namespaces).to be_empty
      expect(preamble.datatypes).to be_empty
      expect(preamble).to be_empty
    end
  end

  describe "#add_namespace" do
    it "adds namespace declarations" do
      preamble = described_class.new
      ns1 = Rng::NamespaceDeclaration.new(uri: "http://example.com",
                                          is_default: true)
      ns2 = Rng::NamespaceDeclaration.new(prefix: "eg", uri: "http://example.com/eg")

      preamble.add_namespace(ns1)
      preamble.add_namespace(ns2)

      expect(preamble.namespaces).to contain_exactly(ns1, ns2)
      expect(preamble).not_to be_empty
    end
  end

  describe "#add_datatype" do
    it "adds datatype declarations" do
      preamble = described_class.new
      dt = Rng::DatatypeDeclaration.new(
        prefix: "xsd",
        uri: "http://www.w3.org/2001/XMLSchema-datatypes",
      )

      preamble.add_datatype(dt)

      expect(preamble.datatypes).to contain_exactly(dt)
      expect(preamble).not_to be_empty
    end
  end

  describe "#default_namespace" do
    it "returns the default namespace URI" do
      preamble = described_class.new
      default_ns = Rng::NamespaceDeclaration.new(uri: "http://example.com",
                                                 is_default: true)
      other_ns = Rng::NamespaceDeclaration.new(prefix: "eg", uri: "http://example.com/eg")

      preamble.add_namespace(default_ns)
      preamble.add_namespace(other_ns)

      expect(preamble.default_namespace).to eq("http://example.com")
    end

    it "returns nil when there is no default namespace" do
      preamble = described_class.new
      ns = Rng::NamespaceDeclaration.new(prefix: "eg", uri: "http://example.com")

      preamble.add_namespace(ns)

      expect(preamble.default_namespace).to be_nil
    end
  end

  describe "#namespace_map" do
    it "returns a map of prefixed namespaces" do
      preamble = described_class.new
      ns1 = Rng::NamespaceDeclaration.new(prefix: "eg", uri: "http://example.com")
      ns2 = Rng::NamespaceDeclaration.new(prefix: "local", uri: "")
      default_ns = Rng::NamespaceDeclaration.new(uri: "http://default.com",
                                                 is_default: true)

      preamble.add_namespace(ns1)
      preamble.add_namespace(ns2)
      preamble.add_namespace(default_ns)

      map = preamble.namespace_map
      expect(map).to eq({
                          "eg" => "http://example.com",
                          "local" => "",
                        })
    end

    it "returns empty hash when there are no prefixed namespaces" do
      preamble = described_class.new
      default_ns = Rng::NamespaceDeclaration.new(uri: "http://example.com",
                                                 is_default: true)

      preamble.add_namespace(default_ns)

      expect(preamble.namespace_map).to eq({})
    end
  end

  describe "#datatype_map" do
    it "returns a map of datatype prefixes to URIs" do
      preamble = described_class.new
      dt1 = Rng::DatatypeDeclaration.new(prefix: "xsd", uri: "http://www.w3.org/2001/XMLSchema-datatypes")
      dt2 = Rng::DatatypeDeclaration.new(prefix: "custom", uri: "http://example.com/types")

      preamble.add_datatype(dt1)
      preamble.add_datatype(dt2)

      map = preamble.datatype_map
      expect(map).to eq({
                          "xsd" => "http://www.w3.org/2001/XMLSchema-datatypes",
                          "custom" => "http://example.com/types",
                        })
    end

    it "returns empty hash when there are no datatypes" do
      preamble = described_class.new
      expect(preamble.datatype_map).to eq({})
    end
  end

  describe "#empty?" do
    it "returns true when preamble has no declarations" do
      preamble = described_class.new
      expect(preamble).to be_empty
    end

    it "returns false when preamble has namespace declarations" do
      preamble = described_class.new
      ns = Rng::NamespaceDeclaration.new(uri: "http://example.com",
                                         is_default: true)
      preamble.add_namespace(ns)

      expect(preamble).not_to be_empty
    end

    it "returns false when preamble has datatype declarations" do
      preamble = described_class.new
      dt = Rng::DatatypeDeclaration.new(prefix: "xsd", uri: "http://www.w3.org/2001/XMLSchema-datatypes")
      preamble.add_datatype(dt)

      expect(preamble).not_to be_empty
    end
  end
end
