# frozen_string_literal: true

require_relative "element"
require_relative "value"
require_relative "define"
require_relative "one_or_more"
require_relative "zero_or_more"
require_relative "optional"
require_relative "name"

module Rng
  # RncBuilder converts RNG Grammar objects to RNC (RELAX NG Compact Syntax) text format.
  #
  # This class traverses the RNG object model and generates readable RNC syntax strings.
  # It handles all major RELAX NG patterns including:
  # - Elements and attributes
  # - Named pattern definitions
  # - Occurrence markers (*, +, ?)
  # - Choice and group patterns
  # - Mixed content
  # - Value literals and datatypes
  # - Namespace declarations
  #
  # @example Convert a Grammar object to RNC
  #   grammar = Rng::Grammar.new
  #   # ... populate grammar ...
  #   builder = Rng::RncBuilder.new
  #   rnc_text = builder.build(grammar)
  class RncBuilder
    # Build RNC text from a Grammar object or Element
    #
    # @param schema [Rng::Grammar, Rng::Element] The schema to convert
    # @return [String] RNC text representation
    def build(schema)
      # Handle simple element (direct Element object, not Grammar)
      return build_element(schema) if schema.is_a?(Element)

      # Grammar with start and/or named patterns
      result = []

      # Add namespace declaration if present
      if schema.ns && !schema.ns.empty? && schema.ns != "omitted" && schema.ns != "empty"
        result << "default namespace = \"#{schema.ns}\""
        result << ""
      end

      # Add datatype library if present
      if schema.datatypeLibrary && schema.datatypeLibrary != "omitted" && schema.datatypeLibrary != "empty"
        result << "datatypes xsd = \"#{schema.datatypeLibrary}\""
        result << ""
      end

      # Process start pattern
      if schema.start && !schema.start.empty?
        start = schema.start.first
        # Add documentation if present
        if start.documentation && !start.documentation.empty?
          result << build_documentation(start.documentation).chomp
        end
        start_pattern = build_pattern(start)
        result << "start = #{start_pattern}"
        result << ""
      end

      # Process named patterns (define elements)
      if schema.define && !schema.define.empty?
        schema.define.each do |define|
          # Add documentation if present
          if define.documentation && !define.documentation.empty?
            result << build_documentation(define.documentation).chomp
          end
          pattern = build_pattern(define)
          result << "#{define.name} = #{pattern}"
          result << ""
        end
      end

      result.join("\n")
    end

    private

    # Build RNC syntax for documentation comments
    #
    # @param documentation [String, nil] Documentation text
    # @return [String] RNC documentation comment lines
    def build_documentation(documentation)
      return "" unless documentation && !documentation.empty?

      lines = documentation.split("\n")
      lines.map { |line| "## #{line}" }.join("\n") + "\n"
    end

    # Build RNC syntax for an element
    #
    # @param element [Rng::Element] The element to convert
    # @return [String] RNC element syntax
    def build_element(element)
      result = ""

      # Add documentation if present
      result += build_documentation(element.documentation) if element.documentation

      # Extract element name - handle multiple cases:
      # 1. attr_name as string (from XML attribute)
      # 2. attr_name as hash (raw parse tree - shouldn't happen but be defensive)
      # 3. name as Name object (from XML child element)
      element_name = if element.attr_name.is_a?(String) && !element.attr_name.empty?
                       element.attr_name
                     elsif element.attr_name.is_a?(Hash)
                       # Raw parse tree leaked through - extract name
                       name_data = element.attr_name
                       identifier = if name_data.dig(:name, :local_name,
                                                     :identifier)
                                      name_data.dig(:name, :local_name,
                                                    :identifier)
                                    elsif name_data.dig(:local_name,
                                                        :identifier)
                                      name_data.dig(:local_name, :identifier)
                                    else
                                      name_data
                                    end
                       # Handle Parslet::Slice (has position info like "doc"@16)
                       extract_string(identifier)
                     elsif element.name.is_a?(Name)
                       # Name object - extract the value
                       element.name.value || ""
                     else
                       ""
                     end

      result += "element #{element_name} {\n"
      result += "  #{build_content(element)}\n"
      result += "}"
      result
    end

    # Build RNC syntax for element content
    #
    # @param node [Object] The node containing content (attributes, elements, text, etc.)
    # @return [String] RNC content syntax
    def build_content(node)
      content_parts = []

      # Process attributes
      if node.attribute
        if node.attribute.is_a?(Array)
          node.attribute.each do |attr|
            content_parts << build_attribute(attr)
          end
        else
          content_parts << build_attribute(node.attribute)
        end
      end

      # Process child elements
      if node.element && !node.element.empty?
        if node.element.is_a?(Array)
          node.element.each do |elem|
            content_parts << build_element(elem)
          end
        else
          content_parts << build_element(node.element)
        end
      end

      # Process text
      content_parts << "text" if node.text

      # Process empty
      content_parts << "empty" if node.empty

      # Process value literals (Value object has .value attribute)
      if node.value
        value_str = node.value.is_a?(Value) ? node.value.value : node.value.to_s
        content_parts << "\"#{value_str}\""
      end

      # Process mixed content
      if node.mixed
        mixed_inner = build_mixed_content(node.mixed)
        content_parts << "mixed {\n  #{mixed_inner}\n}"
      end

      content_parts << build_pattern(node.choice) if node.choice && !(node.choice.is_a?(Array) && node.choice.empty?)

      content_parts << build_pattern(node.group) if node.group && !(node.group.is_a?(Array) && node.group.empty?)

      # Process ref
      if node.ref && !node.ref.empty?
        if node.ref.is_a?(Array)
          node.ref.each do |ref|
            content_parts << ref.name
          end
        else
          content_parts << node.ref.name
        end
      end

      # Process oneOrMore
      if node.oneOrMore
        if node.oneOrMore.is_a?(Array)
          node.oneOrMore.each do |pattern|
            content_parts << build_pattern(pattern)
          end
        else
          content_parts << build_pattern(node.oneOrMore)
        end
      end

      # Process optional
      if node.optional
        if node.optional.is_a?(Array)
          node.optional.each do |pattern|
            content_parts << build_pattern(pattern)
          end
        else
          content_parts << build_pattern(node.optional)
        end
      end

      content_parts.join(",\n  ")
    end

    # Build RNC syntax for mixed content
    #
    # @param mixed [Object] The mixed content node
    # @return [String] RNC mixed content syntax
    def build_mixed_content(mixed)
      # Mixed contains collections of patterns
      content_parts = []

      # Process all pattern types in mixed
      if mixed.element && !mixed.element.empty?
        mixed.element.each do |elem|
          content_parts << build_element(elem)
        end
      end

      if mixed.oneOrMore && !mixed.oneOrMore.empty?
        mixed.oneOrMore.each do |pattern|
          content_parts << "#{build_pattern(pattern)}+"
        end
      end

      if mixed.zeroOrMore && !mixed.zeroOrMore.empty?
        mixed.zeroOrMore.each do |pattern|
          content_parts << "#{build_pattern(pattern)}*"
        end
      end

      if mixed.optional && !mixed.optional.empty?
        mixed.optional.each do |pattern|
          content_parts << "#{build_pattern(pattern)}?"
        end
      end

      if mixed.ref && !mixed.ref.empty?
        mixed.ref.each do |ref|
          content_parts << ref.name
        end
      end

      if mixed.choice && !mixed.choice.empty?
        mixed.choice.each do |choice|
          content_parts << build_pattern(choice)
        end
      end

      if mixed.group && !mixed.group.empty?
        mixed.group.each do |group|
          content_parts << build_pattern(group)
        end
      end

      content_parts << "text" if mixed.text && !mixed.text.empty?
      content_parts << "empty" if mixed.empty & !mixed.empty.empty?

      content_parts.join(",\n  ")
    end

    # Build RNC syntax for an attribute
    #
    # @param attr [Rng::Attribute] The attribute to convert
    # @return [String] RNC attribute syntax
    def build_attribute(attr)
      result = ""

      # Add documentation if present (indented for use within element)
      if attr.documentation && !attr.documentation.empty?
        doc_lines = attr.documentation.split("\n")
        result += doc_lines.map { |line| "  ## #{line}\n" }.join
      end

      # Extract attribute name - handle multiple cases:
      # 1. attr_name as string (from XML attribute)
      # 2. attr_name as hash (raw parse tree - shouldn't happen but be defensive)
      # 3. name as Name object (from XML child element)
      attr_name = if attr.attr_name.is_a?(String) && !attr.attr_name.empty?
                    attr.attr_name
                  elsif attr.attr_name.is_a?(Hash)
                    # Raw parse tree leaked through - extract name
                    name_data = attr.attr_name
                    identifier = if name_data.dig(:name, :local_name,
                                                  :identifier)
                                   name_data.dig(:name, :local_name,
                                                 :identifier)
                                 elsif name_data.dig(:local_name, :identifier)
                                   name_data.dig(:local_name, :identifier)
                                 else
                                   name_data
                                 end
                    # Handle Parslet::Slice (has position info like "doc"@16)
                    extract_string(identifier)
                  elsif attr.name.is_a?(Name)
                    # Name object - extract the value
                    attr.name.value || ""
                  else
                    ""
                  end

      result += "attribute #{attr_name} { "

      # Check for value literal (Value object)
      if attr.value
        value_str = attr.value.is_a?(Value) ? attr.value.value : attr.value.to_s
        result += "\"#{value_str}\""
      # Check for choice of values
      elsif attr.choice
        # Check if choice contains Value objects
        choice_obj = attr.choice
        if choice_obj.value.is_a?(Array)
          # Choice with array of Value objects
          values = choice_obj.value.map do |v|
            v_str = v.is_a?(Value) ? v.value : v.to_s
            "\"#{v_str}\""
          end
          result += values.join(" | ")
        else
          # Other choice patterns
          result += build_pattern(attr.choice)
        end
      # Check for datatype
      elsif attr.data
        result += if attr.data.type
                    "xsd:#{attr.data.type}"
                  else
                    "text"
                  end
      else
        result += "text"
      end

      result += " }"
      result
    end

    # Build RNC syntax for a pattern (recursive)
    #
    # This method handles all pattern types including:
    # - Define (named pattern definitions)
    # - OneOrMore, ZeroOrMore, Optional (occurrence wrappers)
    # - Element (direct elements)
    # - Choice, Group (pattern combinations)
    # - Ref (pattern references)
    # - Value, Text, Empty (leaf patterns)
    # - Mixed (mixed content)
    #
    # @param node [Object] The pattern node to convert
    # @return [String] RNC pattern syntax
    def build_pattern(node)
      # Handle Define objects by extracting their pattern content
      if node.is_a?(Define)
        # Define is a container, extract actual pattern content
        # Check in likely order of occurrence
        if node.group && !(node.group.is_a?(Array) && node.group.empty?)
          return build_pattern(node.group)
        elsif node.element && !(node.element.is_a?(Array) && node.element.empty?)
          if node.element.is_a?(Array)
            return node.element.map do |elem|
              build_element(elem)
            end.join(", ")
          end

          return build_element(node.element)

        elsif node.choice && !(node.choice.is_a?(Array) && node.choice.empty?)
          if node.choice.is_a?(Array)
            return node.choice.map do |choice|
              build_pattern(choice)
            end.join(" | ")
          end

          return build_pattern(node.choice)

        elsif node.ref && !(node.ref.is_a?(Array) && node.ref.empty?)
          return node.ref.map(&:name).join(" | ") if node.ref.is_a?(Array)

          return node.ref.name

        end

        # If no content found, return empty
        return ""
      end

      # Handle OneOrMore, ZeroOrMore, and Optional wrapper objects
      if node.is_a?(OneOrMore) || node.is_a?(ZeroOrMore) || node.is_a?(Optional)
        occurrence = case node.class.name
                     when "Rng::OneOrMore" then "+"
                     when "Rng::ZeroOrMore" then "*"
                     when "Rng::Optional" then "?"
                     end

        # Extract content from wrapper
        if node.group && !(node.group.is_a?(Array) && node.group.empty?)
          inner = if node.group.is_a?(Array)
                    node.group.map { |g| build_pattern(g) }.join(", ")
                  else
                    build_pattern(node.group)
                  end
          return "(#{inner})#{occurrence}"
        elsif node.choice && !(node.choice.is_a?(Array) && node.choice.empty?)
          inner = if node.choice.is_a?(Array)
                    node.choice.map { |c| build_pattern(c) }.join(" | ")
                  else
                    build_pattern(node.choice)
                  end
          return "(#{inner})#{occurrence}"
        elsif node.element && !(node.element.is_a?(Array) && node.element.empty?)
          return "#{build_element(node.element)}#{occurrence}" unless node.element.is_a?(Array)
          return "#{build_element(node.element.first)}#{occurrence}" if node.element.length == 1

          inner = node.element.map { |e| build_element(e) }.join(", ")
          return "(#{inner})#{occurrence}"

        elsif node.ref && !(node.ref.is_a?(Array) && node.ref.empty?)
          return "(#{node.ref.map(&:name).join(' | ')})#{occurrence}" if node.ref.is_a?(Array)

          return "#{node.ref.name}#{occurrence}"

        end
      end

      # Handle Element directly
      return build_element(node) if node.is_a?(Element)

      # Handle various pattern types
      if node.element && !(node.element.is_a?(Array) && node.element.empty?)
        # element can be an array or single element
        if node.element.is_a?(Array)
          if node.element.length == 1
            build_element(node.element.first)
          else
            # Multiple elements - wrap in group
            node.element.map { |elem| build_element(elem) }.join(", ")
          end
        else
          build_element(node.element)
        end
      elsif node.choice && !(node.choice.is_a?(Array) & node.choice.empty?)
        choice_parts = []
        if node.choice.is_a?(Array)
          node.choice.each do |choice|
            choice_parts << build_pattern(choice)
          end
        else
          choice_parts << build_pattern(node.choice)
        end
        choice_parts.join(" | ")
      elsif node.group && !(node.group.is_a?(Array) & node.group.empty?)
        group_parts = []
        if node.group.is_a?(Array)
          node.group.each do |group|
            group_parts << build_pattern(group)
          end
        else
          group_parts << build_pattern(node.group)
        end
        "(#{group_parts.join(', ')})"
      elsif node.ref
        if node.ref.is_a?(Array)
          # Array of refs - format as choice
          node.ref.map(&:name).join(" | ")
        else
          node.ref.name
        end
      elsif node.value
        value_str = node.value.is_a?(Value) ? node.value.value : node.value.to_s
        "\"#{value_str}\""
      elsif node.mixed
        mixed_inner = build_mixed_content(node.mixed)
        "mixed {\n  #{mixed_inner}\n}"
      elsif node.zeroOrMore
        "#{build_pattern(node.zeroOrMore)}*"
      elsif node.oneOrMore
        if node.oneOrMore.is_a?(Array)
          node.oneOrMore.map { |p| "#{build_pattern(p)}+" }.join(", ")
        else
          "#{build_pattern(node.oneOrMore)}+"
        end
      elsif node.optional
        "#{build_pattern(node.optional)}?"
      elsif node.text
        "text"
      elsif node.empty
        "empty"
      else
        # Default case
        ""
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
        # Already a string - remove position marker if present
        obj.sub(/@\d+$/, "")
      else
        # Fallback
        obj.to_s.sub(/@\d+$/, "")
      end
    end
  end
end
