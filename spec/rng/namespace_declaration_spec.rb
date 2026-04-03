# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/rng/namespace_declaration'

RSpec.describe Rng::NamespaceDeclaration do
  describe '#initialize' do
    it 'creates a default namespace without prefix' do
      decl = described_class.new(uri: 'http://example.com', is_default: true)

      expect(decl.uri).to eq('http://example.com')
      expect(decl.prefix).to be_nil
      expect(decl).to be_default
      expect(decl).not_to be_prefixed
    end

    it 'creates a default namespace with prefix' do
      decl = described_class.new(prefix: 'rng',
                                 uri: 'http://relaxng.org/ns/structure/1.0', is_default: true)

      expect(decl.uri).to eq('http://relaxng.org/ns/structure/1.0')
      expect(decl.prefix).to eq('rng')
      expect(decl).to be_default
      expect(decl).to be_prefixed
    end

    it 'creates a prefixed namespace' do
      decl = described_class.new(prefix: 'eg', uri: 'http://example.com')

      expect(decl.uri).to eq('http://example.com')
      expect(decl.prefix).to eq('eg')
      expect(decl).not_to be_default
      expect(decl).to be_prefixed
    end
  end

  describe '#default?' do
    it 'returns true for default namespace' do
      decl = described_class.new(uri: 'http://example.com', is_default: true)
      expect(decl).to be_default
    end

    it 'returns false for non-default namespace' do
      decl = described_class.new(prefix: 'eg', uri: 'http://example.com')
      expect(decl).not_to be_default
    end
  end

  describe '#prefixed?' do
    it 'returns true when prefix is present' do
      decl = described_class.new(prefix: 'eg', uri: 'http://example.com')
      expect(decl).to be_prefixed
    end

    it 'returns false when prefix is nil' do
      decl = described_class.new(uri: 'http://example.com', is_default: true)
      expect(decl).not_to be_prefixed
    end
  end
end
