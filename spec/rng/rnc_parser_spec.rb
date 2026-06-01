# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rng::RncParser do
  describe '#parse' do
    context 'with a simple RNC schema' do
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

      it 'correctly parses the schema' do
        result = described_class.parse(input)
        expect(result).to be_a(Rng::Grammar)
        expect(result.start.first.element.attr_name).to eq('addressBook')
      end
    end

    context 'with attributes' do
      let(:input) do
        <<~RNC
          element person {
            attribute id { text },
            element name { text }
          }
        RNC
      end

      it 'correctly parses attributes' do
        result = described_class.parse(input)
        expect(result.start.first.element.attr_name).to eq('person')
      end
    end

    context 'with nested elements' do
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

      it 'correctly parses nested elements' do
        result = described_class.parse(input)
        expect(result.start.first.element.attr_name).to eq('root')
      end
    end
  end

  describe '#to_rnc' do
    context 'with address_book.rnc' do
      let(:rnc_input) { File.read('spec/fixtures/rnc/address_book.rnc') }

      it 'round-trips successfully' do
        # Parse RNC to Grammar
        grammar1 = described_class.parse(rnc_input)

        # Generate RNC from Grammar
        rnc_output = described_class.to_rnc(grammar1)

        # Parse generated RNC back to Grammar
        grammar2 = described_class.parse(rnc_output)

        # Compare key properties
        expect(grammar2.start.first.element.name).to eq(grammar1.start.first.element.name)
        expect(grammar2.define.map(&:name)).to eq(grammar1.define.map(&:name))
      end
    end

    context 'with value literals' do
      let(:input) do
        <<~RNC
          start = element doc {
            attribute version { "1.0" }
          }
        RNC
      end

      it 'generates value literals correctly' do
        grammar = described_class.parse(input)
        rnc = described_class.to_rnc(grammar)

        expect(rnc).to include('"1.0"')
        expect(rnc).to include('attribute version')
      end
    end

    context 'with choice of values' do
      let(:input) do
        <<~RNC
          start = element admonition {
            attribute type { "note" | "warning" | "tip" }
          }
        RNC
      end

      it 'generates choice of values correctly' do
        grammar = described_class.parse(input)
        rnc = described_class.to_rnc(grammar)

        expect(rnc).to include('"note"')
        expect(rnc).to include('"warning"')
        expect(rnc).to include('"tip"')
        expect(rnc).to include('|')
      end
    end

    context 'with namespace declaration' do
      let(:input) do
        <<~RNC
          default namespace = "http://example.org/ns"

          start = element root { text }
        RNC
      end

      it 'generates namespace declaration' do
        grammar = described_class.parse(input)
        rnc = described_class.to_rnc(grammar)

        expect(rnc).to include('default namespace = "http://example.org/ns"')
      end
    end

    context 'with mixed content' do
      let(:input) do
        <<~RNC
          start = element para {
            mixed {
              element emphasis { text }*
            }
          }
        RNC
      end

      it 'generates mixed content correctly' do
        grammar = described_class.parse(input)
        rnc = described_class.to_rnc(grammar)

        expect(rnc).to include('mixed {')
        expect(rnc).to include('element emphasis')
      end
    end

    context 'with datatype library' do
      it 'generates datatype library declaration' do
        # Create a Grammar object directly with datatype library
        grammar = Rng::Grammar.new
        grammar.datatypeLibrary = 'http://www.w3.org/2001/XMLSchema-datatypes'

        # Create a simple start pattern
        start = Rng::Start.new
        element = Rng::Element.new
        element.attr_name = 'person'

        attribute = Rng::Attribute.new
        attribute.attr_name = 'id'

        data = Rng::Data.new
        data.type = 'ID'
        attribute.data = data

        element.attribute = attribute
        start.element = element
        grammar.start = [start]

        rnc = described_class.to_rnc(grammar)

        expect(rnc).to include('datatypes xsd')
        expect(rnc).to include('xsd:ID')
      end
    end

    context 'with occurrence markers on bare ref patterns' do
      def build_rng(form)
        rnc = "start = element root { #{form} }\nitem = element item { text }\n"
        tree = Rng::ParseTreeProcessor.new(described_class.new.parse(rnc)).normalize.grammar_tree
        described_class.convert_to_rng(tree)
      end

      it 'emits a bare <ref> when there is no occurrence marker' do
        rng_xml = build_rng('item')
        expect(rng_xml).to include('<ref name="item"/>')
        expect(rng_xml).not_to match(%r{<(zeroOrMore|oneOrMore|optional)>})
      end

      it 'wraps ref* in <zeroOrMore>' do
        rng_xml = build_rng('item*')
        expect(rng_xml).to match(%r{<zeroOrMore>\s*<ref name="item"/>\s*</zeroOrMore>})
      end

      it 'wraps ref+ in <oneOrMore>' do
        rng_xml = build_rng('item+')
        expect(rng_xml).to match(%r{<oneOrMore>\s*<ref name="item"/>\s*</oneOrMore>})
      end

      it 'wraps ref? in <optional>' do
        rng_xml = build_rng('item?')
        expect(rng_xml).to match(%r{<optional>\s*<ref name="item"/>\s*</optional>})
      end

      it 'populates ZeroOrMore on the parsed Grammar for ref*' do
        grammar = described_class.parse("start = element root { item* }\nitem = element item { text }\n")
        element = grammar.start.first.element
        expect(element.zeroOrMore.length).to eq(1)
        expect(element.zeroOrMore.first.ref.map(&:name)).to eq(['item'])
        expect(element.ref).to be_empty
      end
    end

    context 'with pattern references in choice' do
      let(:input) do
        <<~RNC
          start = element doc {
            (section1 | section2)+
          }

          section1 = element section1 { text }
          section2 = element section2 { text }
        RNC
      end

      it 'parses choice of references correctly' do
        grammar = described_class.parse(input)

        # Should have start with oneOrMore containing choice of refs
        expect(grammar.start).not_to be_empty
        expect(grammar.define.length).to eq(2)
        expect(grammar.define.map(&:name)).to contain_exactly('section1',
                                                              'section2')
      end

      it 'round-trips choice of references correctly' do
        grammar1 = described_class.parse(input)
        rnc = described_class.to_rnc(grammar1)
        grammar2 = described_class.parse(rnc)

        expect(grammar2.define.map(&:name).sort).to eq(grammar1.define.map(&:name).sort)
      end
    end
  end

  # Metanorma Schema Tests - Test all real-world schemas
  describe 'Metanorma Schema Tests' do
    # Get all RNC files from metanorma fixtures
    rnc_files = Dir.glob('spec/fixtures/metanorma/*.rnc')

    if rnc_files.empty?
      it 'has Metanorma schema fixtures available' do
        skip 'No Metanorma RNC files found in spec/fixtures/metanorma/'
      end
    else
      rnc_files.each do |rnc_file|
        schema_name = File.basename(rnc_file, '.rnc')

        context "with #{schema_name}" do
          it 'parses successfully' do
            expect { Rng.parse_file(rnc_file) }.not_to raise_error
          end

          it 'produces valid Grammar object' do
            grammar = Rng.parse_file(rnc_file)
            expect(grammar).to be_a(Rng::Grammar)
            expect(grammar.start).not_to be_nil
          end

          it 'round-trips correctly' do
            grammar1 = Rng.parse_file(rnc_file)
            rnc_generated = described_class.to_rnc(grammar1)
            grammar2 = described_class.parse(rnc_generated)

            # Compare structure
            expect(grammar2.start.first.element.name).to eq(grammar1.start.first.element.name) if grammar1.start&.first&.element&.name

            # Compare defined patterns
            expect(grammar2.define.map(&:name).sort).to eq(grammar1.define.map(&:name).sort) if grammar1.define && grammar2.define
          end
        end
      end
    end
  end

  # Complex RELAX NG Pattern Tests
  describe 'Complex RELAX NG Patterns' do
    context 'with interleave patterns' do
      let(:input) do
        <<~RNC
          start = element doc {
            element a { text } &
            element b { text }
          }
        RNC
      end

      it 'parses interleave correctly' do
        grammar = described_class.parse(input)
        il = grammar.start.first.element.interleave
        expect(il).not_to be_nil
      end

      it 'round-trips interleave patterns' do
        grammar1 = described_class.parse(input)
        rnc = described_class.to_rnc(grammar1)
        grammar2 = described_class.parse(rnc)

        il = grammar2.start.first.element.interleave
        expect(il).not_to be_nil
      end
    end

    context 'with anyName patterns' do
      let(:input) do
        <<~RNC
          start = element * {
            text
          }
        RNC
      end

      it 'parses anyName correctly' do
        grammar = described_class.parse(input)
        element = grammar.start.first.element
        expect(element.anyName).not_to be_nil
      end
    end

    context 'with nsName patterns' do
      let(:input) do
        <<~RNC
          namespace ns = "http://example.org"

          start = element ns:* {
            text
          }
        RNC
      end

      it 'parses nsName correctly' do
        grammar = described_class.parse(input)
        expect(grammar.start.first.element).to be_a(Rng::Element)
      end
    end

    context 'with external references' do
      let(:input) do
        <<~RNC
          start = element doc {
            external "other.rnc"
          }
        RNC
      end

      it 'parses external references' do
        expect { described_class.parse(input) }.not_to raise_error
      end
    end

    context 'with parent references' do
      let(:input) do
        <<~RNC
          grammar {
            start = element outer {
              grammar {
                start = element inner {
                  parent ref
                }
                ref = element data { text }
              }
            }
            ref = element sibling { text }
          }
        RNC
      end

      it 'parses parent references' do
        expect { described_class.parse(input) }.not_to raise_error
      end
    end

    context 'with list patterns' do
      let(:input) do
        <<~RNC
          start = element values {
            list {
              xsd:int+
            }
          }
        RNC
      end

      it 'parses list patterns' do
        grammar = described_class.parse(input)
        expect(grammar.start.first.element.list).not_to be_nil
      end
    end

    context 'with notAllowed patterns' do
      let(:input) do
        <<~RNC
          start = element doc {
            notAllowed
          }
        RNC
      end

      it 'parses notAllowed correctly' do
        grammar = described_class.parse(input)
        expect(grammar.start.first.element.notAllowed).not_to be_nil
      end
    end

    context 'with empty patterns' do
      let(:input) do
        <<~RNC
          start = element doc {
            empty
          }
        RNC
      end

      it 'parses empty correctly' do
        grammar = described_class.parse(input)
        expect(grammar.start.first.element.empty).not_to be_nil
      end
    end

    context 'with data patterns with params' do
      let(:input) do
        <<~RNC
          start = element value {
            xsd:string { maxLength = "100" }
          }
        RNC
      end

      it 'parses data with parameters' do
        grammar = described_class.parse(input)
        data = grammar.start.first.element.data
        expect(data).not_to be_nil
        expect(data.param).not_to be_empty if data&.param
      end
    end

    context 'with named pattern after ## comment' do
      let(:input) do
        <<~RNC
          document =
            element document {
              ## test 1
              test
            }

          test =
            element sections {
              attribute test { text }?
            }
        RNC
      end

      let(:grammar) { described_class.parse(input) }

      it 'parses without error' do
        expect { grammar }.not_to raise_error
      end

      it 'contains the element document' do
        expect(grammar.define.map(&:name)).to include('document')
        document_def = grammar.define.find { |d| d.name == 'document' }
        expect(document_def.element[0].attr_name).to eq('document')
      end

      it 'contains the element sections' do
        expect(grammar.define.map(&:name)).to include('test')
        test_def = grammar.define.find { |d| d.name == 'test' }
        expect(test_def.element[0].attr_name).to eq('sections')
      end
    end

    context 'with escape sequences in string literals' do
      it 'parses known escapes (\\n, \\t, \\r, \\", \\\\)' do
        input = <<~'RNC'
          start = element value {
            xsd:string { pattern = "hello\nworld\ttab\r\n" }
          }
        RNC
        expect { described_class.parse(input) }.not_to raise_error
      end

      it 'parses RELAX NG class escapes (\\i, \\c, \\d, \\w)' do
        input = <<~'RNC'
          start = element value {
            xsd:string { pattern = "\\i\\c\\d\\w" }
          }
        RNC
        expect { described_class.parse(input) }.not_to raise_error
      end

      it 'parses unknown escape sequences (\\+, \\-, \\s, \\., \\,) preserving backslash' do
        input = <<~'RNC'
          start = element value {
            xsd:string { pattern = "[\\+\\-]?\\d{4}" }
          }
        RNC
        expect { described_class.parse(input) }.not_to raise_error
      end

      it 'parses ISO 8601 regex pattern with multiple escape sequences' do
        input = <<~'RNC'
          ISO8601DateTime = xsd:string { pattern = "([\\+\\-]?\\d{4})((-?)((0[1-9]|1[0-2])((-?)([12]\\d|0[1-9]|3[01]))?|W([0-4]\\d|5[0-2])(-?[1-7])?|(00[1-9]|0[1-9]\\d|[12]\\d{2}|3([0-5]\\d|6[1-6])))([T\\s]((([01]\\d|2[0-3])((:?)[0-5]\\d)?|24:?00)([\\.,]\\d+)?)?((:?)[0-5]\\d([.,]\\d+)?)?([zZ]|([\\+\\-])([01]\\d|2[0-3]):?([0-5]\\d)?)?)?)?)?)?" }
          elem = element elem { ISO8601DateTime }
        RNC
        expect { described_class.parse(input) }.not_to raise_error
      end

      it 'rejects invalid hex escape \\x{}' do
        # Single-quoted heredoc: \x{} is literal \x{} (one backslash)
        input = <<~'RNC'
          start = element value {
            xsd:string { pattern = "\x{}" }
          }
        RNC
        expect do
          described_class.parse(input)
        end.to raise_error(Parslet::ParseFailed)
      end

      it 'round-trips unknown escape sequences preserving backslash' do
        rnc_input = <<~'RNC'
          start = element value {
            xsd:string { pattern = "[\\+\\-]?\\d{4}" }
          }
        RNC
        grammar = described_class.parse(rnc_input)
        rnc_output = described_class.to_rnc(grammar)
        expect(rnc_output).to include('\\+')
        expect(rnc_output).to include('\\-')
        expect(rnc_output).to include('\\d')
      end
    end

    context 'with except patterns in anyName' do
      let(:input) do
        <<~RNC
          start = element * - (reserved | special) {
            text
          }
        RNC
      end

      it 'parses except in anyName' do
        expect { described_class.parse(input) }.not_to raise_error
      end
    end
  end

  # Error Handling Tests
  describe 'Error Handling' do
    context 'with malformed RNC' do
      it 'raises error for missing closing brace' do
        input = 'element doc { text'
        expect do
          described_class.parse(input)
        end.to raise_error(Parslet::ParseFailed)
      end

      it 'raises error for invalid element syntax' do
        input = 'element { text }'
        expect do
          described_class.parse(input)
        end.to raise_error(Parslet::ParseFailed)
      end

      it 'raises error for invalid occurrence marker' do
        input = 'element doc { text ++ }'
        expect do
          described_class.parse(input)
        end.to raise_error(Parslet::ParseFailed)
      end

      it 'raises error for unclosed parentheses' do
        input = 'element doc { (text }'
        expect do
          described_class.parse(input)
        end.to raise_error(Parslet::ParseFailed)
      end

      it 'raises error for invalid choice syntax' do
        input = 'element doc { text | | text }'
        expect do
          described_class.parse(input)
        end.to raise_error(Parslet::ParseFailed)
      end
    end

    context 'with empty input' do
      it 'returns empty grammar for empty string' do
        result = described_class.parse('')
        expect(result).to be_a(Rng::Grammar)
      end

      it 'returns empty grammar for whitespace only' do
        result = described_class.parse("   \n  ")
        expect(result).to be_a(Rng::Grammar)
      end
    end
  end

  # Performance Benchmarks
  describe 'Performance' do
    context 'with large schemas' do
      # Find the largest schema file
      rnc_files = Dir.glob('spec/fixtures/metanorma/*.rnc')

      if rnc_files.any?
        largest_file = rnc_files.max_by { |f| File.size(f) }
        schema_name = File.basename(largest_file, '.rnc')

        it "parses #{schema_name} in reasonable time" do
          rnc = File.read(largest_file)

          start_time = Time.now
          10.times { described_class.parse(rnc) }
          elapsed = Time.now - start_time

          avg_time = elapsed / 10

          # Should parse in under 2s per iteration
          expect(avg_time).to be < 2.0
        end
      else
        it 'has schema files for performance testing' do
          skip 'No Metanorma schemas available for performance testing'
        end
      end
    end

    context 'with round-trip conversion' do
      let(:input) do
        <<~RNC
          start = element addressBook {
            element card {
              attribute id { text },
              element name { text },
              element email { text }
            }*
          }
        RNC
      end

      it 'performs round-trip conversion efficiently' do
        start_time = Time.now

        100.times do
          grammar = described_class.parse(input)
          rnc = described_class.to_rnc(grammar)
          described_class.parse(rnc)
        end

        elapsed = Time.now - start_time
        avg_time = elapsed / 100

        # Should complete in under 50ms per round-trip
        expect(avg_time).to be < 0.05
      end
    end
  end
end
