# frozen_string_literal: true

module Rng
  # Normalizes parse tree structure into consistent grammar format
  #
  # Handles three different RNC file structures:
  # 1. Top-level includes (Metanorma-style)
  # 2. Grammar block wrapper
  # 3. Flat grammar
  #
  # @example Basic Usage
  #   tree = parser.parse(rnc_content)
  #   processor = ParseTreeProcessor.new(tree)
  #   normalized = processor.normalize
  #   grammar_tree = normalized.grammar_tree
  #   namespace = normalized.namespace
  #
  class ParseTreeProcessor
    attr_reader :tree, :namespace, :preamble, :grammar_tree

    # Initialize with parse tree
    #
    # @param tree [Hash] Raw parse tree from Parslet parser
    def initialize(tree)
      @tree = tree
      @namespace = nil
      @preamble = nil # NEW: SchemaPreamble object
      @grammar_tree = nil
    end

    # Normalize the parse tree
    #
    # Extracts namespace and builds consistent grammar structure
    # regardless of input format. Processes raw override blocks.
    #
    # @return [self] Returns self for chaining
    def normalize
      @preamble = extract_preamble_section # NEW: Extract preamble first
      @namespace = extract_namespace         # KEEP: Legacy namespace extraction
      @grammar_tree = build_grammar_tree
      process_raw_overrides!(@grammar_tree)
      add_metadata_to_grammar                # MODIFIED: Add both old and new metadata
      self
    end

    private

    # Extract namespace from parse tree
    #
    # @return [String, nil] Namespace URI if present
    def extract_namespace
      @tree[:namespace]
    end

    # Extract preamble section and build SchemaPreamble object
    #
    # @return [SchemaPreamble, nil] Preamble object or nil if no preamble
    def extract_preamble_section
      return nil unless @tree[:preamble_items]

      preamble = SchemaPreamble.new

      items = @tree[:preamble_items]
      items = [items] unless items.is_a?(Array)

      items.each do |item|
        # Skip non-Hash items (e.g., Parslet::Slice from annotation content)
        next unless item.is_a?(Hash)

        if item[:default_ns] || item[:default_prefixed_ns] || item[:prefixed_ns]
          process_namespace_declaration(preamble, item)
        elsif item[:prefix] && item[:uri]
          # Datatype declaration
          process_datatype_declaration(preamble, item)
        end
      end

      preamble.empty? ? nil : preamble
    end

    # Process a single namespace declaration and add to preamble
    #
    # @param preamble [SchemaPreamble] Preamble to add to
    # @param item [Hash] Namespace declaration from parse tree
    def process_namespace_declaration(preamble, item)
      if item[:default_ns]
        # Default namespace (unprefixed): default namespace = "uri"
        ns_data = item[:default_ns]
        uri = extract_string_literal(ns_data[:uri])
        preamble.add_namespace(
          NamespaceDeclaration.new(uri: uri, is_default: true),
        )
      elsif item[:default_prefixed_ns]
        # Default namespace (prefixed): default namespace prefix = "uri"
        ns_data = item[:default_prefixed_ns]
        prefix = extract_identifier(ns_data[:prefix])
        uri = extract_string_literal(ns_data[:uri])
        preamble.add_namespace(
          NamespaceDeclaration.new(prefix: prefix, uri: uri, is_default: true),
        )
      elsif item[:prefixed_ns]
        # Prefixed namespace: namespace prefix = "uri"
        ns_data = item[:prefixed_ns]
        prefix = extract_identifier(ns_data[:prefix])
        uri = extract_string_literal(ns_data[:uri])
        preamble.add_namespace(
          NamespaceDeclaration.new(prefix: prefix, uri: uri),
        )
      end
    end

    # Process a single datatype library declaration and add to preamble
    #
    # @param preamble [SchemaPreamble] Preamble to add to
    # @param item [Hash] Datatype declaration from parse tree
    def process_datatype_declaration(preamble, item)
      prefix = extract_identifier(item[:prefix])
      uri = extract_string_literal(item[:uri])
      preamble.add_datatype(
        DatatypeDeclaration.new(prefix: prefix, uri: uri),
      )
    end

    # Extract identifier from identifier parts
    #
    # @param id [Hash] Identifier with :identifier_parts
    # @return [String] Extracted identifier
    def extract_identifier(id)
      return "" unless id && id[:identifier_parts]

      id[:identifier_parts].map do |part|
        if part[:char]
          extract_parslet_string(part[:char])
        elsif part[:hex_escape]
          # Handle hex escape: \x{HEX}
          hex_str = extract_parslet_string(part[:hex_escape][:hex])
          [hex_str.to_i(16)].pack("U")
        else
          ""
        end
      end.join
    end

    # Extract string literal with concatenations
    #
    # @param lit [Hash] String literal with :string_parts and :concatenations
    # @return [String] Extracted string
    def extract_string_literal(lit)
      return "" unless lit

      result = extract_string_parts(lit[:string_parts])

      # Handle concatenations if present
      if lit[:concatenations].is_a?(Array)
        lit[:concatenations].each do |concat|
          result += extract_string_parts(concat[:concat_string_parts])
        end
      end

      result
    end

    # Extract documentation comments from parse tree node
    #
    # @param node [Hash] Node that may contain :docs
    # @return [String, nil] Documentation text or nil
    def extract_documentation(node)
      return nil unless node.is_a?(Hash) && node[:docs]

      doc_lines = node[:docs][:documentation]
      return nil unless doc_lines

      doc_lines = [doc_lines] unless doc_lines.is_a?(Array)

      doc_lines.map do |line|
        if line[:doc_line]
          extract_parslet_string(line[:doc_line])
        else
          ""
        end
      end.join("\n").strip
    end

    # Extract annotations from parse tree node
    #
    # @param node [Hash] Node that may contain :annotations
    # @return [Hash] Hash with :attributes and :elements arrays
    RNG_NAMESPACE = "http://relaxng.org/ns/structure/1.0"

    def extract_annotations(node)
      result = { attributes: [], elements: [] }
      return result unless node.is_a?(Hash) && node[:annotations]

      # Get first annotation and additional ones
      annotations = []
      ann_block = node[:annotations]

      # First annotation item (if present)
      if ann_block.is_a?(Hash)
        first_ann = ann_block.except(:more_annotations)
        annotations << first_ann unless first_ann.empty?

        # Additional annotations
        if ann_block[:more_annotations]
          more = ann_block[:more_annotations]
          more = [more] unless more.is_a?(Array)
          annotations.concat(more)
        end
      end

      # Track seen attribute names for duplicate detection (TC 11-12)
      seen_attrs = {}

      # Process each annotation
      annotations.each do |ann|
        next unless ann.is_a?(Hash) && ann[:ann_name]

        name_parts = extract_qualified_name(ann[:ann_name])

        if ann[:attr_value]
          # Foreign attribute
          value = extract_string_literal(ann[:attr_value])

          # TC 11-12: Check for duplicate annotation attributes
          attr_key = "#{name_parts[:prefix]}:#{name_parts[:local]}"
          if seen_attrs.key?(attr_key)
            raise StandardError, "duplicate annotation attribute '#{attr_key}'"
          end
          seen_attrs[attr_key] = true

          # TC 18: xmlns attribute is forbidden in annotations
          if name_parts[:local] == "xmlns" && name_parts[:prefix].nil?
            raise StandardError, "xmlns attribute is not allowed in annotations"
          end

          # TC 70-71: RNG namespace attributes forbidden
          if name_parts[:prefix] && @namespace_prefixes
            ns_uri = @namespace_prefixes[name_parts[:prefix]]
            if ns_uri == RNG_NAMESPACE
              raise StandardError, "attributes in the RELAX NG namespace are not allowed"
            end
          end

          result[:attributes] << {
            name: name_parts[:local],
            namespace: name_parts[:prefix],
            value: value,
          }
        elsif ann.key?(:elem_content)
          # Foreign element
          content_data = extract_annotation_content(ann[:elem_content])

          # TC 70-71: RNG namespace elements forbidden
          if name_parts[:prefix] && @namespace_prefixes
            ns_uri = @namespace_prefixes[name_parts[:prefix]]
            if ns_uri == RNG_NAMESPACE
              raise StandardError, "elements in the RELAX NG namespace are not allowed"
            end
          end

          result[:elements] << {
            name: name_parts[:local],
            namespace: name_parts[:prefix],
            content: content_data[:text],
            attributes: content_data[:attributes],
            elements: content_data[:elements],
          }
        end
      end

      result
    end

    # Extract qualified name (prefix:local or just local)
    #
    # @param qname [Hash] Qualified name from parse tree
    # @return [Hash] Hash with :prefix and :local keys
    def extract_qualified_name(qname)
      return { prefix: nil, local: "" } unless qname

      prefix = nil
      if qname[:prefix]
        prefix = extract_identifier(qname[:prefix])
      end

      local = extract_identifier(qname[:local_name])

      { prefix: prefix, local: local }
    end

    # Extract annotation content (text and nested items)
    #
    # @param content [Hash, nil] Annotation content from parse tree
    # @return [Hash] Hash with :text, :attributes, :elements
    def extract_annotation_content(content)
      result = { text: "", attributes: [], elements: [] }
      return result if content.nil?

      items = []

      # Get first item
      if content[:first]
        items << content[:first]
      end

      # Get rest of items
      if content[:rest]
        rest = content[:rest]
        rest = [rest] unless rest.is_a?(Array)
        items.concat(rest)
      end

      # Process each item
      text_parts = []
      items.each do |item|
        if item[:text]
          # String literal
          text_parts << extract_string_literal(item[:text])
        elsif item[:ann_name]
          # Nested annotation item
          nested = extract_annotations({ annotations: item })
          result[:attributes].concat(nested[:attributes])
          result[:elements].concat(nested[:elements])
        end
      end

      result[:text] = text_parts.join unless text_parts.empty?
      result
    end

    # Extract string from string_parts array
    #
    # @param parts [Array, String] String parts
    # @return [String] Extracted string
    def extract_string_parts(parts)
      return "" unless parts
      return parts if parts.is_a?(String)
      return parts.str if parts.respond_to?(:str)

      return "" unless parts.is_a?(Array)

      parts.map do |part|
        if part.is_a?(String)
          part
        elsif part.respond_to?(:str)
          part.str
        elsif part[:hex_escape]
          # Handle \x{HEX}
          hex_str = extract_parslet_string(part[:hex_escape][:hex])
          [hex_str.to_i(16)].pack("U")
        elsif part[:char_escape]
          # Handle \", \\, \n, \r, \t, and RELAX NG class escapes \i, \c, \d, \w
          char = extract_parslet_string(part[:char_escape][:char])
          case char
          when '"' then '"'
          when "\\" then "\\"
          when "n" then "\n"
          when "r" then "\r"
          when "t" then "\t"
          when "i" then "\\i"
          when "c" then "\\c"
          when "d" then "\\d"
          when "w" then "\\w"
          else char
          end
        elsif part[:char]
          # Regular character (plain char in string literal)
          extract_parslet_string(part[:char])
        else
          part.to_s
        end
      end.join
    end

    # Extract string from Parslet::Slice or String
    #
    # @param obj [Parslet::Slice, String] Object to extract
    # @return [String] Extracted string
    def extract_parslet_string(obj)
      obj.respond_to?(:str) ? obj.str : obj.to_s
    end

    # Build normalized grammar tree
    #
    # Handles different tree structures:
    # - Top-level includes: Creates empty grammar
    # - Grammar block: Extracts inner grammar
    # - Flat: Uses tree as-is
    #
    # @return [Hash] Normalized grammar tree
    def build_grammar_tree
      # Process raw_trailing if present (needs to happen before tree building)
      process_raw_trailing!(@tree) if @tree[:raw_trailing]

      if top_level_includes?
        build_top_level_includes_grammar
      elsif grammar_block?
        build_grammar_block_grammar
      else
        build_flat_grammar
      end
    end

    # Check if tree has top-level includes
    #
    # @return [Boolean]
    def top_level_includes?
      @tree.key?(:top_includes)
    end

    # Check if tree has grammar block wrapper
    #
    # @return [Boolean]
    def grammar_block?
      @tree.key?(:inner_grammar)
    end

    # Build grammar for top-level includes structure
    #
    # @return [Hash]
    def build_top_level_includes_grammar
      definitions = []

      # Add the top-level includes first
      definitions.concat(@tree[:top_includes]) if @tree[:top_includes]

      # Then add any trailing definitions
      definitions.concat(@tree[:trailing_definitions]) if @tree[:trailing_definitions]

      {
        start: nil,
        includes: @tree[:top_includes] || [],
        definitions: definitions,
      }
    end

    # Build grammar for grammar block structure
    #
    # @return [Hash]
    def build_grammar_block_grammar
      grammar = @tree[:inner_grammar].dup

      # Normalize :includes and :patterns into :definitions
      if grammar.key?(:includes) || grammar.key?(:patterns)
        definitions = []
        definitions.concat(grammar.delete(:includes)) if grammar[:includes]
        definitions.concat(grammar.delete(:patterns)) if grammar[:patterns]
        grammar[:definitions] = definitions unless definitions.empty?
      end

      merge_trailing_definitions(grammar)
      grammar
    end

    # Build grammar for flat structure
    #
    # @return [Hash]
    def build_flat_grammar
      grammar = @tree.dup

      # Normalize :includes and :patterns into :definitions for flat grammars too
      if grammar.key?(:includes) || grammar.key?(:patterns)
        definitions = []
        definitions.concat(grammar.delete(:includes)) if grammar[:includes]
        definitions.concat(grammar.delete(:patterns)) if grammar[:patterns]
        grammar[:definitions] = definitions unless definitions.empty?
      end

      grammar
    end

    # Merge trailing definitions into grammar
    #
    # @param grammar [Hash] Grammar to merge into
    def merge_trailing_definitions(grammar)
      return unless @tree[:trailing_definitions] && !@tree[:trailing_definitions].empty?

      grammar[:definitions] ||= []
      grammar[:definitions].concat(@tree[:trailing_definitions])
    end

    # Process raw override and grammar blocks recursively
    #
    # @param node [Hash, Array] Tree node to process
    def process_raw_overrides!(node)
      case node
      when Hash
        # Check for raw_override that needs parsing
        if node[:override]&.dig(:raw_override)
          parse_and_replace_override!(node)
        end

        # Check for raw_grammar that needs parsing (in grammar_block)
        if node[:raw_grammar]
          parse_and_replace_grammar!(node)
        end

        # Check for raw_patterns that need parsing (in flat grammar)
        if node[:raw_patterns]
          parse_and_replace_patterns!(node)
        end

        # Recursively process all hash values
        node.each_value { |v| process_raw_overrides!(v) }
      when Array
        # Recursively process array elements
        node.each { |item| process_raw_overrides!(item) }
      end
    end

    # Parse raw override and replace in-place
    #
    # @param node [Hash] Node containing :override with :raw_override
    def parse_and_replace_override!(node)
      raw = node[:override][:raw_override]
      text = extract_raw_text(raw)

      if text.strip.empty?
        # Empty override - remove it
        node.delete(:override)
      else
        # Parse with proper scoping
        parsed = parse_override_with_scope(text)
        node[:override] = parsed
      end
    end

    # Extract text from raw_override (array of Parslet::Slice objects)
    #
    # @param raw [Array, Parslet::Slice, String] Raw content
    # @return [String] Extracted text
    def extract_raw_text(raw)
      case raw
      when Array
        raw.map { |item| item.respond_to?(:str) ? item.str : item.to_s }.join
      when String
        raw
      else
        raw.respond_to?(:str) ? raw.str : raw.to_s
      end
    end

    # Parse and replace raw grammar block
    #
    # @param node [Hash] Node containing :raw_grammar
    def parse_and_replace_grammar!(node)
      raw = node[:raw_grammar]
      text = extract_raw_text(raw)

      # Remove raw_grammar first
      node.delete(:raw_grammar)

      if text.strip.empty?
        # Empty grammar - use empty structure
        node.merge!(start: nil, includes: [], patterns: [])
      else
        # Parse with proper scoping
        parsed = parse_grammar_with_scope(text)
        # If the node is already an inner_grammar (has raw_grammar as its only key),
        # merge parsed result directly into the node instead of nesting
        if node.empty?
          node.merge!(parsed)
        else
          node[:inner_grammar] = parsed
        end
      end
    end

    # Parse override content with proper scoping
    #
    # Uses a scoped grammar: start + patterns (no includes)
    #
    # @param text [String] Override block content
    # @return [Hash] Parsed structure with :start and :patterns
    def parse_override_with_scope(text)
      # Create temporary parser with override-specific root
      parser = Rng::RncParser.new

      # Parse using grammar rule (which is what override contains)
      # Grammar contains: start (optional) + includes (skip) + patterns
      result = parser.grammar.parse(text.strip)

      {
        start: result[:start],
        patterns: result[:patterns] || [],
      }
    rescue Parslet::ParseFailed => e
      # Graceful fallback for parse errors
      # Warnings suppressed by default as fallback behavior is correct and intentional
      # Set RNG_VERBOSE=1 to enable warnings for debugging
      warn "Warning: Failed to parse override block: #{e.message}" if ENV['RNG_VERBOSE']
      { start: nil, patterns: [] }
    end

    # Parse grammar content with proper scoping
    #
    # Uses full grammar rule: start + includes + patterns
    #
    # @param text [String] Grammar block content
    # @return [Hash] Parsed structure
    def parse_grammar_with_scope(text)
      parser = Rng::RncParser.new

      # Parse using grammar rule
      parser.grammar.parse(text.strip)

      # Return grammar structure
    rescue Parslet::ParseFailed => e
      # Graceful fallback for parse errors
      # Warnings suppressed by default as fallback behavior is correct and intentional
      # Set RNG_VERBOSE=1 to enable warnings for debugging
      warn "Warning: Failed to parse grammar block: #{e.message}" if ENV['RNG_VERBOSE']
      { start: nil, includes: [], patterns: [] }
    end

    # Parse and replace raw patterns in flat grammar
    #
    # @param node [Hash] Node containing :raw_patterns
    def parse_and_replace_patterns!(node)
      raw = node[:raw_patterns]
      text = extract_raw_text(raw)

      if text.strip.empty?
        # Empty patterns
        node[:patterns] = []
      else
        # Parse patterns content with proper scoping
        parsed = parse_patterns_with_scope(text)
        node[:patterns] = parsed
      end

      # Remove raw_patterns after processing
      node.delete(:raw_patterns)
    end

    # Parse patterns content with proper scoping
    #
    # Parses multiple patterns (named_pattern | div | element)*
    #
    # @param text [String] Patterns content
    # @return [Array] Parsed patterns
    def parse_patterns_with_scope(text)
      parser = Rng::RncParser.new

      # Create a custom rule for patterns only
      # We need to parse: (named_pattern | div_block | element_def)*
      patterns_rule = (
        (parser.named_pattern | parser.div_block.as(:div) | parser.element_def.as(:top_element)) >>
        parser.whitespace
      ).repeat

      result = patterns_rule.parse(text.strip)

      # Result should be an array of patterns
      result.is_a?(Array) ? result : [result]
    rescue Parslet::ParseFailed => e
      # Graceful fallback for parse errors
      # Warnings suppressed by default as fallback behavior is correct and intentional
      # Set RNG_VERBOSE=1 to enable warnings for debugging
      warn "Warning: Failed to parse patterns: #{e.message}" if ENV['RNG_VERBOSE']
      []
    end

    # Process and replace raw_trailing content
    #
    # @param node [Hash] Node containing :raw_trailing
    def process_raw_trailing!(node)
      raw = node[:raw_trailing]
      text = extract_raw_text(raw)

      if text.strip.empty?
        node[:trailing_definitions] = []
      else
        # Parse trailing definitions
        parsed = parse_patterns_with_scope(text)
        node[:trailing_definitions] = parsed
      end

      # Remove raw_trailing after processing
      node.delete(:raw_trailing)
    end

    # Add metadata (both legacy and new) to grammar tree
    def add_metadata_to_grammar
      # Legacy namespace (backward compatibility)
      @grammar_tree[:namespace] = @namespace if @namespace

      # New preamble metadata (if present)
      if @preamble
        if @preamble.default_namespace
          @grammar_tree[:default_namespace] =
            @preamble.default_namespace
          # Also set legacy namespace format for converter
          @grammar_tree[:namespace] = {
            namespace_uri: @preamble.default_namespace,
          }
        end
        unless @preamble.namespace_map.empty?
          @grammar_tree[:namespace_map] =
            @preamble.namespace_map
        end
        unless @preamble.datatype_map.empty?
          @grammar_tree[:datatype_map] =
            @preamble.datatype_map
        end
      end
    end
  end
end
