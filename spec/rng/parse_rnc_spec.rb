# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe 'ParseRncSpec' do
  describe '.parse_rnc' do
    let(:simple_rnc) { 'element foo { text }' }

    it 'returns a Grammar for include-free RNC without a location' do
      parsed = Rng.parse_rnc(simple_rnc)

      expect(parsed).to be_a(Rng::Grammar)
      expect(parsed.start.first.element.attr_name).to eq('foo')
    end

    it 'produces equivalent output with and without location for hex-escaped RNC' do
      # \x{72}oot decodes to "root". Hex preprocessing must run on the
      # with-location path or the parse tree differs from the no-location path
      # for the same input — which is the divergence this spec guards against.
      rnc = 'element \\x{72}oot { text }'

      Dir.mktmpdir do |dir|
        scratch = File.join(dir, 'scratch.rnc')

        without_location = Rng.parse_rnc(rnc)
        with_location = Rng.parse_rnc(rnc, location: scratch)

        expect(with_location.to_xml).to be_xml_equivalent_to(without_location.to_xml)
        expect(with_location.start.first.element.attr_name).to eq('root')
      end
    end

    it 'resolves relative includes when location is the source directory' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'child.rnc'), <<~RNC)
          ChildPattern = element child { text }
          start = element wrapped { ChildPattern }
        RNC

        parent_path = File.join(dir, 'parent.rnc')
        File.write(parent_path, <<~RNC)
          include "child.rnc" {
            start = element root { ChildPattern }
          }
        RNC

        parsed = Rng.parse_rnc(File.read(parent_path), location: dir)

        expect(parsed.define.map(&:name)).to include('ChildPattern')
        expect(parsed.start.first.element.attr_name).to eq('root')
      end
    end

    it 'also accepts a source file path as location' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'child.rnc'), <<~RNC)
          ChildPattern = element child { text }
        RNC

        parent_path = File.join(dir, 'parent.rnc')
        File.write(parent_path, <<~RNC)
          include "child.rnc" {
            start = element root { ChildPattern }
          }
        RNC

        parsed = Rng.parse_rnc(File.read(parent_path), location: parent_path)

        expect(parsed.define.map(&:name)).to include('ChildPattern')
        expect(parsed.start.first.element.attr_name).to eq('root')
      end
    end
  end
end
