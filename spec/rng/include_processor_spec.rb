# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Rng::IncludeProcessor do
  # A grammar-block RNC that includes another grammar and then defines its
  # own named patterns after the include. The merged grammar must carry BOTH
  # the included grammar's definitions and the including file's own patterns.
  # ParseTreeProcessor used to overwrite :definitions (the include merge
  # result) with only :includes + :patterns, dropping every included define.
  it 'keeps included definitions and own patterns in a grammar block file' do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'base.rnc'), <<~RNC)
        start = doc
        doc = element doc { sections }
        sections = element sections { element a { text } }
      RNC

      File.write(File.join(dir, 'derived.rnc'), <<~RNC)
        include "base.rnc" {
          doc = element doc { sections }
        }

        start = derived
        derived = element derived { sections }
        note = element note { text }
      RNC

      grammar = Rng.parse_file(File.join(dir, 'derived.rnc'))
      names = grammar.define.map(&:name)

      expect(names).to include('sections')
      expect(names).to include('note')
      expect(names).to include('derived')
    end
  end

  it 'applies include-block overrides, replacing the base definition' do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'base.rnc'), <<~RNC)
        start = doc
        doc = element doc { sections }
        sections = element sections { element a { text } }
      RNC

      File.write(File.join(dir, 'derived.rnc'), <<~RNC)
        include "base.rnc" {
          sections = element sections { element b { text } }
        }
      RNC

      grammar = Rng.parse_file(File.join(dir, 'derived.rnc'))
      sections = grammar.define.find { |d| d.name == 'sections' }

      expect(sections).not_to be_nil
      expect(sections.to_xml).to include('name="b"')
      expect(sections.to_xml).not_to include('name="a"')
    end
  end
end
