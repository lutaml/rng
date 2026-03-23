# frozen_string_literal: true

require "nokogiri"
require "set"
require_relative "grammar"

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
    # Convert a parse tree to RNG XML
    #
    # @param tree [Hash] The parse tree from RncParser
    # @return [String] RNG XML string
    def convert(tree)
      # Track defined names for augmentation support
      defined_names = Set.new

      # Check if we need the annotations namespace
      @has_documentation = has_documentation_comments?(tree)

      builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
        grammar_attrs = { xmlns: "http://relaxng.org/ns/structure/1.0" }
        if @has_documentation
          grammar_attrs[:"xmlns:a"] =
            "http://relaxng.org/ns/compatibility/annotations/1.0"
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
          end

          # If no explicit start but we have top-level elements, wrap them in start
          has_explicit_start = tree[:start] && tree[:start][:start_pattern]
          has_top_elements = tree[:definitions]&.any? do |d|
            d.key?(:top_element)
          end

          if has_explicit_start
            # Process explicit start pattern
            xml.start do
              add_documentation(xml, tree[:start]) if tree[:start][:docs]
              process_pattern_list(xml, tree[:start][:start_pattern])
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
                        operator = pattern_item[:operator] ? extract_string(pattern_item[:operator]) : "="

                        if operator == "="
                          xml.define(name: name) do
                            if pattern_item[:docs]
                              add_documentation(xml,
                                                pattern_item)
                            end
                            process_pattern_list(xml, pattern_item[:pattern])
                          end
                        else
                          combine_type = operator == "|=" ? "choice" : "interleave"
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
              operator = def_item[:operator] ? extract_string(def_item[:operator]) : "="

              if operator == "=" || !defined_names.include?(name)
                # First definition or normal definition
                xml.define(name: name) do
                  add_documentation(xml, def_item) if def_item[:docs]
                  process_pattern_list(xml, def_item[:pattern])
                end
                defined_names.add(name)
              else
                # Augmentation - use combine attribute
                combine_type = operator == "|=" ? "choice" : "interleave"
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
            elsif def_item.key?(:div)
              # Div block for documentation and grouping
              process_div_block(xml, def_item[:div])
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
        return true if %i[documentation docs].include?(key)

        if value.is_a?(Hash)
          return true if has_documentation_comments?(value)
        elsif value.is_a?(Array)
          value.each do |item|
            if item.is_a?(Hash) && item.is_a?(Hash) && has_documentation_comments?(item)
              return true
            end
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
        text = text.sub(/^\s+/, "") if text
        text
      end.join("\n")
    end

    # Add documentation element if present
    def add_documentation(xml, item)
      if item[:docs]
        doc_text = extract_documentation(item[:docs])
        if doc_text && !doc_text.empty?
          xml.send(:"a:documentation", doc_text)
        end
      end
    end

    # Add annotations (foreign attributes and elements) if present
    def add_annotations(xml, item, processor = nil)
      return unless item[:annotations]

      # Use provided processor or create one
      proc = processor || begin
        require_relative "parse_tree_processor"
        ParseTreeProcessor.new({})
      end

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
      "\\" => "\\",
      "n" => "\n",
      "r" => "\r",
      "t" => "\t",
    }.freeze

    # Validate Unicode code point
    #
    # @param code_point [Integer] The Unicode code point to validate
    # @param context [Symbol] Context where the character is used (:identifier or :string)
    # @return [Integer] The validated code point
    # @raise [ArgumentError] If the code point is invalid (surrogate or out of range)
    def validate_unicode_codepoint(code_point, context = :string)
      # Check for surrogate pairs (0xD800-0xDFFF)
      if code_point >= 0xD800 && code_point <= 0xDFFF
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
        char = [code_point].pack("U")
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
      return "" unless parts
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
            if ENV['RNG_DEBUG']
              puts "DEBUG: Processing hex escape: #{hex} -> code_point: 0x#{code_point.to_s(16).upcase}"
            end
            
            validate_unicode_codepoint(code_point, context)
            [code_point].pack("U")
          elsif part[:char_escape]
            # Map character escape
            char = extract_string(part[:char_escape][:char])
            CHAR_ESCAPE_MAP[char] || char
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

    # Process string literal with optional concatenation
    #
    # @param str_node [Hash] String node from parse tree (can have :concatenations)
    # @return [String] Concatenated string value
    def process_string_literal(str_node)
      return "" unless str_node
      return str_node if str_node.is_a?(String)

      # Process base string with potential escapes
      base_str = if str_node[:string_parts]
                   process_escape_sequences(str_node[:string_parts])
                 elsif str_node[:string]
                   extract_string(str_node[:string])
                 else
                   ""
                 end

      # Handle concatenation
      return base_str unless str_node[:concatenations]

      parts = [base_str]
      concatenations = str_node[:concatenations]
      concatenations = [concatenations] unless concatenations.is_a?(Array)

      concatenations.each do |concat|
        next unless concat
        next unless concat.is_a?(Hash)  # FIX: Validate concat is a Hash

        if concat[:concat_string_parts]
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

        if pattern[:choice_items] && !pattern[:choice_items].empty?
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

    def process_content_item(xml, item)
      if item.key?(:type)
        # Attribute definition (has :type key) - CHECK THIS FIRST!
        attrs = {}

        # Handle name wildcards or regular qualified names
        name_obj = item[:name]

        # Unwrap the extra :name level from name_class.as(:name)
        if name_obj.is_a?(Hash) && name_obj.key?(:name)
          name_obj = name_obj[:name]
        end

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
              process_identifier(name_obj[:prefix])
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
          if attr_name_type == :any_name
            # Generate <attribute><anyName> with optional <except>
            xml_ctx.attribute do
              add_documentation(xml_ctx, item) if item[:docs]
              xml_ctx.anyName do
                if except_clause
                  xml_ctx.except_ do
                    process_name_except(xml_ctx, except_clause)
                  end
                end
              end
              process_attribute_type(xml_ctx, item[:type])
            end
          elsif attr_name_type == :ns_name
            # Generate <attribute><nsName> with ns attribute and optional <except>
            xml_ctx.attribute do
              add_documentation(xml_ctx, item) if item[:docs]
              xml_ctx.nsName(ns: ns_prefix) do
                if except_clause
                  xml_ctx.except_ do
                    process_name_except(xml_ctx, except_clause)
                  end
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
                           when "*" then "zeroOrMore"
                           when "+" then "oneOrMore"
                           when "?" then "optional"
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
        if name_obj.is_a?(Hash) && name_obj.key?(:name)
          name_obj = name_obj[:name]
        end

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
          # Regular qualified name
          element_name_type = :qualified
          attrs[:name] = process_identifier(name_obj[:local_name])
          if name_obj[:prefix]
            attrs[:ns] =
              process_identifier(name_obj[:prefix])
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
          if element_name_type == :any_name
            # Generate <anyName> with optional <except>
            xml_ctx.element do
              add_documentation(xml_ctx, item) if item[:docs]
              xml_ctx.anyName do
                if except_clause
                  xml_ctx.except_ do
                    process_name_except(xml_ctx, except_clause)
                  end
                end
              end
              process_element_content(xml_ctx, item[:content]) if item[:content]
            end
          elsif element_name_type == :ns_name
            # Generate <nsName> with ns attribute and optional <except>
            xml_ctx.element do
              add_documentation(xml_ctx, item) if item[:docs]
              xml_ctx.nsName(ns: ns_prefix) do
                if except_clause
                  xml_ctx.except_ do
                    process_name_except(xml_ctx, except_clause)
                  end
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
                           when "*" then "zeroOrMore"
                           when "+" then "oneOrMore"
                           when "?" then "optional"
                           end

          xml.send(occurrence_tag) do
            element_block.call(xml)
          end
        else
          element_block.call(xml)
        end
      elsif item.key?(:text)
        xml.parent << Nokogiri::XML::Node.new("text", xml.doc)
      elsif item.key?(:empty)
        xml.parent << Nokogiri::XML::Node.new("empty", xml.doc)
      elsif item.key?(:not_allowed)
        xml.parent << Nokogiri::XML::Node.new("notAllowed", xml.doc)
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
                           when "*" then "zeroOrMore"
                           when "+" then "oneOrMore"
                           when "?" then "optional"
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
        xml.ref(name: process_identifier(item[:ref]))
      elsif item.key?(:value)
        # Value literal (string) in element content
        xml.value(process_string_literal(item[:value]))
      end
    end

    # Process element content which may have choice_items and sequence_items
    def process_element_content(xml, content)
      return unless content

      # Handle new structure: {:first, :choice_items, :sequence_items}
      if content.is_a?(Hash) && content.key?(:first)
        first_item = content[:first]

        if content[:choice_items] && !content[:choice_items].empty?
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
          xml_ctx.parent << Nokogiri::XML::Node.new("text", xml_ctx.doc)
        elsif item.key?(:prefix)
          # Datatype reference
          data_attrs = {
            type: process_identifier(item[:type]),
            datatypeLibrary: "http://www.w3.org/2001/XMLSchema-datatypes",
          }
          xml_ctx.data(data_attrs)
        elsif item.key?(:ref)
          # Reference to named pattern
          xml_ctx.ref(name: process_identifier(item[:ref]))
        end
      end

      if occurrence
        occurrence_tag = case occurrence
                         when "*" then "zeroOrMore"
                         when "+" then "oneOrMore"
                         when "?" then "optional"
                         end
        xml.send(occurrence_tag) do
          item_block.call(xml)
        end
      else
        item_block.call(xml)
      end
    end

    # Process name except clause for wildcards
    def process_name_except(xml, except_clause)
      # except_clause can be a single qualified_name or multiple names
      if except_clause.is_a?(Hash) && except_clause.key?(:local_name)
        # Single name
        xml.name(process_identifier(except_clause[:local_name]))
      elsif except_clause.is_a?(Array)
        # Multiple names - wrap in choice
        except_clause.each do |name|
          xml.name(process_identifier(name[:local_name])) if name.key?(:local_name)
        end
      end
    end

    # Process attribute type content (factored out for wildcard support)
    def process_attribute_type(xml, type_info)
      if type_info == "text" || (type_info.is_a?(Hash) && type_info.key?(:text_type))
        xml.parent << Nokogiri::XML::Node.new("text", xml.doc)
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
          datatypeLibrary: "http://www.w3.org/2001/XMLSchema-datatypes",
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
                      operator = pattern_item[:operator] ? extract_string(pattern_item[:operator]) : "="
                      if operator == "="
                        xml.define(name: name) do
                          process_pattern_list(xml, pattern_item[:pattern])
                        end
                      else
                        combine_type = operator == "|=" ? "choice" : "interleave"
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
              operator = pattern_item[:operator] ? extract_string(pattern_item[:operator]) : "="
              if operator == "="
                xml.define(name: name) do
                  process_pattern_list(xml, pattern_item[:pattern])
                end
              else
                combine_type = operator == "|=" ? "choice" : "interleave"
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
            end
          end
        end
      end
    end
  end
end
