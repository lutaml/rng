# frozen_string_literal: true

require 'nokogiri'
require 'set'

module Rng
  # RncToRngConverter converts RNC parse trees to RNG XML format.
  #
  # This class takes the parse tree output from the Parslet RNC parser and
  # converts it to RNG XML using Nokogiri's XML builder. The resulting XML
  # can then be deserialized into Grammar objects using Lutaml::Model.
  #
  # @example Convert a parse tree to RNG XML
  #   tree = parser.parse(rnc_content)
  #   converter = Rng::RncToRngConverter.new
  #   rng_xml = converter.convert(tree)
  #   grammar = Rng::Grammar.from_xml(rng_xml)
  class RncToRngConverter
    RNG_NAMESPACE = 'http://relaxng.org/ns/structure/1.0'

    # Convert a parse tree to RNG XML
    #
    # @param tree [Hash] The parse tree from RncParser
    # @return [String] RNG XML string
    def convert(tree)
      # Track defined names for augmentation support
      defined_names = Set.new

      # Check if we need the annotations namespace
      @has_documentation = has_documentation_comments?(tree)

      # Collect prefixed namespace declarations from preamble
      @namespace_prefixes = {}
      collect_namespace_prefixes(tree[:preamble_items])

      # Validate that element notations in preamble annotations are only used with element/attribute patterns
      validate_preamble_element_notation_usage(tree[:preamble_items], tree[:definitions])

      builder = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
        grammar_attrs = { xmlns: 'http://relaxng.org/ns/structure/1.0' }
        if @has_documentation
          grammar_attrs[:'xmlns:a'] =
            'http://relaxng.org/ns/compatibility/annotations/1.0'
        end

        xml.grammar(grammar_attrs) do
          # Add namespace if present
          if tree[:namespace]
            xml.parent[:ns] =
              process_string_literal(tree[:namespace][:namespace_uri])
          end

          # Add datatype library if present
          if tree[:datatype_library]
            xml.parent[:datatypeLibrary] =
              process_string_literal(tree[:datatype_library][:uri])
          elsif tree[:datatype_map] && !tree[:datatype_map].empty?
            # From ParseTreeProcessor - datatype_map is {prefix => uri}
            # Use the first (typically only) datatype library
            xml.parent[:datatypeLibrary] = tree[:datatype_map].values.first
          end

          # If no explicit start but we have top-level elements, wrap them in start
          has_explicit_start = tree[:start] && tree[:start][:start_pattern]
          has_top_elements = tree[:definitions]&.any? do |d|
            d.key?(:top_element)
          end
          has_top_choice = tree[:definitions]&.any? do |d|
            d.key?(:top_choice)
          end

          if has_explicit_start
            # Process explicit start pattern
            xml.start do
              add_documentation(xml, tree[:start]) if tree[:start][:docs]
              process_pattern_list(xml, tree[:start][:start_pattern])
            end
          elsif has_top_choice
            # No explicit start, but has top-level choice - wrap in start with choice
            first_choice = tree[:definitions].find { |d| d.key?(:top_choice) }
            xml.start do
              xml.choice do
                process_content_item(xml, first_choice[:top_choice][:first])
                first_choice[:top_choice][:choice_items]&.each do |item|
                  process_content_item(xml, item)
                end
              end
            end
          elsif has_top_elements
            # No explicit start, but has top-level elements - wrap first one in start
            xml.start do
              first_element = tree[:definitions].find do |d|
                d.key?(:top_element)
              end
              process_content_item(xml, first_element[:top_element])
            end
          end

          # Process named patterns and remaining top-level elements
          tree[:definitions]&.each_with_index do |def_item, idx|
            if def_item.key?(:href)
              # Include directive
              href = process_string_literal(def_item[:href])

              if def_item[:override]
                # Include with override block - override is properly scoped
                override = def_item[:override]

                # Check if override has any content
                has_content = (override[:start] && override[:start][:start_pattern]) ||
                              (override[:patterns] && !override[:patterns].empty?)

                if has_content
                  xml.include(href: href) do
                    # Process override start if present
                    if override[:start] && override[:start][:start_pattern]
                      xml.start do
                        process_pattern_list(xml,
                                             override[:start][:start_pattern])
                      end
                    end

                    # Process override patterns (named patterns, div blocks, and top-level elements)
                    override[:patterns]&.each do |pattern_item|
                      if pattern_item.key?(:name)
                        # Named pattern in override
                        name = process_identifier(pattern_item[:name])
                        operator = pattern_item[:operator] ? extract_string(pattern_item[:operator]) : '='

                        if operator == '='
                          xml.define(name: name) do
                            if pattern_item[:docs]
                              add_documentation(xml,
                                                pattern_item)
                            end
                            process_pattern_list(xml, pattern_item[:pattern])
                          end
                        else
                          combine_type = operator == '|=' ? 'choice' : 'interleave'
                          xml.define(name: name, combine: combine_type) do
                            if pattern_item[:docs]
                              add_documentation(xml,
                                                pattern_item)
                            end
                            process_pattern_list(xml, pattern_item[:pattern])
                          end
                        end
                      elsif pattern_item.key?(:top_element)
                        # Top-level element in override
                        process_content_item(xml, pattern_item[:top_element])
                      elsif pattern_item.key?(:div)
                        # Div block in override
                        process_div_block(xml, pattern_item[:div])
                      end
                    end
                  end
                else
                  # Empty override block
                  xml.include(href: href)
                end
              else
                # Include without override block
                xml.include(href: href)
              end
            elsif def_item.key?(:name)
              # Named pattern - handle augmentation operators
              name = process_identifier(def_item[:name])
              operator = def_item[:operator] ? extract_string(def_item[:operator]) : '='

              if operator == '=' || !defined_names.include?(name)
                # First definition or normal definition
                xml.define(name: name) do
                  add_documentation(xml, def_item) if def_item[:docs]
                  process_pattern_list(xml, def_item[:pattern])
                end
                defined_names.add(name)
              else
                # Augmentation - use combine attribute
                combine_type = operator == '|=' ? 'choice' : 'interleave'
                xml.define(name: name, combine: combine_type) do
                  add_documentation(xml, def_item) if def_item[:docs]
                  process_pattern_list(xml, def_item[:pattern])
                end
              end
            elsif def_item.key?(:top_element) && has_explicit_start
              # Top-level element (only add if we already have explicit start)
              process_content_item(xml, def_item[:top_element])
            elsif def_item.key?(:top_element) && !has_explicit_start && idx.positive?
              # Additional top-level elements after the first (which is in start)
              process_content_item(xml, def_item[:top_element])
            elsif def_item.key?(:top_choice) && !has_explicit_start
              # Top-level choice already handled in start generation above, skip
            elsif def_item.key?(:div)
              # Div block for documentation and grouping
              process_div_block(xml, def_item[:div])
            elsif def_item.key?(:standalone)
              # Standalone pattern (bare wildcard, etc.)
              process_standalone_pattern(xml, def_item[:standalone])
            elsif def_item.key?(:foreign_name)
              # Foreign element annotation - emit as foreign element in RNG XML
              process_foreign_element(xml, def_item)
            end
          end
        end
      end

      builder.to_xml
    end

    private

    # Check if tree contains any documentation comments
    def has_documentation_comments?(tree)
      return false unless tree.is_a?(Hash)

      tree.each do |key, value|
        return true if %i[documentation docs].include?(key) && value

        if value.is_a?(Hash)
          return true if has_documentation_comments?(value)
        elsif value.is_a?(Array)
          value.each do |item|
            return true if item.is_a?(Hash) && has_documentation_comments?(item)
          end
        end
      end

      false
    end

    # Extract documentation text from doc_comments structure
    def extract_documentation(docs)
      return nil unless docs && docs[:documentation]

      doc_lines = docs[:documentation]
      doc_lines = [doc_lines] unless doc_lines.is_a?(Array)

      # Join all doc lines, stripping the leading space if present
      doc_lines.filter_map do |line|
        text = line[:doc_line]
        text = extract_string(text) if text
        # Strip leading space from ## comment
        text = text.sub(/^\s+/, '') if text
        text
      end.join("\n")
    end

    # Add documentation element if present
    def add_documentation(xml, item)
      return unless item[:docs]

      doc_text = extract_documentation(item[:docs])
      return unless doc_text && !doc_text.empty?

      xml.send(:'a:documentation', doc_text)
    end

    # Add annotations (foreign attributes and elements) if present
    def add_annotations(xml, item, processor = nil)
      return unless item[:annotations]

      # Use provided processor or create one
      proc = processor || ParseTreeProcessor.new({})

      # Extract annotations using processor
      annotations = proc.extract_annotations(item)

      # Add foreign attributes to parent element
      annotations[:attributes].each do |attr|
        attr_name = if attr[:namespace]
                      "#{attr[:namespace]}:#{attr[:name]}"
                    else
                      attr[:name]
                    end
        xml.parent[attr_name] = attr[:value]
      end

      # Add foreign elements as children
      annotations[:elements].each do |elem|
        elem_name = if elem[:namespace]
                      "#{elem[:namespace]}:#{elem[:name]}"
                    else
                      elem[:name]
                    end

        # Create foreign element with proper namespace handling
        xml.send(elem_name) do
          # Add nested attributes if present
          elem[:attributes].each do |nested_attr|
            nested_name = if nested_attr[:namespace]
                            "#{nested_attr[:namespace]}:#{nested_attr[:name]}"
                          else
                            nested_attr[:name]
                          end
            xml.parent[nested_name] = nested_attr[:value]
          end

          # Add text content if present
          xml.text(elem[:content]) if elem[:content] && !elem[:content].empty?

          # Add nested elements recursively
          elem[:elements].each do |nested_elem|
            # Recursively handle nested elements
            # TODO: Implement full nesting if needed
          end
        end
      end
    end

    # Extract clean string from Parslet::Slice or other objects
    #
    # @param obj [Object] The object to extract string from
    # @return [String] Clean string without position markers
    def extract_string(obj)
      if obj.respond_to?(:str)
        # Parslet::Slice - use .str to get clean string
        obj.str
      elsif obj.is_a?(String)
        obj
      else
        obj.to_s
      end
    end

    # Map of character escapes to actual characters
    CHAR_ESCAPE_MAP = {
      '"' => '"',
      '\\' => '\\',
      'n' => "\n",
      'r' => "\r",
      't' => "\t",
      # RELAX NG character class escapes - preserve backslash
      'i' => '\\i',
      'c' => '\\c',
      'd' => '\\d',
      'w' => '\\w'
    }.freeze

    # Validate Unicode code point
    #
    # @param code_point [Integer] The Unicode code point to validate
    # @param context [Symbol] Context where the character is used (:identifier or :string)
    # @return [Integer] The validated code point
    # @raise [ArgumentError] If the code point is invalid (surrogate or out of range)
    def validate_unicode_codepoint(code_point, context = :string)
      # Check for surrogate pairs (0xD800-0xDFFF)
      if code_point.between?(0xD800, 0xDFFF)
        raise ArgumentError,
              "Invalid Unicode: surrogate code point U+#{code_point.to_s(16).upcase} is not allowed"
      end

      # Check for out-of-range (> 0x10FFFF)
      if code_point > 0x10FFFF
        raise ArgumentError,
              "Invalid Unicode: code point U+#{code_point.to_s(16).upcase} exceeds maximum (U+10FFFF)"
      end

      # Check for whitespace in identifiers
      if context == :identifier
        char = [code_point].pack('U')
        if char.match?(/\s/)
          raise ArgumentError,
                "Invalid identifier: whitespace character U+#{code_point.to_s(16).upcase} is not allowed in identifiers"
        end
      end

      code_point
    end

    # Process escape sequences in parsed content
    #
    # @param parts [Array, Hash, String] The parts to process
    # @param context [Symbol] Context where the text is used (:identifier or :string)
    # @return [String] The processed string
    def process_escape_sequences(parts, context = :string)
      return '' unless parts
      return parts if parts.is_a?(String)

      parts = [parts] unless parts.is_a?(Array)

      parts.map do |part|
        case part
        when Hash
          if part[:hex_escape]
            # Convert hex to Unicode character with validation
            hex = extract_string(part[:hex_escape][:hex])
            code_point = hex.to_i(16)

            # DEBUG output
            puts "DEBUG: Processing hex escape: #{hex} -> code_point: 0x#{code_point.to_s(16).upcase}" if ENV['RNG_DEBUG']

            validate_unicode_codepoint(code_point, context)
            [code_point].pack('U')
          elsif part[:char_escape]
            # Map character escape
            char = extract_string(part[:char_escape][:char])
            CHAR_ESCAPE_MAP[char] || "\\#{char}"
          elsif part[:backslash_escape]
            # Backslash escape in identifier: \x -> x
            if part[:backslash_escape][:escaped_backslash]
              '\\'
            elsif part[:backslash_escape][:escaped_char]
              extract_string(part[:backslash_escape][:escaped_char])
            elsif part[:backslash_escape][:escaped_keyword]
              extract_string(part[:backslash_escape][:escaped_keyword])
            else
              extract_string(part[:backslash_escape])
            end
          elsif part[:char]
            # Regular character from identifier/string
            extract_string(part[:char])
          else
            # Fallback - extract as string
            extract_string(part)
          end
        else
          extract_string(part)
        end
      end.join
    end

    # Extract multi-line triple-quoted string content (no escape processing)
    def extract_multi_line_parts(parts)
      return '' unless parts
      return extract_string(parts) unless parts.is_a?(Array)

      parts.map { |p| extract_string(p) }.join
    end

    # Process identifier with potential escape sequences
    def process_identifier(id_node)
      return extract_string(id_node) unless id_node.is_a?(Hash)

      if id_node[:identifier_parts]
        process_escape_sequences(id_node[:identifier_parts], :identifier)
      elsif id_node[:identifier]
        extract_string(id_node[:identifier])
      else
        extract_string(id_node)
      end
    end

    # Collect prefixed namespace declarations from preamble items
    def collect_namespace_prefixes(preamble_items)
      return unless preamble_items

      # Handle single Parslet::Slice (when there's only one preamble item)
      items = preamble_items.is_a?(Parslet::Slice) ? [preamble_items] : preamble_items

      # Track seen annotation attributes for duplicate detection (across all notations)
      seen_ann_attrs = {}

      items.each do |item|
        # Skip non-Hash items (e.g., Parslet::Slice from annotation content)
        next unless item.is_a?(Hash)

        if item[:prefixed_ns]
          prefix_info = item[:prefixed_ns][:prefix]
          prefix = process_identifier(prefix_info)
          uri_info = item[:prefixed_ns][:uri]
          uri = process_string_literal(uri_info)

          # TC 13: xmlns prefix is reserved
          raise StandardError, "namespace prefix 'xmlns' is reserved" if prefix == 'xmlns'

          # TC 14: xmlns URI cannot be used as a namespace URI
          raise StandardError, "namespace URI 'http://www.w3.org/2000/xmlns' is reserved" if uri == 'http://www.w3.org/2000/xmlns'

          # TC 15: xml prefix must map to the XML namespace URI
          if prefix == 'xml' && uri != 'http://www.w3.org/XML/1998/namespace'
            raise StandardError,
                  "namespace prefix 'xml' must be bound to 'http://www.w3.org/XML/1998/namespace'"
          end

          # TC 16: XML namespace URI must use xml prefix
          if uri == 'http://www.w3.org/XML/1998/namespace' && prefix != 'xml'
            raise StandardError,
                  "namespace URI 'http://www.w3.org/XML/1998/namespace' must use prefix 'xml'"
          end

          @namespace_prefixes[prefix] = uri
        elsif item[:ann] && item[:ann][:ann_items]
          # Validate annotations in notations (wrapped in :ann hash)
          validate_preamble_annotations(item[:ann][:ann_items], seen_ann_attrs)
        elsif item[:ann_items]
          # Direct ann_items (backward compatibility)
          validate_preamble_annotations(item[:ann_items], seen_ann_attrs)
        end
      end
    end

    # Validate annotations in preamble notations (TC 11, 12, 18, 70, 71)
    def validate_preamble_annotations(ann_items, seen_ann_attrs)
      return unless ann_items

      items = ann_items.is_a?(Array) ? ann_items : [ann_items]

      items.each do |ann|
        next unless ann.is_a?(Hash)

        if ann[:ann_attr]
          validate_annotation_attribute(ann[:ann_attr], seen_ann_attrs)
        elsif ann[:ann_elem]
          # TC 71: RNG namespace elements in annotations are forbidden
          validate_annotation_element(ann[:ann_elem])
        end
      end
    end

    # Validate that element notations in preamble annotations are only used with element/attribute patterns
    # TC 80, 81: Element notations like x[] in annotations should only annotate element/attribute patterns
    def validate_preamble_element_notation_usage(preamble_items, patterns)
      return unless preamble_items && patterns

      # Check if preamble contains element notations
      preamble_items_array = preamble_items.is_a?(Array) ? preamble_items : [preamble_items]
      has_element_notation = false

      preamble_items_array.each do |item|
        next unless item.is_a?(Hash)

        if item[:ann] && item[:ann][:ann_items]
          ann_items = item[:ann][:ann_items]
          ann_items_array = ann_items.is_a?(Array) ? ann_items : [ann_items]
          ann_items_array.each do |ann|
            next unless ann.is_a?(Hash)

            if ann[:ann_elem]
              has_element_notation = true
              break
            end
          end
        end
        break if has_element_notation
      end

      return unless has_element_notation

      # Check if first pattern is element or attribute definition
      first_pattern = patterns.first
      return unless first_pattern

      is_element_or_attribute = first_pattern.key?(:top_element) ||
                                first_pattern.key?(:top_choice) ||
                                first_pattern.key?(:attribute_def)

      return if is_element_or_attribute

      raise StandardError, 'element notation in annotation must be used with element or attribute pattern'
    end

    # Validate a single annotation attribute in preamble
    def validate_annotation_attribute(ann_attr, seen_ann_attrs)
      name_node = ann_attr[:ann_name]
      ann_attr[:attr_value]

      # Extract prefix and local name
      prefix = name_node[:prefix] ? process_identifier(name_node[:prefix]) : nil
      local = process_identifier(name_node)

      # TC 11: Check for duplicate annotation attributes (same prefix:local)
      attr_key = prefix ? "#{prefix}:#{local}" : local
      raise StandardError, "duplicate annotation attribute '#{attr_key}'" if seen_ann_attrs.key?(attr_key)

      # TC 12: Check for duplicate even with different prefixes that map to same URI
      if prefix
        prefix_uri = @namespace_prefixes[prefix]
        if prefix_uri
          # Check if any previously seen prefix maps to the same URI with same local name
          seen_ann_attrs.each do |key, info|
            next unless info[:uri] == prefix_uri && info[:local] == local

            raise StandardError, "duplicate annotation attribute '#{attr_key}' (same as '#{key}')"
          end
        end
      end

      seen_ann_attrs[attr_key] = { uri: prefix_uri, local: local }

      # TC 18: xmlns attribute is forbidden in annotations
      raise StandardError, 'xmlns attribute is not allowed in annotations' if local == 'xmlns' && prefix.nil?

      # TC 70: RNG namespace attributes forbidden
      return unless prefix && @namespace_prefixes[prefix] == RNG_NAMESPACE

      raise StandardError, 'attributes in the RELAX NG namespace are not allowed'
    end

    # Validate a single annotation element in preamble
    def validate_annotation_element(ann_elem)
      name_node = ann_elem[:elem_name]

      # Extract prefix and local name
      prefix = name_node[:prefix] ? process_identifier(name_node[:prefix]) : nil
      process_identifier(name_node)

      # TC 71: RNG namespace elements forbidden
      return unless prefix && @namespace_prefixes[prefix] == RNG_NAMESPACE

      raise StandardError, 'elements in the RELAX NG namespace are not allowed'
    end

    # Resolve a namespace prefix to a URI
    # Returns the prefix itself if not found (for backward compatibility)
    def resolve_namespace_prefix(prefix)
      return prefix unless prefix

      @namespace_prefixes.fetch(prefix, prefix)
    end

    # Process string literal with optional concatenation
    #
    # @param str_node [Hash] String node from parse tree (can have :concatenations)
    # @return [String] Concatenated string value
    def process_string_literal(str_node)
      return '' unless str_node
      return str_node if str_node.is_a?(String)

      # Process base string with potential escapes
      base_str = if str_node[:multi_line_parts]
                   # Multi-line triple-quoted string: no escape processing
                   extract_multi_line_parts(str_node[:multi_line_parts])
                 elsif str_node[:string_parts]
                   process_escape_sequences(str_node[:string_parts])
                 elsif str_node[:string]
                   extract_string(str_node[:string])
                 else
                   ''
                 end

      # Handle concatenation
      return base_str unless str_node[:concatenations]

      parts = [base_str]
      concatenations = str_node[:concatenations]
      concatenations = [concatenations] unless concatenations.is_a?(Array)

      concatenations.each do |concat|
        next unless concat
        next unless concat.is_a?(Hash) # FIX: Validate concat is a Hash

        if concat[:concat_multi_line_parts]
          parts << extract_multi_line_parts(concat[:concat_multi_line_parts])
        elsif concat[:concat_string_parts]
          parts << process_escape_sequences(concat[:concat_string_parts])
        elsif concat[:concat_string]
          parts << extract_string(concat[:concat_string])
        end
      end

      parts.join
    end

    # Process a pattern which can be a single item or pattern_list structure
    def process_pattern_list(xml, pattern)
      # Handle new pattern_list structure with :first, :choice_items, :sequence_items
      if pattern.is_a?(Hash) && pattern.key?(:first)
        first_item = pattern[:first]

        if pattern[:interleave_items] && !pattern[:interleave_items].empty?
          # Interleave pattern - generate <interleave>
          xml.interleave do
            process_content_item(xml, first_item)
            pattern[:interleave_items].each do |item|
              process_content_item(xml, item)
            end
          end
        elsif pattern[:choice_items] && !pattern[:choice_items].empty?
          # Choice pattern - generate <choice>
          xml.choice do
            process_content_item(xml, first_item)
            pattern[:choice_items].each do |item|
              process_content_item(xml, item)
            end
          end
        elsif pattern[:sequence_items] && !pattern[:sequence_items].empty?
          # Sequence pattern - generate <group> if multiple items
          items = [first_item] + pattern[:sequence_items]
          if items.length == 1
            process_content_item(xml, items[0])
          else
            xml.group do
              items.each { |item| process_content_item(xml, item) }
            end
          end
        else
          # Single item
          process_content_item(xml, first_item)
        end
      elsif pattern.is_a?(Array)
        # Legacy array format (for backward compatibility)
        if pattern.length == 1
          process_content_item(xml, pattern[0])
        else
          xml.group do
            pattern.each { |item| process_content_item(xml, item) }
          end
        end
      else
        # Single item (direct hash)
        process_content_item(xml, pattern)
      end
    end

    def process_standalone_pattern(xml, item)
      if item.key?(:bare_any_name)
        # Bare anyName wildcard: *
        any_name_info = item[:bare_any_name]
        except_clause = any_name_info[:any_name_except]
        xml.element do
          xml.anyName do
            if except_clause
              xml.except_ do
                process_name_except(xml, except_clause, parent_type: :any_name)
              end
            end
          end
        end
      else
        # Fallback to content item processing
        process_content_item(xml, item)
      end
    end

    def process_content_item(xml, item)
      if item.key?(:type) && item.key?(:name)
        # Attribute definition (has both :type and :name keys)
        attrs = {}

        # Handle name wildcards or regular qualified names
        name_obj = item[:name]

        # Unwrap the extra :name level from name_class.as(:name)
        name_obj = name_obj[:name] if name_obj.is_a?(Hash) && name_obj.key?(:name)

        # Skip if name_obj is nil (shouldn't happen but be defensive)
        return if name_obj.nil?

        if name_obj.key?(:any_name)
          # anyName wildcard
          attr_name_type = :any_name
          except_clause = name_obj[:any_name][:except] if name_obj[:any_name].is_a?(Hash)
        elsif name_obj.key?(:ns_name)
          # nsName wildcard
          attr_name_type = :ns_name
          ns_prefix = process_identifier(name_obj[:ns_name][:prefix])
          except_clause = name_obj[:ns_name][:except] if name_obj[:ns_name].is_a?(Hash)
        elsif name_obj.key?(:local_name)
          # Regular qualified name
          attr_name_type = :qualified
          attrs[:name] = process_identifier(name_obj[:local_name])
          if name_obj[:prefix]
            attrs[:ns] =
              resolve_namespace_prefix(process_identifier(name_obj[:prefix]))
          end
        elsif name_obj.key?(:name_choice)
          # Name choice - generate choice of attributes
          attr_name_type = :name_choice
          name_choice = name_obj[:name_choice]
          # Collect all names in the choice
          all_names = [name_choice[:local_name]]
          name_choice[:name_choice_items]&.each do |nc_item|
            all_names << nc_item[:local_name] if nc_item[:local_name]
          end
        else
          # Fallback - treat as regular name
          attr_name_type = :qualified
          # name_obj might be the identifier directly
          attrs[:name] =
            name_obj[:identifier] ? extract_string(name_obj[:identifier]) : name_obj.to_s
        end

        # Check for occurrence marker
        occurrence = item[:occurrence]

        attribute_block = lambda do |xml_ctx|
          case attr_name_type
          when :any_name
            # Generate <attribute><anyName> with optional <except>
            xml_ctx.attribute do
              add_documentation(xml_ctx, item) if item[:docs]
              xml_ctx.anyName do
                if except_clause
                  xml_ctx.except_ do
                    process_name_except(xml_ctx, except_clause, parent_type: :any_name)
                  end
                end
              end
              process_attribute_type(xml_ctx, item[:type])
            end
          when :ns_name
            # Generate <attribute><nsName> with ns attribute and optional <except>
            xml_ctx.attribute do
              add_documentation(xml_ctx, item) if item[:docs]
              xml_ctx.nsName(ns: ns_prefix) do
                if except_clause
                  xml_ctx.except_ do
                    process_name_except(xml_ctx, except_clause, parent_type: :ns_name)
                  end
                end
              end
              process_attribute_type(xml_ctx, item[:type])
            end
          when :name_choice
            # Generate <attribute><choice><name>...<name>...</choice>...</attribute>
            add_documentation(xml_ctx, item) if item[:docs]
            xml_ctx.attribute do
              xml_ctx.choice do
                all_names.each do |name_info|
                  xml_ctx.name(process_identifier(name_info))
                end
              end
              process_attribute_type(xml_ctx, item[:type])
            end
          else
            # Regular named attribute
            xml_ctx.attribute(attrs) do
              add_documentation(xml_ctx, item) if item[:docs]
              process_attribute_type(xml_ctx, item[:type])
            end
          end
        end

        if occurrence
          # Wrap in occurrence element
          occurrence_tag = case occurrence.to_s
                           when '*' then 'zeroOrMore'
                           when '+' then 'oneOrMore'
                           when '?' then 'optional'
                           end
          xml.send(occurrence_tag) do
            attribute_block.call(xml)
          end
        else
          attribute_block.call(xml)
        end
      elsif item.key?(:name)
        # Element definition
        attrs = {}

        # Handle name wildcards or regular qualified names
        name_obj = item[:name]

        # Unwrap the extra :name level from name_class.as(:name)
        name_obj = name_obj[:name] if name_obj.is_a?(Hash) && name_obj.key?(:name)

        # Unwrap name_choice from name_class.as(:name_choice)
        name_obj = name_obj[:name_choice] if name_obj.is_a?(Hash) && name_obj.key?(:name_choice)

        if name_obj.key?(:any_name)
          # anyName wildcard - no name attribute needed, will be handled separately
          element_name_type = :any_name
          except_clause = name_obj[:any_name][:except] if name_obj[:any_name].is_a?(Hash)
        elsif name_obj.key?(:ns_name)
          # nsName wildcard
          element_name_type = :ns_name
          ns_prefix = process_identifier(name_obj[:ns_name][:prefix])
          except_clause = name_obj[:ns_name][:except] if name_obj[:ns_name].is_a?(Hash)
        elsif name_obj.key?(:local_name)
          # Check if this is a choice between multiple names (e.g., name1|name2|name3)
          if name_obj.key?(:name_choice_items) && name_obj[:name_choice_items].is_a?(Array) && !name_obj[:name_choice_items].empty?
            # Choice between multiple names
            element_name_type = :name_choice
            choice_names = [name_obj[:local_name]] + name_obj[:name_choice_items].map { |n| n[:local_name] || n }
          else
            # Regular qualified name
            element_name_type = :qualified
            attrs[:name] = process_identifier(name_obj[:local_name])
            if name_obj[:prefix]
              attrs[:ns] =
                resolve_namespace_prefix(process_identifier(name_obj[:prefix]))
            end
          end
        else
          # Fallback - treat as regular name
          element_name_type = :qualified
          # name_obj might be the identifier directly
          attrs[:name] =
            name_obj[:identifier] ? extract_string(name_obj[:identifier]) : name_obj.to_s
        end

        # Determine if we need occurrence wrapper
        occurrence = item[:occurrence]

        element_block = lambda do |xml_ctx|
          case element_name_type
          when :any_name
            # Generate <anyName> with optional <except>
            xml_ctx.element do
              add_documentation(xml_ctx, item) if item[:docs]
              xml_ctx.anyName do
                if except_clause
                  xml_ctx.except_ do
                    process_name_except(xml_ctx, except_clause, parent_type: :any_name)
                  end
                end
              end
              process_element_content(xml_ctx, item[:content]) if item[:content]
            end
          when :ns_name
            # Generate <nsName> with ns attribute and optional <except>
            xml_ctx.element do
              add_documentation(xml_ctx, item) if item[:docs]
              xml_ctx.nsName(ns: ns_prefix) do
                if except_clause
                  xml_ctx.except_ do
                    process_name_except(xml_ctx, except_clause, parent_type: :ns_name)
                  end
                end
              end
              process_element_content(xml_ctx, item[:content]) if item[:content]
            end
          when :name_choice
            # Element with choice of names (e.g., element foo|bar { ... })
            xml_ctx.element do
              add_documentation(xml_ctx, item) if item[:docs]
              xml_ctx.choice do
                choice_names.each do |name_part|
                  name_str = if name_part.is_a?(Hash) && name_part[:identifier_parts]
                               process_identifier(name_part)
                             elsif name_part.is_a?(Hash) && name_part[:local_name]
                               process_identifier(name_part[:local_name])
                             elsif name_part.is_a?(Hash) && name_part[:prefix]
                               process_identifier(name_part)
                             else
                               name_part.to_s
                             end
                  xml_ctx.name(name_str)
                end
              end
              process_element_content(xml_ctx, item[:content]) if item[:content]
            end
          else
            # Regular named element
            xml_ctx.element(attrs) do
              add_documentation(xml_ctx, item) if item[:docs]
              process_element_content(xml_ctx, item[:content]) if item[:content]
            end
          end
        end

        if occurrence
          # Wrap in occurrence element
          occurrence_tag = case occurrence.to_s
                           when '*' then 'zeroOrMore'
                           when '+' then 'oneOrMore'
                           when '?' then 'optional'
                           end

          xml.send(occurrence_tag) do
            element_block.call(xml)
          end
        else
          element_block.call(xml)
        end
      elsif item.key?(:text)
        xml.parent << Nokogiri::XML::Node.new('text', xml.doc)
      elsif item.key?(:empty)
        xml.parent << Nokogiri::XML::Node.new('empty', xml.doc)
      elsif item.key?(:not_allowed)
        xml.parent << Nokogiri::XML::Node.new('notAllowed', xml.doc)
      elsif item.key?(:list_content)
        xml.list do
          process_list_content(xml, item[:list_content])
        end
      elsif item.key?(:parent_pattern)
        xml.parentRef(name: process_identifier(item[:parent_pattern]))
      elsif item.key?(:external_href)
        xml.externalRef(href: process_string_literal(item[:external_href]))
      elsif item.key?(:group)
        occurrence = item[:occurrence]

        if occurrence
          occurrence_tag = case occurrence.to_s
                           when '*' then 'zeroOrMore'
                           when '+' then 'oneOrMore'
                           when '?' then 'optional'
                           end

          xml.send(occurrence_tag) do
            xml.group do
              process_element_content(xml, item[:group])
            end
          end
        else
          xml.group do
            process_element_content(xml, item[:group])
          end
        end
      elsif item.key?(:mixed_content)
        # Mixed content pattern
        xml.mixed do
          process_element_content(xml, item[:mixed_content])
        end
      elsif item.key?(:ref)
        # Reference to a named pattern
        ref_name = process_identifier(item[:ref])
        raise StandardError, "subtraction operator '-' cannot be used as a pattern" if ref_name == '-'

        occurrence = item[:occurrence]

        if occurrence
          occurrence_tag = case occurrence.to_s
                           when '*' then 'zeroOrMore'
                           when '+' then 'oneOrMore'
                           when '?' then 'optional'
                           end

          xml.send(occurrence_tag) do
            xml.ref(name: ref_name)
          end
        else
          xml.ref(name: ref_name)
        end
      elsif item.key?(:prefix) && item.key?(:type)
        # Datatype reference (e.g., xsd:string { maxLength = "100" })
        data_attrs = {
          type: process_identifier(item[:type]),
          datatypeLibrary: 'http://www.w3.org/2001/XMLSchema-datatypes'
        }
        if item[:params]
          xml.data(data_attrs) do
            params = item[:params].is_a?(Array) ? item[:params] : [item[:params]]
            params.each do |param|
              param_name = process_identifier(param[:param_name])
              param_value = process_string_literal(param[:param_value])
              xml.param(param_value, name: param_name)
            end
          end
        else
          xml.data(data_attrs)
        end
      elsif item.key?(:value)
        # Value literal (string) in element content
        xml.value(process_string_literal(item[:value]))
      elsif item.key?(:grammar_block)
        # Inline grammar block
        grammar_data = item[:grammar_block]
        inner = grammar_data[:inner_grammar] || grammar_data
        xml.grammar(xmlns: 'http://relaxng.org/ns/structure/1.0') do
          # Process start
          if inner[:start]
            xml.start do
              start_pattern = inner[:start]
              if start_pattern.is_a?(Hash) && start_pattern.key?(:start_pattern)
                process_pattern_list(xml,
                                     start_pattern[:start_pattern])
              end
            end
          end
          # Process patterns/definitions
          patterns = inner[:definitions] || inner[:patterns] || []
          patterns.each do |pattern|
            if pattern.is_a?(Hash) && pattern.key?(:name) && pattern.key?(:pattern)
              # Named pattern (define)
              define_name = process_identifier(pattern[:name])
              xml.define(name: define_name) do
                process_pattern_list(xml, pattern[:pattern])
              end
            else
              process_content_item(xml, pattern)
            end
          end
        end
      end
    end

    # Process element content which may have choice_items and sequence_items
    def process_element_content(xml, content)
      return unless content

      # Handle new structure: {:first, :choice_items, :sequence_items}
      if content.is_a?(Hash) && content.key?(:first)
        first_item = content[:first]

        if content[:interleave_items] && !content[:interleave_items].empty?
          # This is an interleave
          xml.interleave do
            process_content_item(xml, first_item)
            content[:interleave_items].each do |item|
              process_content_item(xml, item)
            end
          end
        elsif content[:choice_items] && !content[:choice_items].empty?
          # This is a choice
          xml.choice do
            process_content_item(xml, first_item)
            content[:choice_items].each do |choice|
              process_content_item(xml, choice)
            end
            # After choice items, if we have sequence_items, process them too
            first_item[:sequence_items]&.each do |seq|
              process_content_item(xml, seq)
            end
          end
        elsif content[:sequence_items] && !content[:sequence_items].empty?
          # This is a sequence - process all items
          process_content_item(xml, first_item)
          content[:sequence_items].each { |seq| process_content_item(xml, seq) }
        elsif first_item.is_a?(Array)
          # Multiple items in first position - process as sequence
          first_item.each { |item| process_content_item(xml, item) }
        else
          # Single item
          process_content_item(xml, first_item)
        end
        return
      end

      # Legacy handling: Content might be an array directly or a hash with items
      items = if content.is_a?(Array)
                content
              elsif content.is_a?(Hash)
                [content]
              else
                return
              end

      # Check if we have choice_items (| separated)
      first_item = items[0]
      if first_item.is_a?(Hash) && first_item.key?(:choice_items) && !first_item[:choice_items].empty?
        # This is a choice
        xml.choice do
          process_content_item(xml, first_item)
          first_item[:choice_items].each do |choice|
            process_content_item(xml, choice)
          end
          # After choice items, if we have sequence_items, process them too
          first_item[:sequence_items]&.each do |seq|
            process_content_item(xml, seq)
          end
        end
        return
      end

      # This is a sequence items handling
      if first_item.is_a?(Hash) && first_item.key?(:sequence_items) && !first_item[:sequence_items].empty?
        # This is a sequence - process all items
        process_content_item(xml, first_item)
        first_item[:sequence_items].each do |seq|
          process_content_item(xml, seq)
        end
        return
      end

      # Regular sequence - just process items
      if items.length == 1
        process_content_item(xml, items[0])
      else
        items.each { |item| process_content_item(xml, item) }
      end
    end

    # Process list content - handles datatypes and text with occurrence markers
    def process_list_content(xml, list_content)
      return unless list_content

      # Handle new structure: {:first, :sequence_items}
      if list_content.is_a?(Hash) && list_content.key?(:first)
        first_item = list_content[:first]
        items = [first_item]
        items += list_content[:sequence_items] if list_content[:sequence_items] && !list_content[:sequence_items].empty?

        items.each do |item|
          process_list_item(xml, item)
        end
      else
        # Single item
        process_list_item(xml, list_content)
      end
    end

    # Process a single list content item (datatype or text with optional occurrence)
    def process_list_item(xml, item)
      occurrence = item[:occurrence]&.to_s

      item_block = lambda do |xml_ctx|
        if item.key?(:text)
          xml_ctx.parent << Nokogiri::XML::Node.new('text', xml_ctx.doc)
        elsif item.key?(:prefix)
          # Datatype reference
          data_attrs = {
            type: process_identifier(item[:type]),
            datatypeLibrary: 'http://www.w3.org/2001/XMLSchema-datatypes'
          }
          xml_ctx.data(data_attrs)
        elsif item.key?(:ref)
          # Reference to named pattern
          ref_name = process_identifier(item[:ref])
          raise StandardError, "subtraction operator '-' cannot be used as a pattern" if ref_name == '-'

          xml_ctx.ref(name: ref_name)
        end
      end

      if occurrence
        occurrence_tag = case occurrence
                         when '*' then 'zeroOrMore'
                         when '+' then 'oneOrMore'
                         when '?' then 'optional'
                         end
        xml.send(occurrence_tag) do
          item_block.call(xml)
        end
      else
        item_block.call(xml)
      end
    end

    # Process name except clause for wildcards
    def process_name_except(xml, except_clause, parent_type: nil)
      # Validate name class subtraction rules
      validate_name_except(except_clause, parent_type) if parent_type

      # except_clause can be a single qualified_name, ns_name, or multiple names
      if except_clause.is_a?(Hash) && except_clause.key?(:local_name)
        # Single name
        xml.name(process_identifier(except_clause[:local_name]))
      elsif except_clause.is_a?(Hash) && except_clause.key?(:ns_name)
        # nsName - namespace-qualified wildcard
        ns_name_info = except_clause[:ns_name]
        ns_prefix = process_identifier(ns_name_info[:prefix])
        xml.nsName(ns: ns_prefix)
      elsif except_clause.is_a?(Hash) && except_clause.key?(:any_name)
        # anyName - unprefixed wildcard
        xml.anyName
      elsif except_clause.is_a?(Array)
        # Multiple names - wrap in choice
        except_clause.each do |name|
          if name.is_a?(Hash) && name.key?(:local_name)
            xml.name(process_identifier(name[:local_name]))
          elsif name.is_a?(Hash) && name.key?(:ns_name)
            ns_prefix = process_identifier(name[:ns_name][:prefix])
            xml.nsName(ns: ns_prefix)
          elsif name.is_a?(Hash) && name.key?(:any_name)
            xml.anyName
          end
        end
      end
    end

    def validate_name_except(except_clause, parent_type)
      items = except_clause.is_a?(Array) ? except_clause : [except_clause]
      items.each do |item|
        next unless item.is_a?(Hash)

        if parent_type == :any_name
          # anyName except must not contain anyName
          raise StandardError, 'anyName except must not contain anyName' if item.key?(:any_name)
        elsif parent_type == :ns_name
          # nsName except must contain only name elements
          raise StandardError, 'nsName except must not contain anyName' if item.key?(:any_name)
          raise StandardError, 'nsName except must not contain nsName' if item.key?(:ns_name)
        end
      end
    end

    # Process attribute type content (factored out for wildcard support)
    def process_attribute_type(xml, type_info)
      if type_info == 'text' || (type_info.is_a?(Hash) && type_info.key?(:text_type))
        xml.parent << Nokogiri::XML::Node.new('text', xml.doc)
      elsif type_info.is_a?(Hash) && type_info.key?(:value_choice)
        # Choice of value literals
        xml.choice do
          # First value (before the choice operator)
          xml.value(process_string_literal(type_info[:value]))
          # Remaining values (after | operators)
          type_info[:value_choice].each do |val|
            xml.value(process_string_literal(val[:value]))
          end
        end
      elsif type_info.is_a?(Hash) && type_info.key?(:value)
        # Single value literal
        xml.value(process_string_literal(type_info[:value]))
      elsif type_info.is_a?(Hash) && type_info.key?(:prefix)
        # Datatype reference
        data_attrs = {
          type: process_identifier(type_info[:type]),
          datatypeLibrary: 'http://www.w3.org/2001/XMLSchema-datatypes'
        }

        # Check if datatype has parameters
        if type_info[:params]
          xml.data(data_attrs) do
            # Process each parameter
            params = type_info[:params].is_a?(Array) ? type_info[:params] : [type_info[:params]]
            params.each do |param|
              param_name = process_identifier(param[:param_name])
              param_value = process_string_literal(param[:param_value])
              xml.param(param_value, name: param_name)
            end
          end
        else
          xml.data(data_attrs)
        end
      end
    end

    # Process data parameters (e.g., maxLength = "100")
    def process_data_params(xml, params)
      params = [params] unless params.is_a?(Array)
      params.each do |param|
        param_name = process_identifier(param[:param_name])
        param_value = process_string_literal(param[:param_value])
        xml.param(param_value, name: param_name)
      end
    end

    # Process a div block for documentation and grouping
    def process_div_block(xml, div_block)
      xml.div do
        # Process start if present
        if div_block[:start] && div_block[:start][:start_pattern]
          xml.start do
            process_pattern_list(xml, div_block[:start][:start_pattern])
          end
        end

        # Process includes if present
        div_block[:includes]&.each do |include_item|
          href = process_string_literal(include_item[:href])

          if include_item[:override]
            # Include with override block - override is properly scoped
            override = include_item[:override]

            # Check if override has any content
            has_content = (override[:start] && override[:start][:start_pattern]) ||
                          (override[:patterns] && !override[:patterns].empty?)

            if has_content
              xml.include(href: href) do
                # Process override start if present
                if override[:start] && override[:start][:start_pattern]
                  xml.start do
                    process_pattern_list(xml,
                                         override[:start][:start_pattern])
                  end
                end

                # Process override patterns (named patterns, div blocks, and top-level elements)
                override[:patterns]&.each do |pattern_item|
                  if pattern_item.key?(:name)
                    name = process_identifier(pattern_item[:name])
                    operator = pattern_item[:operator] ? extract_string(pattern_item[:operator]) : '='
                    if operator == '='
                      xml.define(name: name) do
                        process_pattern_list(xml, pattern_item[:pattern])
                      end
                    else
                      combine_type = operator == '|=' ? 'choice' : 'interleave'
                      xml.define(name: name, combine: combine_type) do
                        process_pattern_list(xml, pattern_item[:pattern])
                      end
                    end
                  elsif pattern_item.key?(:top_element)
                    process_content_item(xml, pattern_item[:top_element])
                  elsif pattern_item.key?(:div)
                    process_div_block(xml, pattern_item[:div])
                  end
                end
              end
            else
              # Empty override block
              xml.include(href: href)
            end
          else
            # Include without override block
            xml.include(href: href)
          end
        end

        # Process patterns (defines, nested divs, and top-level elements)
        div_block[:patterns]&.each do |pattern_item|
          if pattern_item.key?(:name)
            # Named pattern definition
            name = process_identifier(pattern_item[:name])
            operator = pattern_item[:operator] ? extract_string(pattern_item[:operator]) : '='
            if operator == '='
              xml.define(name: name) do
                process_pattern_list(xml, pattern_item[:pattern])
              end
            else
              combine_type = operator == '|=' ? 'choice' : 'interleave'
              xml.define(name: name, combine: combine_type) do
                process_pattern_list(xml, pattern_item[:pattern])
              end
            end
          elsif pattern_item.key?(:nested_div)
            # Nested div block
            process_div_block(xml, pattern_item[:nested_div])
          elsif pattern_item.key?(:top_element)
            # Top-level element
            process_content_item(xml, pattern_item[:top_element])
          elsif pattern_item.key?(:foreign_name)
            # Foreign element annotation - emit as foreign element in RNG XML
            process_foreign_element(xml, pattern_item)
          end
        end
      end
    end

    # Process a foreign element annotation (e.g., foo [] or rng:foo [ "val" ])
    # Emits the foreign element directly in the RNG XML
    def process_foreign_element(xml, pattern_item)
      name_info = pattern_item[:foreign_name]
      element_name = process_identifier(name_info)

      # Validate annotations if present (TC 18, 70, 71)
      if pattern_item[:foreign_annotation]
        ann_data = pattern_item[:foreign_annotation]
        # ann_data is {ann: {ann_items: ...}} or could be {ann_items: ...}
        ann_data = ann_data[:ann] if ann_data.is_a?(Hash) && ann_data[:ann]
        ann_items = ann_data.is_a?(Hash) ? ann_data[:ann_items] : nil
        validate_preamble_annotations(ann_items, @seen_ann_attrs ||= {}) if ann_items
      end

      # Emit as an empty foreign element (content is annotation-only, ignored in RNG)
      xml.parent.add_child("<#{element_name}/>")
    end
  end
end
