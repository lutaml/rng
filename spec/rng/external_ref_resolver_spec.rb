# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rng::ExternalRefResolver do
  describe '#resolve' do
    context 'with include directives' do
      let(:include_main) { File.read('spec/fixtures/external/include_main.rng') }
      let(:include_lib) { File.read('spec/fixtures/external/include_lib.rng') }

      it 'resolves include href and merges content' do
        grammar = Rng::Grammar.from_xml(include_main)
        resolved = described_class.new(grammar, location: 'spec/fixtures/external/include_main.rng').resolve

        expect(resolved.start).not_to be_nil
        expect(resolved.start.first.element.attr_name).to eq('foo')
      end

      it 'produces correct XML output after resolution' do
        grammar = Rng::Grammar.from_xml(include_main)
        resolved = described_class.new(grammar, location: 'spec/fixtures/external/include_main.rng').resolve

        xml = resolved.to_xml
        expect(xml).to include('<element name="foo">')
        expect(xml).to include('<empty/>')
        expect(xml).not_to include('<include')
      end
    end

    context 'with externalRef directives' do
      let(:external_ref_main) { File.read('spec/fixtures/external/external_ref_main.rng') }

      it 'resolves externalRef href and replaces with content' do
        grammar = Rng::Grammar.from_xml(external_ref_main)
        resolved = described_class.new(grammar, location: 'spec/fixtures/external/external_ref_main.rng').resolve

        # The externalRef should be replaced with the content from external_ref_lib
        xml = resolved.to_xml
        expect(xml).to include('<element name="bar">')
        expect(xml).to include('<empty/>')
        expect(xml).not_to include('<externalRef')
      end
    end

    context 'with nested include chain' do
      let(:nested_chain) { File.read('spec/fixtures/external/nested_chain.rng') }

      it 'resolves multiple levels of includes' do
        grammar = Rng::Grammar.from_xml(nested_chain)
        resolved = described_class.new(grammar, location: 'spec/fixtures/external/nested_chain.rng').resolve

        # nested_chain includes nested_mid, which includes nested_leaf
        # The final result should have the start pattern from nested_leaf
        xml = resolved.to_xml
        expect(xml).to include('<element name="z">')
      end
    end

    context 'with externalRef in group' do
      let(:circular_main) { File.read('spec/fixtures/external/circular_main.rng') }

      it 'resolves externalRef within group element' do
        grammar = Rng::Grammar.from_xml(circular_main)
        resolved = described_class.new(grammar, location: 'spec/fixtures/external/circular_main.rng').resolve

        xml = resolved.to_xml
        expect(xml).to include('<element name="b">')
        expect(xml).not_to include('<externalRef')
      end
    end

    context 'with interleaved children reached through an include' do
      let(:order_main) { File.read('spec/fixtures/external/order_main.rng') }

      it 'preserves element_order through external ref resolution' do
        grammar = Rng::Grammar.from_xml(order_main)
        resolved = described_class.new(grammar, location: 'spec/fixtures/external/order_main.rng').resolve

        xml = resolved.to_xml
        expect(xml.index('first')).to be < xml.index('mid')
        expect(xml.index('mid')).to be < xml.index('last')

        root = resolved.start.first.element
        expect(root.instance_variable_get(:@element_order)).not_to be_nil
      end
    end

    context 'with non-existent external file' do
      it 'does not raise error but warns when external file not found' do
        # Create a grammar with a non-existent include
        grammar = Rng::Grammar.from_xml('<grammar xmlns="http://relaxng.org/ns/structure/1.0"><include href="nonexistent.rng"/></grammar>')
        resolver = described_class.new(grammar, location: '/tmp/test.rng')

        # Without verbose mode, errors are swallowed silently
        expect { resolver.resolve }.not_to raise_error
      end
    end

    context 'with verbose mode' do
      it 'prints warning when external file not found' do
        grammar = Rng::Grammar.from_xml('<grammar xmlns="http://relaxng.org/ns/structure/1.0"><include href="nonexistent.rng"/></grammar>')
        resolver = described_class.new(grammar, location: '/tmp/test.rng')

        expect do
          ENV['RNG_VERBOSE'] = '1'
          resolver.resolve
        end.to output(/Warning: Failed to resolve include/).to_stderr
      end
    end
  end

  describe 'via Rng.parse' do
    it 'accepts resolve_external: true option' do
      main_rng = File.read('spec/fixtures/external/external_ref_main.rng')
      resolved = Rng.parse(main_rng, location: 'spec/fixtures/external/external_ref_main.rng', resolve_external: true)

      xml = resolved.to_xml
      expect(xml).to include('<element name="bar">')
      expect(xml).not_to include('<externalRef')
    end

    it 'does not resolve by default' do
      main_rng = File.read('spec/fixtures/external/external_ref_main.rng')
      grammar = Rng.parse(main_rng)

      # Without resolve_external, the grammar is returned as-is
      expect(grammar).to be_a(Rng::Grammar)
    end

    it 'warns about unresolved external references when not resolving' do
      main_rng = File.read('spec/fixtures/external/include_main.rng')
      grammar = Rng.parse(main_rng)

      expect(grammar.warnings).to include(a_string_matching(/include_lib\.rng/))
    end
  end

  describe Rng::ExternalRefResolver::ExternalRefResolutionError do
    it 'stores href and cause' do
      error = described_class.new('Test error', href: 'test.rng', cause: :circular)
      expect(error.href).to eq('test.rng')
      expect(error.cause).to eq(:circular)
    end
  end
end
