# frozen_string_literal: true

require 'spec_helper'
require 'rng'
require 'parslet'

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

    it 'parses an annotated attribute within a sequence' do
      rnc = 'start = element n { [ a:x = "1" ] attribute foo { text }, ' \
            'attribute bar { text } }'
      grammar = Rng.parse_rnc(rnc)
      attrs = grammar.start.first.element.attribute.map(&:attr_name)
      expect(attrs).to eq(%w[foo bar])
    end

    it 'leaves un-annotated content parsing unchanged' do
      rnc = 'start = element n { attribute foo { text } }'
      expect { Rng.parse_rnc(rnc) }.not_to raise_error
    end

    it 'does not let brackets inside an annotation string close it early' do
      rnc = 'start = element n { [ a:x = "a]b[c" ] attribute foo { text }, ' \
            'attribute bar { text } }'
      grammar = Rng.parse_rnc(rnc)
      attrs = grammar.start.first.element.attribute.map(&:attr_name)
      expect(attrs).to eq(%w[foo bar])
    end

    it 'ignores brackets inside a single-quoted annotation string' do
      rnc = "start = element n { [ a:x = 'a]b[c' ] attribute foo { text }, " \
            'attribute bar { text } }'
      grammar = Rng.parse_rnc(rnc)
      attrs = grammar.start.first.element.attribute.map(&:attr_name)
      expect(attrs).to eq(%w[foo bar])
    end

    it 'ignores brackets inside a triple-quoted annotation string' do
      rnc = 'start = element n { [ a:doc [ """multi]line[x""" ] ] ' \
            'attribute foo { text }, attribute bar { text } }'
      grammar = Rng.parse_rnc(rnc)
      attrs = grammar.start.first.element.attribute.map(&:attr_name)
      expect(attrs).to eq(%w[foo bar])
    end

    it 'drops an annotation before a non-leading definition without corrupting it' do
      rnc = "foo = element foo { text }\n" \
            "[ a:defaultValue = \"x\" ]\n" \
            "bar = element bar { text }\n" \
            'start = foo'
      grammar = Rng.parse_rnc(rnc)

      expect(grammar.define.map(&:name)).to contain_exactly('foo', 'bar')
    end

    it 'rejects a control character inside an annotation string, like a value string' do
      rnc = "start = element n { [ a:x = \"#{1.chr}\" ] " \
            'attribute foo { text } }'
      expect { Rng.parse_rnc(rnc) }.to raise_error(Parslet::ParseFailed)
    end
  end

  describe 'Sequence separators' do
    it 'rejects comma-less sequence items so they cannot swallow the next definition' do
      rnc = 'start = element n { attribute foo { text } attribute bar { text } }'
      expect { Rng.parse_rnc(rnc) }.to raise_error(Parslet::ParseFailed)
    end

    it 'parses comma-separated sequence items in element content' do
      rnc = 'start = element n { attribute foo { text }, attribute bar { text } }'
      grammar = Rng.parse_rnc(rnc)
      attrs = grammar.start.first.element.attribute.map(&:attr_name)
      expect(attrs).to eq(%w[foo bar])
    end
  end

  describe 'Non-leading start' do
    it 'produces a real <start> for a start = element after other defines' do
      rnc = "item = element item { text }\nstart = element root { item* }"
      grammar = Rng.parse_rnc(rnc)

      expect(grammar.start.first.element.attr_name).to eq('root')
      expect(grammar.define.map(&:name)).to eq(['item'])
    end

    it 'produces a real <start> for a non-leading start = ref' do
      rnc = "library = element library { text }\nstart = library"
      grammar = Rng.parse_rnc(rnc)

      expect(grammar.start.first.ref.name).to eq('library')
      expect(grammar.define.map(&:name)).not_to include('start')
    end

    it 'collects multiple start |= definitions as combining starts' do
      rnc = "a = element a { empty }\nb = element b { empty }\n" \
            "start |= a\nstart |= b"
      grammar = Rng.parse_rnc(rnc)

      expect(grammar.start.map(&:combine)).to eq(%w[choice choice])
      expect(grammar.start.map { |s| s.ref.name }).to contain_exactly('a', 'b')
    end

    it 'maps start &= to interleave-combining starts' do
      rnc = "a = element a { empty }\nb = element b { empty }\n" \
            "start &= a\nstart &= b"
      grammar = Rng.parse_rnc(rnc)

      expect(grammar.start.map(&:combine)).to eq(%w[interleave interleave])
    end

    it 'keeps an escaped \\start as a define, not the grammar start' do
      rnc = "x = element x { text }\n\\start = element a { text }\nstart = x"
      grammar = Rng.parse_rnc(rnc)

      expect(grammar.define.map(&:name)).to include('start')
      expect(grammar.start.first.ref.name).to eq('x')
    end
  end
end
