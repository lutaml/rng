# frozen_string_literal: true

require 'thor'
require 'rng'
require 'rng/version'

module Rng
  # Base error class for CLI errors (inherits from Thor::Error for proper error display)
  class CLIError < Thor::Error; end

  # Validation error - document failed validation
  class ValidationError < CLIError; end

  # File error - file not found or not readable
  class FileError < CLIError; end

  # Parse error - schema could not be parsed
  class ParseError < CLIError; end

  # Conversion error - could not convert between formats
  class ConversionError < CLIError; end

  class CLI < Thor
    VERSION = Rng::VERSION

    class_option :verbose, type: :boolean, aliases: '-v', desc: 'Verbose output'
    class_option :quiet, type: :boolean, aliases: '-q', desc: 'Suppress non-error output'

    def self.exit_on_failure?
      true
    end

    desc 'validate SCHEMA [DOCUMENT]', 'Validate XML document against RELAX NG schema'
    long_desc <<~DESC
      Validate an XML document against a RELAX NG schema (replaces jing).

      SCHEMA is the path to the RELAX NG schema file (RNG or RNC format).
      DOCUMENT is the path to the XML document to validate (optional).

      If DOCUMENT is not provided, validates the schema itself.
    DESC
    method_option :compact, type: :boolean, aliases: '-c', desc: 'Schema is in RNC compact format'
    method_option :xml, type: :boolean, aliases: '-x', desc: 'Schema is in RNG XML format (default: auto-detect)'
    method_option :ignore_whitespace, type: :boolean, aliases: '-i', desc: 'Ignore insignificant whitespace'
    method_option :output, type: :string, aliases: '-o', desc: 'Output format: text, xml, json (default: text)'
    def validate(schema, document = nil)
      if document
        validate_document(schema, document)
      else
        validate_schema(schema)
      end
    end

    desc 'convert INPUT [OUTPUT]', 'Convert between RNC, RNG, and other schema formats'
    long_desc <<~DESC
      Convert between RELAX NG Compact (RNC) and XML (RNG) formats (replaces trang).

      INPUT is the path to the input schema file.
      OUTPUT is the path to the output file (default: stdout).
    DESC
    method_option :input_format, type: :string, aliases: '-I', desc: 'Input format: rng, rnc, auto (default: auto)'
    method_option :output_format, type: :string, aliases: '-O', desc: 'Output format: rng, rnc, auto (default: auto)'
    method_option :inherit, type: :boolean, desc: 'Inherit namespaces from input'
    def convert(input, output = nil)
      convert_schema(input, output)
    end

    desc 'parse SCHEMA', 'Parse and display schema structure'
    long_desc <<~DESC
      Parse a schema and display its structure in various formats.

      SCHEMA is the path to the schema file (RNG or RNC format).
    DESC
    method_option :format, type: :string, aliases: '-f', desc: 'Output format: text, json, yaml, xml (default: text)'
    method_option :ast, type: :boolean, desc: 'Show abstract syntax tree (RNC only)'
    method_option :locations, type: :boolean, desc: 'Show source locations'
    def parse(schema)
      parse_schema(schema)
    end

    desc 'info SCHEMA', 'Show information about a schema'
    long_desc <<~DESC
      Show information about a RELAX NG schema.

      SCHEMA is the path to the schema file.
    DESC
    method_option :statistics, type: :boolean, desc: 'Show pattern statistics'
    method_option :namespaces, type: :boolean, desc: 'List used namespaces'
    def info(schema)
      info_schema(schema)
    end

    desc 'version', 'Show version number'
    def version
      puts "rng version #{VERSION}"
    end

    map %w[--version -V] => :version

    private

    def detect_format(path)
      return :rnc if path.end_with?('.rnc')
      return :rng if path.end_with?('.rng')
      return :xml if path.end_with?('.xml')

      :auto
    end

    def validate_document(schema_path, document_path)
      raise FileError, "Schema file not found: #{schema_path}" unless File.exist?(schema_path)
      raise FileError, "Document file not found: #{document_path}" unless File.exist?(document_path)

      say "Validating #{document_path} against #{schema_path}...", :green

      schema_content = File.read(schema_path)
      document_content = File.read(document_path)

      format = if options[:compact]
                 :rnc
               elsif options[:xml]
                 :rng
               else
                 detect_format(schema_path)
               end

      grammar = if format == :rnc
                  Rng.parse_rnc(schema_content)
                else
                  Rng.parse(schema_content)
                end

      # Use SchemaValidator for validation
      Rng::SchemaValidator.validate(document_content, grammar: grammar)

      say 'Document is valid', :green
    rescue Errno::ENOENT => e
      raise FileError, "File not found: #{e.filename}"
    rescue Rng::SchemaValidationError => e
      raise ValidationError, e.message
    rescue StandardError => e
      raise e if e.is_a?(CLIError)

      raise ParseError, "#{e.class}: #{e.message}"
    end

    def validate_schema(schema_path)
      raise FileError, "Schema file not found: #{schema_path}" unless File.exist?(schema_path)

      say "Validating schema #{schema_path}...", :green

      content = File.read(schema_path)

      format = if options[:compact]
                 :rnc
               elsif options[:xml]
                 :rng
               else
                 detect_format(schema_path)
               end

      grammar = if format == :rnc
                  Rng.parse_rnc(content)
                else
                  Rng.parse(content)
                end

      say 'Schema is valid', :green
      say "Found #{grammar.define.count} definitions" unless options[:quiet]
    rescue StandardError => e
      raise e if e.is_a?(CLIError)

      raise ParseError, "#{e.class}: #{e.message}"
    end

    def convert_schema(input_path, output_path)
      raise FileError, "Input file not found: #{input_path}" unless File.exist?(input_path)

      input_content = File.read(input_path)

      input_format = if options[:input_format] && options[:input_format] != 'auto'
                       options[:input_format].to_sym
                     else
                       detect_format(input_path)
                     end

      output_format = if options[:output_format] && options[:output_format] != 'auto'
                        options[:output_format].to_sym
                      elsif input_format == :rnc
                        :rng
                      else
                        :rnc
                      end

      say "Converting #{input_path} (#{input_format}) to #{output_format}...", :green

      grammar = case input_format
                when :rnc
                  Rng.parse_rnc(input_content)
                when :rng
                  Rng.parse(input_content)
                else
                  begin
                    Rng.parse(input_content)
                  rescue StandardError
                    Rng.parse_rnc(input_content)
                  end
                end

      result = case output_format
               when :rnc
                 Rng.to_rnc(grammar)
               when :rng
                 grammar.to_xml
               else
                 raise ConversionError, "Unknown output format: #{output_format}"
               end

      if output_path
        File.write(output_path, result)
        say "Written to #{output_path}", :green
      else
        puts result
      end
    rescue StandardError => e
      raise e if e.is_a?(CLIError)

      raise ConversionError, "#{e.class}: #{e.message}"
    end

    def parse_schema(schema_path)
      raise FileError, "Schema file not found: #{schema_path}" unless File.exist?(schema_path)

      content = File.read(schema_path)
      output_format = (options[:format] || 'text').to_sym

      format = if options[:compact]
                 :rnc
               elsif options[:xml]
                 :rng
               else
                 detect_format(schema_path)
               end

      grammar = case format
                when :rnc
                  Rng.parse_rnc(content)
                when :rng
                  Rng.parse(content)
                else
                  begin
                    Rng.parse(content)
                  rescue StandardError
                    Rng.parse_rnc(content)
                  end
                end

      case output_format
      when :json
        puts JSON.pretty_generate(grammar.to_h)
      when :yaml
        require 'yaml'
        puts YAML.dump(grammar.to_h)
      when :xml
        puts grammar.to_xml
      else
        display_schema_text(grammar)
      end
    rescue StandardError => e
      raise e if e.is_a?(CLIError)

      raise ParseError, "#{e.class}: #{e.message}"
    end

    def display_schema_text(grammar)
      say 'Schema Structure:', :green
      start = grammar.start
      if start && !start.empty?
        say "  Start: #{start.first ? pattern_name(start.first) : 'none'}"
      else
        say '  Start: none'
      end

      defines = grammar.define
      if defines && !defines.empty?
        say '  Definitions:', :green
        defines.each do |define|
          pattern_types = collect_pattern_types(define)
          say "    #{define.name}: #{pattern_types.join(', ')}"
        end
      end

      includes = grammar.include
      return unless includes && !includes.empty?

      say '  Includes:', :green
      includes.each do |inc|
        say "    #{inc.href}"
      end
    end

    def collect_pattern_types(define)
      types = []
      types << 'ref' if define.ref&.any?
      types << 'element' if define.element&.any?
      types << 'choice' if define.choice&.any?
      types << 'group' if define.group&.any?
      types << 'interleave' if define.interleave&.any?
      types << 'mixed' if define.mixed&.any?
      types << 'optional' if define.optional&.any?
      types << 'zeroOrMore' if define.zeroOrMore&.any?
      types << 'oneOrMore' if define.oneOrMore&.any?
      types << 'text' if define.text&.any?
      types << 'empty' if define.empty&.any?
      types << 'value' if define.value&.any?
      types << 'data' if define.data&.any?
      types << 'list' if define.list&.any?
      types << 'notAllowed' if define.notAllowed&.any?
      types << 'attribute' if define.attribute&.any?
      types
    end

    def pattern_name(pattern)
      return 'empty' unless pattern

      pattern.class.name.split('::').last
    end

    def info_schema(schema_path)
      raise FileError, "Schema file not found: #{schema_path}" unless File.exist?(schema_path)

      content = File.read(schema_path)

      format = if options[:compact]
                 :rnc
               elsif options[:xml]
                 :rng
               else
                 detect_format(schema_path)
               end

      grammar = case format
                when :rnc
                  Rng.parse_rnc(content)
                when :rng
                  Rng.parse(content)
                else
                  begin
                    Rng.parse(content)
                  rescue StandardError
                    Rng.parse_rnc(content)
                  end
                end

      say 'Schema Information:', :green
      say "  File: #{schema_path}"
      say "  Format: #{format}"

      if options[:statistics]
        stats = compute_statistics(grammar)
        say '  Statistics:', :green
        stats.each do |key, value|
          say "    #{key}: #{value}"
        end
      end

      if options[:namespaces]
        namespaces = collect_namespaces(grammar)
        say '  Namespaces:', :green
        namespaces.each do |ns|
          say "    #{ns}"
        end
      end

      return unless !options[:statistics] && !options[:namespaces]

      say "  Definitions: #{grammar.define.count}"
      say "  Elements: #{count_elements(grammar)}"
    rescue StandardError => e
      raise e if e.is_a?(CLIError)

      raise ParseError, "#{e.class}: #{e.message}"
    end

    def compute_statistics(grammar)
      stats = {
        definitions: grammar.define.count,
        elements: count_elements(grammar),
        attributes: count_attributes(grammar),
        choices: count_patterns(grammar, 'Choice'),
        groups: count_patterns(grammar, 'Group'),
        interleaves: count_patterns(grammar, 'Interleave'),
        optionals: count_patterns(grammar, 'Optional'),
        zero_or_more: count_patterns(grammar, 'ZeroOrMore'),
        one_or_more: count_patterns(grammar, 'OneOrMore')
      }
      stats[:text] = count_patterns(grammar, 'Text')
      stats[:empty] = count_patterns(grammar, 'Empty')
      stats[:value] = count_patterns(grammar, 'Value')
      stats[:data] = count_patterns(grammar, 'Data')
      stats
    end

    def count_elements(grammar)
      count = 0
      grammar.define.each do |define|
        count += define.element.count
        define.element.each { |e| count += count_elements_in(e) }
      end
      count
    end

    def count_elements_in(element)
      return 0 unless element

      count = 0
      element.element.each { |e| count += 1 + count_elements_in(e) } if element.respond_to?(:element) && element.element
      if element.respond_to?(:choice) && element.choice
        element.choice.each do |c|
          next unless c.respond_to?(:element) && c.element

          c.element.each do |e|
            count += count_elements_in(e)
          end
        end
      end
      if element.respond_to?(:group) && element.group
        element.group.each do |g|
          next unless g.respond_to?(:element) && g.element

          g.element.each do |e|
            count += count_elements_in(e)
          end
        end
      end
      if element.respond_to?(:interleave) && element.interleave
        element.interleave.each do |i|
          next unless i.respond_to?(:element) && i.element

          i.element.each do |e|
            count += count_elements_in(e)
          end
        end
      end
      if element.respond_to?(:optional) && element.optional
        element.optional.each { |o| count += count_elements_in(o) if o.respond_to?(:element) && o.element }
      end
      if element.respond_to?(:zeroOrMore) && element.zeroOrMore
        element.zeroOrMore.each { |z| count += count_elements_in(z) if z.respond_to?(:element) && z.element }
      end
      if element.respond_to?(:oneOrMore) && element.oneOrMore
        element.oneOrMore.each { |o| count += count_elements_in(o) if o.respond_to?(:element) && o.element }
      end
      count
    end

    def count_attributes(grammar)
      count = 0
      grammar.define.each do |define|
        count += define.attribute.count
        define.element.each { |e| count += count_attributes_in(e) }
      end
      count
    end

    def count_attributes_in(element)
      count = 0
      return count unless element

      count += element.attribute.count if element.respond_to?(:attribute) && element.attribute
      element.element.each { |e| count += count_attributes_in(e) } if element.respond_to?(:element) && element.element
      if element.respond_to?(:choice) && element.choice
        element.choice.each do |c|
          next unless c.respond_to?(:element) && c.element

          c.element.each do |e|
            count += count_attributes_in(e)
          end
        end
      end
      if element.respond_to?(:group) && element.group
        element.group.each do |g|
          next unless g.respond_to?(:element) && g.element

          g.element.each do |e|
            count += count_attributes_in(e)
          end
        end
      end
      if element.respond_to?(:interleave) && element.interleave
        element.interleave.each do |i|
          next unless i.respond_to?(:element) && i.element

          i.element.each do |e|
            count += count_attributes_in(e)
          end
        end
      end
      if element.respond_to?(:optional) && element.optional
        element.optional.each { |o| count += count_attributes_in(o) if o.respond_to?(:element) && o.element }
      end
      if element.respond_to?(:zeroOrMore) && element.zeroOrMore
        element.zeroOrMore.each { |z| count += count_attributes_in(z) if z.respond_to?(:element) && z.element }
      end
      if element.respond_to?(:oneOrMore) && element.oneOrMore
        element.oneOrMore.each { |o| count += count_attributes_in(o) if o.respond_to?(:element) && o.element }
      end
      count
    end

    def count_patterns(grammar, class_name)
      count = 0
      grammar.define.each do |define|
        count += define.send(class_name.downcase).count if define.respond_to?(class_name.downcase)
      end
      count
    end

    def collect_namespaces(grammar)
      namespaces = Set.new
      namespaces.add(grammar.datatype_library) if grammar.datatype_library
      grammar.define.each do |define|
        collect_namespaces_in_define(define, namespaces)
      end
      namespaces.to_a.sort
    end

    def collect_namespaces_in_define(define, namespaces)
      define.element.each { |e| collect_namespaces_in_element(e, namespaces) }
      define.group.each { |g| g.element.each { |e| collect_namespaces_in_element(e, namespaces) } }
      define.choice.each { |c| c.element.each { |e| collect_namespaces_in_element(e, namespaces) } }
      define.interleave.each { |i| i.element.each { |e| collect_namespaces_in_element(e, namespaces) } }
      define.optional.each do |o|
        next unless o.respond_to?(:element)

        o.element.each do |e|
          collect_namespaces_in_element(e, namespaces)
        end
      end
      define.zeroOrMore.each do |z|
        next unless z.respond_to?(:element)

        z.element.each do |e|
          collect_namespaces_in_element(e, namespaces)
        end
      end
      define.oneOrMore.each do |o|
        next unless o.respond_to?(:element)

        o.element.each do |e|
          collect_namespaces_in_element(e, namespaces)
        end
      end
    end

    def collect_namespaces_in_element(element, namespaces)
      return unless element

      namespaces.add(element.ns) if element.respond_to?(:ns) && element.ns
      if element.respond_to?(:element) && element.element
        element.element.each do |e|
          collect_namespaces_in_element(e, namespaces)
        end
      end
      if element.respond_to?(:choice) && element.choice
        element.choice.each do |c|
          next unless c.respond_to?(:element) && c.element

          c.element.each do |e|
            collect_namespaces_in_element(e, namespaces)
          end
        end
      end
      if element.respond_to?(:group) && element.group
        element.group.each do |g|
          next unless g.respond_to?(:element) && g.element

          g.element.each do |e|
            collect_namespaces_in_element(e, namespaces)
          end
        end
      end
      if element.respond_to?(:interleave) && element.interleave
        element.interleave.each do |i|
          next unless i.respond_to?(:element) && i.element

          i.element.each do |e|
            collect_namespaces_in_element(e, namespaces)
          end
        end
      end
      if element.respond_to?(:optional) && element.optional
        element.optional.each do |o|
          collect_namespaces_in_element(o, namespaces)
        end
      end
      if element.respond_to?(:zeroOrMore) && element.zeroOrMore
        element.zeroOrMore.each do |z|
          collect_namespaces_in_element(z, namespaces)
        end
      end
      return unless element.respond_to?(:oneOrMore) && element.oneOrMore

      element.oneOrMore.each { |o| collect_namespaces_in_element(o, namespaces) }
    end
  end
end
