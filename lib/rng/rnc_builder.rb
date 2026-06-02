# frozen_string_literal: true

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
      @datatype_prefix = nil
      @datatype_library_uri = nil
      # Handle simple element (direct Element object, not Grammar)
      return build_element(schema) if schema.is_a?(Element)

      # Grammar with start and/or named patterns
      result = []

      # Collect datatype libraries from data elements
      collect_datatype_libraries(schema)

      # Add namespace declaration if present
      if schema.ns && !schema.ns.empty? && schema.ns != 'omitted' && schema.ns != 'empty'
        result << "default namespace = \"#{schema.ns}\""
        result << ''
      end

      # Add datatype library if present (grammar-level or from data elements)
      dt_lib = schema.datatypeLibrary if schema.datatypeLibrary &&
                                         !%w[omitted empty].include?(schema.datatypeLibrary)
      dt_lib ||= @datatype_library_uri
      if dt_lib
        result << "datatypes xsd = \"#{dt_lib}\""
        @datatype_prefix = 'xsd'
        result << ''
      end

      # Process start pattern
      if schema.start && !schema.start.empty?
        start = schema.start.first
        # Add documentation if present
        result << build_documentation(start.documentation).chomp if start.documentation && !start.documentation.empty?
        start_pattern = build_pattern(start)
        result << "start = #{start_pattern}"
        result << ''
      end

      # Process named patterns (define elements)
      if schema.define && !schema.define.empty?
        schema.define.each do |define|
          # Add documentation if present
          result << build_documentation(define.documentation).chomp if define.documentation && !define.documentation.empty?
          pattern = build_pattern(define)
          result << "#{define.name} = #{pattern}"
          result << ''
        end
      end

      # Process div elements (grouping containers)
      if schema.div && !schema.div.empty?
        schema.div.each do |div|
          div_content = build_div(div)
          result << div_content
          result << ''
        end
      end

      result.join("\n")
    end

    # Escape a string value for use in RNC double-quoted string literals.
    # RNC string escape sequences: \\ (backslash), \" (double quote),
    # \n (newline), \r (carriage return), \t (tab)
    #
    # @param str [String] The string to escape
    # @return [String] The escaped string
    def escape_rnc_string(str)
      str.gsub('\\') { '\\\\' }
         .gsub('"') { '\\"' }
         .gsub("\n") { '\\n' }
         .gsub("\r") { '\\r' }
         .gsub("\t") { '\\t' }
    end

    # Build RNC syntax for a div grouping construct
    #
    # @param div [Rng::Div] The div to convert
    # @return [String] RNC div syntax
    def build_div(div)
      result = 'div {'
      parts = []

      # Process divs within div
      if div.div && !div.div.empty?
        div.div.each do |nested_div|
          parts << build_div(nested_div)
        end
      end

      # Process start within div
      if div.start && !div.start.empty?
        div.start.each do |start|
          parts << "start = #{build_pattern(start)}"
        end
      end

      # Process defines within div
      if div.define && !div.define.empty?
        div.define.each do |define|
          parts << "#{define.name} = #{build_pattern(define)}"
        end
      end

      if parts.empty?
        "#{result} }"
      else
        "#{result}\n  #{parts.join("\n  ")}\n}"
      end
    end

    private

    # Build RNC syntax for documentation comments
    #
    # @param documentation [String, nil] Documentation text
    # @return [String] RNC documentation comment lines
    def build_documentation(documentation)
      return '' unless documentation && !documentation.empty?

      lines = documentation.split("\n")
      lines.map { |line| "## #{line}" }.join("\n") + "\n"
    end

    # Build RNC syntax for an element
    #
    # @param element [Rng::Element] The element to convert
    # @return [String] RNC element syntax
    def build_element(element)
      result = ''

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
                     elsif element.anyName || element.nsName ||
                           (element.name.is_a?(Name) && element.name.value)
                       build_name_class(element)
                     else
                       ''
                     end

      result += "element #{element_name} {\n"
      result += "  #{build_content(element)}\n"
      result += '}'
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
      content_parts << 'text' if node.text

      # Process empty
      content_parts << 'empty' if node.empty

      # Process value literals (Value object has .value attribute)
      if node.value
        value_str = node.value.is_a?(Value) ? node.value.value : node.value.to_s
        content_parts << "\"#{value_str}\""
      end

      # Process mixed content
      if node.mixed
        mixed_items = node.mixed.is_a?(Array) ? node.mixed : [node.mixed]
        mixed_items.each do |m|
          mixed_inner = build_mixed_content(m)
          content_parts << "mixed {\n  #{mixed_inner}\n}"
        end
      end
      if node.choice && !(node.choice.is_a?(Array) && node.choice.empty?)
        choices = node.choice.is_a?(Array) ? node.choice : [node.choice]
        choices.each { |c| content_parts << build_pattern(c) }
      end
      if node.group && !(node.group.is_a?(Array) && node.group.empty?)
        groups = node.group.is_a?(Array) ? node.group : [node.group]
        groups.each { |g| content_parts << build_pattern(g) }
      end
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

      # Process zeroOrMore
      if node.zeroOrMore
        if node.zeroOrMore.is_a?(Array)
          node.zeroOrMore.each do |pattern|
            content_parts << build_pattern(pattern)
          end
        else
          content_parts << build_pattern(node.zeroOrMore)
        end
      end

      # Process interleave
      if node.interleave && !(node.interleave.is_a?(Array) && node.interleave.empty?)
        interleaves = node.interleave.is_a?(Array) ? node.interleave : [node.interleave]
        interleaves.each do |il|
          content_parts << build_interleave(il)
        end
      end

      # Process data
      content_parts << build_data(node.data) if node.data

      # Process list
      content_parts << build_list(node.list) if node.list

      # Process notAllowed
      content_parts << 'notAllowed' if node.notAllowed

      parts = content_parts.reject(&:empty?)
      if parts.length > 1
        # Wrap choice/interleave in parentheses when part of a sequence
        parts.map! do |p|
          if p.include?(' | ') || p.include?(' & ')
            "(#{p})"
          else
            p
          end
        end
      end
      parts.join(",\n  ")
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

      content_parts << 'text' if mixed.text && !mixed.text.empty?
      content_parts << 'empty' if mixed.empty && !mixed.empty.empty?

      content_parts.reject(&:empty?).join(",\n  ")
    end

    # Build RNC syntax for an attribute
    #
    # @param attr [Rng::Attribute] The attribute to convert
    # @return [String] RNC attribute syntax
    def build_attribute(attr)
      result = ''

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
                  elsif attr.anyName || attr.nsName ||
                        (attr.name.is_a?(Name) && attr.name.value)
                    build_name_class(attr)
                  else
                    ''
                  end

      result += "attribute #{attr_name} { "

      # Check for value literal (Value object)
      if attr.value
        value_str = attr.value.is_a?(Value) ? attr.value.value : attr.value.to_s
        result += "\"#{value_str}\""
      # Check for choice (values, text, refs, etc.) — delegate to the
      # canonical choice builder so every member type is preserved
      elsif attr.choice
        result += build_choice(attr.choice)
      # Check for datatype
      elsif attr.data
        result += if attr.data.type
                    "xsd:#{attr.data.type}"
                  else
                    'text'
                  end
      else
        result += 'text'
      end

      result += ' }'
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
        # All pattern attributes are collections
        if node.group && !node.group.empty?
          return node.group.map { |g| build_pattern(g) }.join(', ')
        elsif node.element && !node.element.empty?
          return node.element.map { |elem| build_element(elem) }.join(', ')
        elsif node.choice && !node.choice.empty?
          return node.choice.map { |c| build_pattern(c) }.join(' | ')
        elsif node.ref && !node.ref.empty?
          return node.ref.map(&:name).join(' | ')
        elsif node.optional && !node.optional.empty?
          return node.optional.map { |o| build_pattern(o) }.join(', ')
        elsif node.zeroOrMore && !node.zeroOrMore.empty?
          return node.zeroOrMore.map { |z| build_pattern(z) }.join(', ')
        elsif node.oneOrMore && !node.oneOrMore.empty?
          return node.oneOrMore.map { |o| build_pattern(o) }.join(', ')
        elsif node.interleave && !node.interleave.empty?
          return node.interleave.map { |i| build_pattern(i) }.join(' & ')
        elsif node.text && !node.text.empty?
          return 'text'
        elsif node.empty && !node.empty.empty?
          return 'empty'
        elsif node.value && !node.value.empty?
          values = node.value.map do |v|
            v.is_a?(Value) ? "\"#{escape_rnc_string(v.value)}\"" : "\"#{escape_rnc_string(v.to_s)}\""
          end
          return values.join(', ')
        elsif node.data && !node.data.empty?
          return node.data.map { |d| build_data(d) }.join(', ')
        elsif node.attribute && !node.attribute.empty?
          return node.attribute.map { |a| build_attribute(a) }.join(', ')
        elsif node.list && !node.list.empty?
          return node.list.map { |l| build_list(l) }.join(', ')
        elsif node.mixed && !node.mixed.empty?
          return node.mixed.map { |m| build_mixed(m) }.join(', ')
        elsif node.notAllowed && !node.notAllowed.empty?
          return 'notAllowed'
        elsif node.grammar && !node.grammar.empty?
          return node.grammar.map { |g| build(g) }.join(', ')
        end
      end

      # Handle OneOrMore, ZeroOrMore, and Optional wrapper objects
      if node.is_a?(OneOrMore) || node.is_a?(ZeroOrMore) || node.is_a?(Optional)
        occurrence = case node.class.name
                     when 'Rng::OneOrMore' then '+'
                     when 'Rng::ZeroOrMore' then '*'
                     when 'Rng::Optional' then '?'
                     end

        # Extract content from wrapper
        if node.group && !(node.group.is_a?(Array) && node.group.empty?)
          inner = if node.group.is_a?(Array)
                    node.group.map { |g| build_pattern(g) }.join(', ')
                  else
                    build_pattern(node.group)
                  end
          return "(#{inner})#{occurrence}"
        elsif node.choice && !(node.choice.is_a?(Array) && node.choice.empty?)
          inner = if node.choice.is_a?(Array)
                    node.choice.map { |c| build_pattern(c) }.join(' | ')
                  else
                    build_pattern(node.choice)
                  end
          return "(#{inner})#{occurrence}"
        elsif node.element && !(node.element.is_a?(Array) && node.element.empty?)
          return "#{build_element(node.element)}#{occurrence}" unless node.element.is_a?(Array)
          return "#{build_element(node.element.first)}#{occurrence}" if node.element.length == 1

          inner = node.element.map { |e| build_element(e) }.join(', ')
          return "(#{inner})#{occurrence}"

        elsif node.ref && !(node.ref.is_a?(Array) && node.ref.empty?)
          return "(#{node.ref.map(&:name).join(' | ')})#{occurrence}" if node.ref.is_a?(Array)

          return "#{node.ref.name}#{occurrence}"

        elsif node.attribute && !(node.attribute.is_a?(Array) && node.attribute.empty?)
          # Handle attribute content inside wrapper (e.g., attribute acronym { text }?)
          attr_parts = if node.attribute.is_a?(Array)
                         node.attribute.map { |a| build_attribute(a) }
                       else
                         [build_attribute(node.attribute)]
                       end
          inner = attr_parts.join(', ')
          return "#{inner}#{occurrence}"
        elsif node.text && !(node.text.is_a?(Array) && node.text.empty?)
          # Handle text inside wrapper
          return "text#{occurrence}"
        elsif node.optional && !(node.optional.is_a?(Array) && node.optional.empty?)
          inner = if node.optional.is_a?(Array)
                    node.optional.map { |o| build_pattern(o) }.join(', ')
                  else
                    build_pattern(node.optional)
                  end
          return "(#{inner})#{occurrence}"
        elsif node.zeroOrMore && !(node.zeroOrMore.is_a?(Array) && node.zeroOrMore.empty?)
          inner = if node.zeroOrMore.is_a?(Array)
                    node.zeroOrMore.map { |z| build_pattern(z) }.join(', ')
                  else
                    build_pattern(node.zeroOrMore)
                  end
          return "(#{inner})#{occurrence}"
        elsif node.oneOrMore && !(node.oneOrMore.is_a?(Array) && node.oneOrMore.empty?)
          inner = if node.oneOrMore.is_a?(Array)
                    node.oneOrMore.map { |o| build_pattern(o) }.join(', ')
                  else
                    build_pattern(node.oneOrMore)
                  end
          return "(#{inner})#{occurrence}"
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
            node.element.map { |elem| build_element(elem) }.join(', ')
          end
        else
          build_element(node.element)
        end
      elsif node.is_a?(Choice)
        build_choice(node)
      elsif node.is_a?(Group) || node.is_a?(Start)
        # Handle Group and Start objects directly
        # They are container types with pattern attributes
        group_parts = []
        if node.group && !(node.group.is_a?(Array) && node.group.empty?)
          group_parts = if node.group.is_a?(Array)
                          node.group.map { |g| build_pattern(g) }
                        else
                          [build_pattern(node.group)]
                        end
        elsif node.choice && !(node.choice.is_a?(Array) && node.choice.empty?)
          group_parts = if node.choice.is_a?(Array)
                          node.choice.map { |c| build_pattern(c) }
                        else
                          [build_pattern(node.choice)]
                        end
        elsif node.element && !(node.element.is_a?(Array) && node.element.empty?)
          group_parts = if node.element.is_a?(Array)
                          node.element.map { |e| build_element(e) }
                        else
                          [build_element(node.element)]
                        end
        elsif node.ref && !(node.ref.is_a?(Array) && node.ref.empty?)
          group_parts = if node.ref.is_a?(Array)
                          node.ref.map(&:name)
                        else
                          [node.ref.name]
                        end
        elsif node.optional && !(node.optional.is_a?(Array) && node.optional.empty?)
          group_parts = if node.optional.is_a?(Array)
                          node.optional.map { |p| build_pattern(p) }
                        else
                          [build_pattern(node.optional)]
                        end
        elsif node.zeroOrMore && !(node.zeroOrMore.is_a?(Array) && node.zeroOrMore.empty?)
          group_parts = if node.zeroOrMore.is_a?(Array)
                          node.zeroOrMore.map { |p| build_pattern(p) }
                        else
                          [build_pattern(node.zeroOrMore)]
                        end
        elsif node.oneOrMore && !(node.oneOrMore.is_a?(Array) && node.oneOrMore.empty?)
          group_parts = if node.oneOrMore.is_a?(Array)
                          node.oneOrMore.map { |p| build_pattern(p) }
                        else
                          [build_pattern(node.oneOrMore)]
                        end
        end
        "(#{group_parts.join(', ')})"
      elsif node.ref
        if node.ref.is_a?(Array)
          # Array of refs - format as choice
          node.ref.map(&:name).join(' | ')
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
          node.oneOrMore.map { |p| "#{build_pattern(p)}+" }.join(', ')
        else
          "#{build_pattern(node.oneOrMore)}+"
        end
      elsif node.optional
        "#{build_pattern(node.optional)}?"
      elsif node.text
        'text'
      elsif node.empty
        'empty'
      else
        # Default case
        ''
      end
    end

    # Build RNC name class syntax for AnyName, NsName, Name objects
    #
    # @param node [Object] Element or Attribute with name class
    # @return [String] RNC name class syntax
    def build_name_class(node)
      if node.anyName
        result = '*'
        result += " - #{build_except(node.anyName.except)}" if node.anyName.except
        result
      elsif node.nsName
        ns_uri = node.nsName.ns
        # If ns is nil, use the default namespace from the grammar
        ns_uri = node.lutaml_root.ns if ns_uri.nil? && node.lutaml_root
        # Output as namespace prefix if we have one, otherwise use literal URI
        if ns_uri
          # Look up the prefix for this URI from the grammar's namespace declarations
          prefix = find_prefix_for_uri(node, ns_uri)
          result = prefix ? "#{prefix}:*" : "\"#{ns_uri}\":*"
        else
          # No namespace info available - this shouldn't happen but be safe
          result = '*'
        end
        result += " - #{build_except(node.nsName.except)}" if node.nsName.except
        result
      elsif node.name.is_a?(Name) && node.name.value
        node.name.value
      else
        ''
      end
    end

    # Find the namespace prefix for a given URI
    def find_prefix_for_uri(node, uri)
      return nil unless node.lutaml_root

      grammar = node.lutaml_root
      # Check if the grammar has namespace declarations
      if grammar.respond_to?(:namespace) && grammar.namespace
        ns = grammar.namespace
        if ns.is_a?(Array)
          ns.each do |n|
            return n.prefix if n.uri == uri
          end
        elsif ns.respond_to?(:uri) && ns.uri == uri
          return ns.prefix
        end
      end
      nil
    end

    # Build RNC except syntax
    #
    # @param except [Rng::Except] The except clause
    # @return [String] RNC except syntax
    def build_except(except)
      items = []
      except.name&.each { |n| items << n.value }
      except.ns_name&.each do |ns|
        name = ns.ns ? "#{ns.ns}:*" : 'default:*'
        items << name
      end
      except.choice&.each { |c| items << build_choice(c) }

      if items.length == 1
        items.first
      else
        "(#{items.join(' | ')})"
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
        obj.sub(/@\d+$/, '')
      else
        # Fallback
        obj.to_s.sub(/@\d+$/, '')
      end
    end

    # Build a data pattern from a Data object
    #
    # @param data [Data] Data object
    # @return [String] RNC data pattern
    def build_data(data)
      type = data.type.to_s
      # Prefix with datatype prefix if available (e.g., xsd:string)
      result = @datatype_prefix ? "#{@datatype_prefix}:#{type}" : type
      if data.param && !data.param.empty?
        params = data.param.map { |p| "#{p.name} = \"#{escape_rnc_string(p.value)}\"" }
        result += " { #{params.join(', ')} }"
      end
      result
    end

    # Build a list pattern from a List object
    #
    # @param list [List] List object
    # @return [String] RNC list pattern
    def build_list(list)
      content_parts = collect_list_items(list)
      content = content_parts.join(', ')
      "list { #{content} }"
    end

    # Collect all pattern items from a List node
    #
    # @param list [List] List node
    # @return [Array<String>] Array of pattern strings
    def collect_list_items(list)
      parts = []
      list.element&.each { |e| parts << build_element(e) unless e.nil? }
      list.attribute&.each { |a| parts << build_attribute(a) unless a.nil? }
      list.ref&.each { |r| parts << r.name unless r.nil? }
      list.text&.each { |_t| parts << 'text' }
      list.empty&.each { |_e| parts << 'empty' }
      list.value&.each { |v| parts << "\"#{escape_rnc_string(v.value)}\"" unless v.nil? }
      list.data&.each { |d| parts << build_data(d) unless d.nil? }
      list.notAllowed&.each { |_n| parts << 'notAllowed' }
      list.choice&.each { |c| parts << build_choice(c) unless c.nil? }
      list.group&.each { |g| parts << "(#{build_pattern(g)})" unless g.nil? }
      list.zeroOrMore&.each { |z| parts << build_pattern(z) unless z.nil? }
      list.oneOrMore&.each { |o| parts << build_pattern(o) unless o.nil? }
      list.optional&.each { |o| parts << build_pattern(o) unless o.nil? }
      list.mixed&.each { |m| parts << build_mixed_content(m) unless m.nil? }
      list.interleave&.each { |i| parts << build_interleave(i) unless i.nil? }
      parts
    end

    # Build a choice pattern from a Choice object or array of Choices
    #
    # Collects all children (element, ref, value, text, empty, data, etc.)
    # and builds each as a pattern, joined with " | ".
    #
    # @param choices [Choice, Array<Choice>] Choice object(s)
    # @return [String] RNC choice pattern
    def build_choice(choices)
      items = choices.is_a?(Array) ? choices : [choices]
      items.flat_map { |choice| collect_choice_items(choice) }.join(' | ')
    end

    # Build an interleave pattern from an Interleave object
    #
    # In RNC, interleave uses the & operator to separate child patterns.
    #
    # @param interleave [Interleave] Interleave object
    # @return [String] RNC interleave pattern
    def build_interleave(interleave)
      parts = collect_interleave_items(interleave)
      parts.join(' & ')
    end

    # Collect datatype library URIs from all data elements in a grammar
    def collect_datatype_libraries(schema)
      return unless schema.respond_to?(:define)

      schema.define.each do |d|
        collect_dt_from_node(d)
      end
    end

    def collect_dt_from_node(node)
      return unless node

      if node.respond_to?(:data) && node.data
        [node.data].flatten.each do |d|
          next unless d.datatypeLibrary && !d.datatypeLibrary.empty? &&
                      d.datatypeLibrary != 'omitted' && d.datatypeLibrary != 'empty'

          @datatype_library_uri ||= d.datatypeLibrary
        end
      end
      # Recurse into common pattern attributes (only for LUTAML model objects)
      return unless node.respond_to?(:element_order) # LUTAML model check

      %i[data element attribute choice group interleave optional zeroOrMore oneOrMore
         mixed list ref].each do |attr|
        val = node.send(attr) if node.respond_to?(attr)
        next unless val && !(val.respond_to?(:empty?) && val.empty?)

        [val].flatten.each { |v| collect_dt_from_node(v) }
      end
    end

    # Collect all pattern items from an Interleave node
    #
    # @param interleave [Interleave] Interleave node
    # @return [Array<String>] Array of pattern strings
    def collect_interleave_items(interleave)
      parts = []
      interleave.element&.each { |e| parts << build_element(e) unless e.nil? }
      interleave.attribute&.each { |a| parts << build_attribute(a) unless a.nil? }
      interleave.ref&.each { |r| parts << r.name unless r.nil? }
      interleave.text&.each { |_t| parts << 'text' }
      interleave.empty&.each { |_e| parts << 'empty' }
      interleave.value&.each { |v| parts << "\"#{escape_rnc_string(v.value)}\"" unless v.nil? }
      interleave.data&.each { |d| parts << build_data(d) unless d.nil? }
      interleave.list&.each { |l| parts << build_list(l) unless l.nil? }
      interleave.notAllowed&.each { |_n| parts << 'notAllowed' }
      interleave.choice&.each { |c| parts << build_choice(c) unless c.nil? }
      interleave.group&.each { |g| parts << "(#{build_pattern(g)})" unless g.nil? }
      interleave.zeroOrMore&.each { |z| parts << build_pattern(z) unless z.nil? }
      interleave.oneOrMore&.each { |o| parts << build_pattern(o) unless o.nil? }
      interleave.optional&.each { |o| parts << build_pattern(o) unless o.nil? }
      interleave.mixed&.each { |m| parts << build_mixed_content(m) unless m.nil? }
      interleave.interleave&.each { |i| parts << "(#{build_interleave(i)})" unless i.nil? }
      parts
    end

    # Collect all pattern items from a single Choice node
    #
    # @param choice [Choice] Choice node
    # @return [Array<String>] Array of pattern strings
    def collect_choice_items(choice)
      parts = []
      choice.element&.each { |e| parts << build_element(e) }
      choice.attribute&.each { |a| parts << build_attribute(a) }
      choice.ref&.each { |r| parts << r.name }
      choice.value&.each { |v| parts << "\"#{escape_rnc_string(v.value)}\"" }
      choice.text&.each { |_t| parts << 'text' }
      choice.empty&.each { |_e| parts << 'empty' }
      choice.data&.each { |d| parts << build_data(d) }
      choice.list&.each { |l| parts << build_list(l) }
      choice.notAllowed&.each { |_n| parts << 'notAllowed' }
      choice.choice&.each { |c| parts << build_choice(c) }
      choice.group&.each { |g| parts << "(#{build_pattern(g)})" }
      choice.zeroOrMore&.each { |z| parts << build_pattern(z) }
      choice.oneOrMore&.each { |o| parts << build_pattern(o) }
      choice.optional&.each { |o| parts << build_pattern(o) }
      choice.mixed&.each { |m| parts << build_mixed_content(m) }
      parts
    end
  end
end
