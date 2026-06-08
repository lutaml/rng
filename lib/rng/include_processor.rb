# frozen_string_literal: true

require 'set'

module Rng
  # Handles RNC file inclusion and grammar merging
  #
  # This class processes include directives in RNC files, resolving them
  # recursively while preventing circular includes. It supports both:
  # - Grammar-level includes (inside grammar blocks)
  # - Top-level includes (Metanorma-style schemas)
  #
  # @example Parse a file with includes
  #   processor = Rng::IncludeProcessor.new
  #   grammar = processor.parse_file("schema.rnc")
  #
  class IncludeProcessor
    # Initialize with optional converter
    #
    # @param converter [RncToRngConverter] Converter for parse tree to RNG XML
    def initialize(converter = RncToRngConverter.new)
      @converter = converter
    end

    # Parse a file with include resolution
    #
    # @param file_path [String] Path to RNC file
    # @param base_dir [String, nil] Base directory for resolving relative paths
    # @param visited_files [Set] Set of already visited file paths (for circular detection)
    # @return [Grammar] Parsed grammar object
    def parse_file(file_path, base_dir = nil, visited_files = Set.new)
      abs_path = track_visited_file(file_path, base_dir, visited_files)

      # Read file content
      raise "Include file not found: #{abs_path}" unless File.exist?(abs_path)

      parse_tree_to_grammar(File.read(abs_path), abs_path, visited_files)
    end

    # Parse in-memory RNC content with optional include resolution.
    #
    # When +location+ is nil, includes are not resolved and the pipeline matches
    # {RncParser.parse} exactly. When +location+ is a file path, relative
    # +include+ directives are resolved against that file's directory.
    #
    # @param content [String] RNC content
    # @param location [String, nil] Source file path used to resolve relative includes
    # @param visited_files [Set] Set of already visited file paths (for circular detection)
    # @return [Grammar] Parsed grammar object
    def parse_content(content, location: nil, visited_files: Set.new)
      abs_path = location && track_visited_file(location, nil, visited_files)
      parse_tree_to_grammar(content, abs_path, visited_files)
    end

    private

    def parse_tree_to_grammar(content, abs_path, visited_files)
      tree = parse_content_to_tree(content)

      if abs_path
        # process_includes runs before normalize and needs raw_override /
        # raw_grammar / raw_patterns expanded so it can walk the parsed
        # subtrees. normalize would do this on the grammar_tree later, but
        # by then process_includes has already executed.
        process_raw_nodes!(tree)
        process_includes(tree, File.dirname(abs_path), visited_files)
      end

      rng_xml = @converter.convert(build_grammar_tree(tree))
      Grammar.from_xml(rng_xml)
    end

    def track_visited_file(file_path, base_dir, visited_files)
      abs_path = File.expand_path(file_path, base_dir)
      raise "Circular include detected: #{abs_path}" if visited_files.include?(abs_path)

      visited_files.add(abs_path)
      abs_path
    end

    # Parse RNC content into a raw parse tree.
    #
    # Applies hex-escape preprocessing so callers get the same parse tree
    # they would from {RncParser.parse}. Preprocessing is idempotent on input
    # that contains no hex escapes outside string literals, so it is safe to
    # apply to file content as well.
    #
    # @param content [String] RNC content
    # @return [Hash] Raw parse tree
    def parse_content_to_tree(content)
      RncParser.new.parse(RncParser.preprocess_hex_escapes(content.strip))
    end

    # Process include directives by recursively parsing included files
    #
    # @param tree [Hash] Parse tree
    # @param base_dir [String] Base directory for resolving relative paths
    # @param visited_files [Set] Set of already visited file paths
    def process_includes(tree, base_dir, visited_files)
      # Handle top-level includes first (Metanorma-style schemas)
      if tree.key?(:top_includes)
        process_top_level_includes(tree, base_dir, visited_files)
        return
      end

      return if tree[:includes] && tree[:includes].empty?

      # Handle grammar-level includes (existing logic)
      grammar_tree = extract_grammar_tree(tree)

      return unless grammar_tree[:includes] && !grammar_tree[:includes].empty?

      # Process each include
      grammar_tree[:includes].each do |include_item|
        process_single_include(grammar_tree, include_item, base_dir,
                               visited_files)
      end

      # Remove includes array after processing (no longer needed in conversion)
      grammar_tree.delete(:includes)
    end

    # Process top-level includes (Metanorma-style schemas)
    #
    # @param tree [Hash] Parse tree
    # @param base_dir [String] Base directory for resolving relative paths
    # @param visited_files [Set] Set of already visited file paths
    def process_top_level_includes(tree, base_dir, visited_files)
      # Create a temporary grammar_tree to hold merged content
      grammar_tree = {
        start: nil,
        definitions: []
      }

      # Process each top-level include
      tree[:top_includes].each do |include_item|
        href = extract_string_literal(include_item[:href])
        override = parse_override(include_item[:override])

        included_grammar = resolve_included_grammar(href, base_dir, visited_files.dup)

        # Merge included definitions into temporary grammar_tree
        merge_included_grammar(grammar_tree, included_grammar, override)
      end

      # Merge the resolved grammar_tree back into the main tree
      tree[:start] = grammar_tree[:start] if grammar_tree[:start]
      if grammar_tree[:definitions]
        tree[:definitions] =
          grammar_tree[:definitions]
      end

      # Process raw_trailing if present (named patterns after includes)
      process_raw_trailing!(tree, grammar_tree) if tree[:raw_trailing]

      # Clean up - remove top_includes key as it's been processed
      tree.delete(:top_includes)
    end

    # Process a single include directive
    #
    # @param grammar_tree [Hash] Grammar tree to merge into
    # @param include_item [Hash] Include item from parse tree
    # @param base_dir [String] Base directory for resolving relative paths
    # @param visited_files [Set] Set of already visited file paths
    def process_single_include(grammar_tree, include_item, base_dir,
                               visited_files)
      href = extract_string_literal(include_item[:href])
      override = parse_override(include_item[:override])

      included_grammar = resolve_included_grammar(href, base_dir, visited_files.dup)

      # Merge included definitions into current tree
      merge_included_grammar(grammar_tree, included_grammar, override)
    end

    # Extract grammar tree from parse tree
    #
    # @param tree [Hash] Parse tree
    # @return [Hash] Grammar tree
    def extract_grammar_tree(tree)
      if tree.key?(:inner_grammar)
        tree[:inner_grammar]
      else
        tree
      end
    end

    def resolve_included_grammar(file_path, base_dir, visited_files)
      abs_path = track_visited_file(file_path, base_dir, visited_files)
      raise "Include file not found: #{abs_path}" unless File.exist?(abs_path)

      tree = parse_content_to_tree(File.read(abs_path))
      process_raw_nodes!(tree)
      process_includes(tree, File.dirname(abs_path), visited_files)
      build_grammar_tree(tree)
    end

    # Process raw_grammar/raw_override/raw_patterns nodes in-place
    #
    # This is needed when included files contain grammar blocks or
    # overrides that are captured as raw text by the parser.
    #
    # @param tree [Hash] Parse tree to process in-place
    def process_raw_nodes!(tree)
      ParseTreeProcessor.new(tree).send(:process_raw_overrides!, tree)
    end

    # Process raw_trailing content (named patterns after top-level includes)
    #
    # For schemas like ietf.rnc where include directives are followed by
    # named pattern definitions, the trailing content is captured as raw_trailing.
    # This method parses that content and adds definitions to grammar_tree.
    #
    # @param tree [Hash] Parse tree containing raw_trailing
    # @param grammar_tree [Hash] Grammar tree to merge definitions into
    def process_raw_trailing!(tree, grammar_tree)
      raw = tree[:raw_trailing]
      return unless raw

      text = if raw.is_a?(Array)
               raw.map { |r| r.respond_to?(:str) ? r.str : r.to_s }.join
             else
               (raw.respond_to?(:str) ? raw.str : raw.to_s)
             end
      return if text.strip.empty?

      # Parse raw_trailing as a grammar (which handles named patterns)
      parser = Rng::RncParser.new
      begin
        parsed = parser.grammar.parse(text.strip)
        patterns = parsed[:patterns] || []
        grammar_tree[:definitions] ||= []
        grammar_tree[:definitions].concat(patterns)
      rescue Parslet::ParseFailed => e
        warn "Warning: Failed to parse trailing content: #{e.message}" if ENV['RNG_VERBOSE']
      ensure
        tree.delete(:raw_trailing)
      end
    end

    # Build grammar tree from different tree structures
    #
    # Handles:
    # - Top-level includes (Metanorma style)
    # - Grammar block wrapper
    # - Flat grammar
    #
    # @param tree [Hash] Parse tree
    # @return [Hash] Normalized grammar tree
    def build_grammar_tree(tree)
      ParseTreeProcessor.new(tree).normalize.grammar_tree
    end

    # Merge included grammar into current grammar, applying overrides
    #
    # @param target_tree [Hash] Target grammar tree to merge into
    # @param source_tree [Hash] Source grammar tree to merge from
    # @param override [Hash, nil] Override definitions from include directive
    def merge_included_grammar(target_tree, source_tree, override)
      # Merge datatype library if not already set
      if source_tree[:datatype_library] && !target_tree[:datatype_library]
        target_tree[:datatype_library] =
          source_tree[:datatype_library]
      end

      # Merge start pattern if not overridden
      if source_tree[:start] && !override
        # If target has no start, use source start
        target_tree[:start] ||= source_tree[:start]
      elsif override && override[:start]
        # Use override start
        target_tree[:start] = override[:start]
      elsif source_tree[:start] && !target_tree[:start]
        target_tree[:start] = source_tree[:start]
      end

      # Initialize definitions array if needed
      target_tree[:definitions] ||= []

      # Merge definitions from source
      source_tree[:definitions]&.each do |source_def|
        # Check if this definition is overridden
        overridden = false

        if override && override[:definitions]
          override[:definitions].each do |override_def|
            # Check if names match
            next unless source_def[:name] && override_def[:name] &&
                        extract_name_from_identifier(source_def) ==
                        extract_name_from_identifier(override_def)

            # Use override instead of source
            target_tree[:definitions] << override_def
            overridden = true
            break
          end
        end

        # If not overridden, add source definition
        target_tree[:definitions] << source_def unless overridden
      end

      # Add any override definitions not matched with source
      return unless override && override[:definitions]

      override[:definitions].each do |override_def|
        # Check if this override matched any source definition
        matched = false

        source_tree[:definitions]&.each do |source_def|
          next unless source_def[:name] && override_def[:name] &&
                      extract_name_from_identifier(source_def) ==
                      extract_name_from_identifier(override_def)

          matched = true
          break
        end

        # If no match, this is a new definition - add it
        target_tree[:definitions] << override_def unless matched
      end
    end

    # Extract identifier string from a definition name hash.
    # Handles both {:identifier => "name"} and
    # {:identifier_parts => [{:char => "n"}, ...]} structures.
    def extract_name_from_identifier(defn)
      name = defn[:name]
      return nil unless name.is_a?(Hash)

      if name[:identifier]
        extract_string(name[:identifier])
      elsif name[:identifier_parts]
        name[:identifier_parts].map do |part|
          if part.is_a?(Hash) && part[:char]
            c = part[:char]
            c.respond_to?(:str) ? c.str : c.to_s
          else
            part.to_s
          end
        end.join
      end
    end

    # Helper method to extract clean string without Parslet position markers
    #
    # @param obj [Object] Parslet::Slice or String
    # @return [String] Clean string
    def extract_string(obj)
      RncParser.extract_string(obj)
    end

    # Parse raw override string into structured override hash
    #
    # @param override [Hash, nil] Override hash potentially containing :raw_override
    # @return [Hash, nil] Parsed override with :start and :definitions, or nil
    def parse_override(override)
      return nil unless override
      return override unless override[:raw_override]

      raw = extract_string(override[:raw_override])
      return nil if raw.nil? || raw.strip.empty?

      # Parse the raw override content as RNC directly (top-level style)
      parser = RncParser.new
      begin
        parsed = parser.parse(raw.strip)
        # Normalize the parsed override
        processor = ParseTreeProcessor.new(parsed)
        normalized = processor.normalize
        tree = normalized.grammar_tree
        result = {}
        result[:start] = tree[:start] if tree[:start]
        result[:definitions] = tree[:definitions] if tree[:definitions] && !tree[:definitions].empty?
        result.empty? ? nil : result
      rescue Parslet::ParseFailed
        nil
      end
    end

    # Helper method to extract string literal with concatenations
    #
    # @param lit [Hash] String literal with :string_parts and :concatenations
    # @return [String] Extracted string
    def extract_string_literal(lit)
      return '' unless lit

      # Extract main string parts
      result = extract_string_parts(lit[:string_parts])

      # Handle concatenations if present
      if lit[:concatenations].is_a?(Array)
        lit[:concatenations].each do |concat|
          result += extract_string_parts(concat[:concat_string_parts])
        end
      end

      result
    end

    # Extract string from string_parts array
    #
    # @param parts [Array, String] String parts
    # @return [String] Extracted string
    def extract_string_parts(parts)
      return '' unless parts
      return parts if parts.is_a?(String)
      return parts.str if parts.respond_to?(:str)

      return '' unless parts.is_a?(Array)

      parts.map do |part|
        if part.is_a?(String)
          part
        elsif part.respond_to?(:str)
          part.str
        elsif part[:hex_escape]
          # Handle \x{HEX}
          hex_str = part[:hex_escape][:hex]
          hex_str = hex_str.str if hex_str.respond_to?(:str)
          [hex_str.to_i(16)].pack('U')
        elsif part[:char_escape]
          # Handle \", \\, \n, \r, \t, and RELAX NG class escapes \i, \c, \d, \w
          char = part[:char_escape][:char]
          char = char.str if char.respond_to?(:str)
          case char
          when '"' then '"'
          when '\\' then '\\'
          when 'n' then "\n"
          when 'r' then "\r"
          when 't' then "\t"
          when 'i' then '\\i'
          when 'c' then '\\c'
          when 'd' then '\\d'
          when 'w' then '\\w'
          else char
          end
        elsif part[:char]
          # Regular character (plain char in string literal)
          c = part[:char]
          c = c.str if c.respond_to?(:str)
          c.to_s
        else
          part.to_s
        end
      end.join
    end
  end
end
