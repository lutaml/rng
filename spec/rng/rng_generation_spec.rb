# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'RNG Generation' do
  describe 'Grammar.to_xml()' do
    context 'with simple manually constructed schema' do
      it 'generates valid RNG XML from a Grammar object' do
        # Create simple grammar manually
        grammar = Rng::Grammar.new
        grammar.datatypeLibrary = 'http://www.w3.org/2001/XMLSchema-datatypes'

        # Create start with element
        start = Rng::Start.new
        element = Rng::Element.new
        element.attr_name = 'root'
        text = Rng::Text.new
        element.text = text
        start.element = element
        grammar.start = [start]

        # Generate XML (note: to_xml() doesn't include XML declaration)
        xml = grammar.to_xml

        # Verify structure
        expect(xml).to include('<grammar')
        expect(xml).to include('xmlns="http://relaxng.org/ns/structure/1.0"')
        expect(xml).to include('<start')
        expect(xml).to include('<element name="root"')
        expect(xml).to include('<text')
        expect(xml).to include('</element>')
        expect(xml).to include('</start>')
        expect(xml).to include('</grammar>')
      end

      it 'handles namespace attributes correctly' do
        grammar = Rng::Grammar.new
        grammar.ns = 'http://example.com/ns'

        xml = grammar.to_xml
        expect(xml).to include('ns="http://example.com/ns"')
      end

      it 'handles datatype library attributes correctly' do
        grammar = Rng::Grammar.new
        grammar.datatypeLibrary = 'http://www.w3.org/2001/XMLSchema-datatypes'

        xml = grammar.to_xml
        expect(xml).to include('datatypeLibrary="http://www.w3.org/2001/XMLSchema-datatypes"')
      end
    end

    context 'with parsed RNG schema' do
      let(:address_book_rng) { File.read('spec/fixtures/rng/address_book.rng') }

      it 'regenerates XML from parsed RNG' do
        parsed = Rng.parse(address_book_rng)
        regenerated = parsed.to_xml

        # Verify it's valid XML (note: to_xml() doesn't include XML declaration)
        expect(regenerated).to include('<grammar')
        expect(regenerated).to include('xmlns="http://relaxng.org/ns/structure/1.0"')

        # Verify structure
        expect(regenerated).to include('<start')
        expect(regenerated).to include('<element name="addressBook"')
        expect(regenerated).to include('name="cardContent"')
      end

      it 'maintains semantic equivalence (round-trip)' do
        parsed = Rng.parse(address_book_rng)
        regenerated = parsed.to_xml
        reparsed = Rng.parse(regenerated)

        # Verify key structure is maintained
        expect(reparsed.start.first.element.attr_name).to eq('addressBook')
        expect(reparsed.define.first.name).to eq('cardContent')
      end
    end

    context 'with parsed RNC schema' do
      let(:address_book_rnc) { File.read('spec/fixtures/rnc/address_book.rnc') }

      it 'generates RNG XML from parsed RNC' do
        parsed = Rng.parse_rnc(address_book_rnc)
        xml = parsed.to_xml

        # Verify it's valid RNG XML (note: to_xml() doesn't include XML declaration)
        expect(xml).to include('<grammar')
        expect(xml).to include('xmlns="http://relaxng.org/ns/structure/1.0"')
        expect(xml).to include('<start')
        expect(xml).to include('<element name="addressBook"')
        # NOTE: Current RNC parser doesn't populate Grammar.define array
        # It inlines pattern definitions instead of creating separate <define> elements
        expect(xml).to include('<ref name="cardContent"')
      end

      it 'produces semantically valid schema' do
        parsed = Rng.parse_rnc(address_book_rnc)
        xml = parsed.to_xml
        reparsed = Rng.parse(xml)

        # Verify structure
        expect(reparsed).to be_a(Rng::Grammar)
        expect(reparsed.start.first.element.attr_name).to eq('addressBook')
      end
    end

    context 'with special attribute values' do
      it 'handles nil namespace (attribute omitted)' do
        grammar = Rng::Grammar.new
        grammar.ns = nil

        xml = grammar.to_xml
        # nil values cause the attribute to be omitted
        expect(xml).not_to match(/\bns="/)
      end

      it 'handles nil datatype library (attribute omitted)' do
        grammar = Rng::Grammar.new
        grammar.datatypeLibrary = nil

        xml = grammar.to_xml
        # nil values cause the attribute to be omitted
        expect(xml).not_to include('datatypeLibrary=')
      end

      it 'handles empty strings correctly' do
        grammar = Rng::Grammar.new
        grammar.ns = ''

        xml = grammar.to_xml
        expect(xml).to include('ns=""')
      end
    end

    context 'with complex patterns' do
      it 'handles choice patterns' do
        grammar = Rng::Grammar.new
        start = Rng::Start.new
        choice = Rng::Choice.new

        elem1 = Rng::Element.new
        elem1.attr_name = 'option1'
        elem1.text = Rng::Text.new

        elem2 = Rng::Element.new
        elem2.attr_name = 'option2'
        elem2.text = Rng::Text.new

        choice.element = [elem1, elem2]
        start.choice = choice
        grammar.start = [start]

        xml = grammar.to_xml
        expect(xml).to include('<choice>')
        expect(xml).to include('<element name="option1">')
        expect(xml).to include('<element name="option2">')
      end

      it 'handles group patterns' do
        grammar = Rng::Grammar.new
        start = Rng::Start.new
        group = Rng::Group.new

        elem1 = Rng::Element.new
        elem1.attr_name = 'first'
        elem1.text = Rng::Text.new

        elem2 = Rng::Element.new
        elem2.attr_name = 'second'
        elem2.text = Rng::Text.new

        group.element = [elem1, elem2]
        start.group = group
        grammar.start = [start]

        xml = grammar.to_xml
        expect(xml).to include('<group>')
        expect(xml).to include('<element name="first">')
        expect(xml).to include('<element name="second">')
      end

      it 'handles optional patterns' do
        grammar = Rng::Grammar.new
        start = Rng::Start.new
        optional = Rng::Optional.new

        elem = Rng::Element.new
        elem.attr_name = 'optional'
        elem.text = Rng::Text.new
        optional.element = elem

        start.optional = optional
        grammar.start = [start]

        xml = grammar.to_xml
        expect(xml).to include('<optional>')
        expect(xml).to include('<element name="optional">')
      end

      it 'handles zeroOrMore patterns' do
        grammar = Rng::Grammar.new
        start = Rng::Start.new
        zero_or_more = Rng::ZeroOrMore.new

        elem = Rng::Element.new
        elem.attr_name = 'item'
        elem.text = Rng::Text.new
        zero_or_more.element = elem

        start.zeroOrMore = zero_or_more
        grammar.start = [start]

        xml = grammar.to_xml
        expect(xml).to include('<zeroOrMore>')
        expect(xml).to include('<element name="item">')
      end

      it 'handles oneOrMore patterns' do
        grammar = Rng::Grammar.new
        start = Rng::Start.new
        one_or_more = Rng::OneOrMore.new

        elem = Rng::Element.new
        elem.attr_name = 'item'
        elem.text = Rng::Text.new
        one_or_more.element = elem

        start.oneOrMore = [one_or_more]
        grammar.start = [start]

        xml = grammar.to_xml
        expect(xml).to include('<oneOrMore>')
        expect(xml).to include('<element name="item">')
      end
    end

    context 'with references' do
      it 'handles ref patterns' do
        grammar = Rng::Grammar.new

        # Define pattern
        define = Rng::Define.new
        define.name = 'myPattern'
        elem = Rng::Element.new
        elem.attr_name = 'test'
        elem.text = Rng::Text.new
        define.element = elem
        grammar.define = [define]

        # Reference pattern
        start = Rng::Start.new
        ref = Rng::Ref.new
        ref.name = 'myPattern'
        start.ref = ref
        grammar.start = [start]

        xml = grammar.to_xml
        expect(xml).to match(/<define[^>]+name="myPattern"/)
        expect(xml).to include('<ref name="myPattern"')
      end
    end

    context 'with attributes' do
      it 'handles attribute patterns' do
        grammar = Rng::Grammar.new
        start = Rng::Start.new

        elem = Rng::Element.new
        elem.attr_name = 'root'

        attr = Rng::Attribute.new
        attr.attr_name = 'id'
        attr.text = Rng::Text.new
        elem.attribute = attr

        start.element = elem
        grammar.start = [start]

        xml = grammar.to_xml
        expect(xml).to include('<element name="root"')
        expect(xml).to include('<attribute name="id"')
        expect(xml).to include('<text/')
      end
    end
  end
end
