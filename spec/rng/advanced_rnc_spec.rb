# frozen_string_literal: true

require 'spec_helper'
require 'rng'

RSpec.describe 'Advanced RNC features' do
  describe 'Name wildcards' do
    context 'anyName in attributes' do
      it 'parses wildcard attribute without except' do
        rnc = 'start = element foo { attribute * { text } }'
        expect { Rng.parse_rnc(rnc) }.not_to raise_error
      end

      it 'parses wildcard attribute with except clause' do
        rnc = 'start = element foo { attribute * - bar { text } }'
        expect { Rng.parse_rnc(rnc) }.not_to raise_error
      end
    end

    context 'anyName in elements' do
      it 'parses wildcard element without except' do
        rnc = 'start = element * { text }'
        expect { Rng.parse_rnc(rnc) }.not_to raise_error
      end
    end

    context 'nsName wildcards' do
      it 'parses namespace wildcard in attributes' do
        rnc = 'start = element foo { attribute xml:* { text } }'
        expect { Rng.parse_rnc(rnc) }.not_to raise_error
      end

      it 'parses namespace wildcard with except' do
        rnc = 'start = element foo { attribute ns:* - ns:bar { text } }'
        expect { Rng.parse_rnc(rnc) }.not_to raise_error
      end
    end
  end

  describe 'Augmentation operators' do
    it 'parses choice augmentation (|=)' do
      rnc = <<~RNC
        start = foo
        foo = bar
        foo |= baz
      RNC
      schema = Rng.parse_rnc(rnc)

      # Should have two define elements with combine="choice"
      defines = schema.define.select { |d| d.name == 'foo' }
      expect(defines.length).to eq(2)
      expect(defines[1].combine).to eq('choice')
    end

    it 'parses interleave augmentation (&=)' do
      rnc = <<~RNC
        start = foo
        foo = bar
        foo &= baz
      RNC
      schema = Rng.parse_rnc(rnc)

      defines = schema.define.select { |d| d.name == 'foo' }
      expect(defines.length).to eq(2)
      expect(defines[1].combine).to eq('interleave')
    end
  end

  describe 'List patterns' do
    it 'parses simple list pattern' do
      rnc = 'start = element foo { list { xsd:token+ } }'
      expect { Rng.parse_rnc(rnc) }.not_to raise_error
    end

    it 'parses list with text' do
      rnc = 'start = element foo { list { text } }'
      expect { Rng.parse_rnc(rnc) }.not_to raise_error
    end
  end

  describe 'Parent references' do
    it 'parses parent reference' do
      rnc = 'start = parent start'
      expect { Rng.parse_rnc(rnc) }.not_to raise_error
    end
  end

  describe 'External references' do
    it 'parses external reference' do
      rnc = 'start = external "common.rng"'
      expect { Rng.parse_rnc(rnc) }.not_to raise_error
    end
  end

  describe 'notAllowed pattern' do
    it 'parses notAllowed' do
      rnc = 'start = element foo { notAllowed }'
      expect { Rng.parse_rnc(rnc) }.not_to raise_error
    end
  end

  describe 'Content-position annotations' do
    it 'parses a bracket annotation before an attribute in content' do
      rnc = 'start = element n { [ a:defaultValue = "x" ] attribute foo { text } }'
      expect { Rng.parse_rnc(rnc) }.not_to raise_error
    end

    it 'parses a bracket annotation before a nested element in content' do
      rnc = 'start = element n { [ a:documentation [ "hi" ] ] element c { text } }'
      expect { Rng.parse_rnc(rnc) }.not_to raise_error
    end

    it 'parses a bracket annotation before a ref in content' do
      rnc = <<~RNC
        c = element c { text }
        start = element n { [ a:defaultValue = "x" ] c }
      RNC
      expect { Rng.parse_rnc(rnc) }.not_to raise_error
    end

    it 'leaves un-annotated content parsing unchanged' do
      rnc = 'start = element n { attribute foo { text } }'
      expect { Rng.parse_rnc(rnc) }.not_to raise_error
    end
  end
end
