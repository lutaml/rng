require "parslet"
require "nokogiri"
require_relative "schema"

module Rng
  class RncParser < Parslet::Parser
    rule(:space) { match('\s').repeat(1) }
    rule(:space?) { space.maybe }
    rule(:newline) { (str("\r").maybe >> str("\n")).repeat(1) }
    rule(:newline?) { newline.maybe }
    rule(:whitespace) { (space | newline).repeat }
    rule(:comma) { str(",") }
    rule(:comma?) { (whitespace >> comma >> whitespace).maybe }

    rule(:identifier) { match("[a-zA-Z0-9_]").repeat(1).as(:identifier) }
    rule(:namespace_prefix) { identifier.as(:prefix) >> str(":") }
    rule(:namespace_prefix?) { namespace_prefix.maybe }
    rule(:qualified_name) { namespace_prefix? >> identifier.as(:local_name) }

    rule(:datatype_library) { str("datatypes") >> space >> identifier.as(:prefix) >> space >> string_literal.as(:uri) }

    rule(:string_literal) { str('"') >> match('[^"]').repeat.as(:string) >> str('"') }

    rule(:element_def) do
      str("element") >> space >>
        qualified_name.as(:name) >>
        whitespace >>
        str("{") >>
        whitespace >>
        content.maybe.as(:content) >>
        whitespace >>
        str("}") >>
        (str("*") | str("+") | str("?")).maybe.as(:occurrence)
    end

    rule(:attribute_def) do
      str("attribute") >> space >>
        qualified_name.as(:name) >>
        whitespace >>
        str("{") >>
        whitespace >>
        (datatype_ref | str("text")).as(:type) >>
        whitespace >>
        str("}")
    end

    rule(:datatype_ref) do
      identifier.as(:prefix) >> str(":") >> identifier.as(:type)
    end

    rule(:text_def) { str("text").as(:text) }
    rule(:empty_def) { str("empty").as(:empty) }

    rule(:group_def) do
      str("(") >>
        whitespace >>
        content.as(:group) >>
        whitespace >>
        str(")") >>
        (str("*") | str("+") | str("?")).maybe.as(:occurrence)
    end

    rule(:choice_def) do
      content_item.as(:first) >>
        (whitespace >> str("|") >> whitespace >> content_item.as(:second)).repeat(1).as(:rest)
    end

    rule(:named_pattern) do
      identifier.as(:name) >> whitespace >> str("=") >> whitespace >> content_item.as(:pattern)
    end

    rule(:content_item) do
      element_def | attribute_def | text_def | empty_def | group_def | choice_def | identifier.as(:ref)
    end

    rule(:content) do
      (content_item >> (comma? >> content_item).repeat).as(:items)
    end

    rule(:start_def) do
      str("start") >> whitespace >> str("=") >> whitespace >> content_item.as(:start)
    end

    rule(:grammar) do
      whitespace >>
        datatype_library.maybe.as(:datatype_library) >>
        whitespace >>
        (start_def | named_pattern | element_def).as(:root) >>
        (whitespace >> (named_pattern | element_def)).repeat.as(:definitions) >>
        whitespace
    end

    root(:grammar)

    def self.parse(input)
      parser = new
      tree = parser.parse(input.strip)
      convert_to_rng(tree)
    end

    def self.to_rnc(schema)
      # Convert RNG schema to RNC
      builder = RncBuilder.new
      builder.build(schema)
    end

    private

    def self.convert_to_rng(tree)
      builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
        if tree[:root].key?(:start)
          # This is a grammar with named patterns
          xml.grammar(xmlns: "http://relaxng.org/ns/structure/1.0") do
            # Add datatype library if present
            xml.datatypeLibrary tree[:datatype_library][:uri][:string].to_s if tree[:datatype_library]

            # Process start pattern
            xml.start do
              process_content_item(xml, tree[:root][:start])
            end

            # Process named patterns
            if tree[:definitions]
              tree[:definitions].each do |def_item|
                next unless def_item.key?(:name)

                xml.define(name: def_item[:name][:identifier].to_s) do
                  process_content_item(xml, def_item[:pattern])
                end
              end
            end
          end
        else
          # This is a simple element pattern
          process_content_item(xml, tree[:root])
        end
      end

      builder.to_xml
    end

    def self.process_content_item(xml, item)
      if item.key?(:name)
        # Element definition
        attrs = {}
        attrs[:name] = item[:name][:local_name][:identifier].to_s

        attrs[:ns] = item[:name][:prefix][:identifier].to_s if item[:name][:prefix]

        xml.element(attrs) do
          if item[:content]
            item[:content][:items].each do |content_item|
              process_content_item(xml, content_item)
            end
          end
        end

        # Handle occurrence
        if item[:occurrence]
          case item[:occurrence].to_s
          when "*"
            xml.parent.name = "zeroOrMore"
          when "+"
            xml.parent.name = "oneOrMore"
          when "?"
            xml.parent.name = "optional"
          end
        end
      elsif item.key?(:attr_name)
        # Attribute definition
        attrs = {}
        attrs[:name] = item[:attr_name][:local_name][:identifier].to_s

        attrs[:ns] = item[:attr_name][:prefix][:identifier].to_s if item[:attr_name][:prefix]

        xml.attribute(attrs) do
          if item[:type] == "text"
            xml.text
          elsif item[:type].key?(:prefix)
            xml.data(type: item[:type][:type][:identifier].to_s,
                     datatypeLibrary: "http://www.w3.org/2001/XMLSchema-datatypes")
          end
        end
      elsif item.key?(:text)
        xml.text
      elsif item.key?(:empty)
        xml.empty
      elsif item.key?(:group)
        xml.group do
          item[:group][:items].each do |group_item|
            process_content_item(xml, group_item)
          end
        end

        # Handle occurrence
        if item[:occurrence]
          case item[:occurrence].to_s
          when "*"
            xml.parent.name = "zeroOrMore"
          when "+"
            xml.parent.name = "oneOrMore"
          when "?"
            xml.parent.name = "optional"
          end
        end
      elsif item.key?(:first) && item.key?(:rest)
        # Choice definition
        xml.choice do
          process_content_item(xml, item[:first])
          item[:rest].each do |choice_item|
            process_content_item(xml, choice_item[:second])
          end
        end
      elsif item.key?(:ref)
        # Reference to a named pattern
        xml.ref(name: item[:ref][:identifier].to_s)
      end
    end
  end

  class RncBuilder
    def build(schema)
      if schema.element
        # Simple element pattern
        build_element(schema.element)
      else
        # Grammar with named patterns
        result = []

        # Add datatype library if present
        if schema.datatypeLibrary
          result << "datatypes xsd = \"#{schema.datatypeLibrary}\""
          result << ""
        end

        # Process start pattern
        if schema.start
          result << "start = #{build_pattern(schema.start)}"
          result << ""
        end

        # Process named patterns
        if schema.define && !schema.define.empty?
          schema.define.each do |define|
            result << "#{define.name} = #{build_pattern(define)}"
            result << ""
          end
        end

        result.join("\n")
      end
    end

    private

    def build_element(element)
      result = "element #{element.name} {\n"
      result += "  #{build_content(element)}\n"
      result += "}"
      result
    end

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
      if node.element
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

      # Process choice
      if node.choice
        choice_parts = []
        if node.choice.is_a?(Array)
          node.choice.each do |choice|
            choice_parts << build_pattern(choice)
          end
        else
          choice_parts << build_pattern(node.choice)
        end
        content_parts << choice_parts.join(" | ")
      end

      # Process group
      if node.group
        group_parts = []
        if node.group.is_a?(Array)
          node.group.each do |group|
            group_parts << build_pattern(group)
          end
        else
          group_parts << build_pattern(node.group)
        end
        content_parts << "(" + group_parts.join(", ") + ")"
      end

      # Process ref
      if node.ref
        if node.ref.is_a?(Array)
          node.ref.each do |ref|
            content_parts << ref.name
          end
        else
          content_parts << node.ref.name
        end
      end

      # Process zeroOrMore
      content_parts << "#{build_pattern(node.zeroOrMore)}*" if node.zeroOrMore

      # Process oneOrMore
      content_parts << "#{build_pattern(node.oneOrMore)}+" if node.oneOrMore

      # Process optional
      content_parts << "#{build_pattern(node.optional)}?" if node.optional

      content_parts.join(",\n  ")
    end

    def build_attribute(attr)
      result = "attribute #{attr.name} { "

      result += if attr.data
                  if attr.data.type
                    "xsd:#{attr.data.type}"
                  else
                    "text"
                  end
                else
                  "text"
                end

      result += " }"
      result
    end

    def build_pattern(node)
      if node.element
        build_element(node.element)
      elsif node.ref
        node.ref.name
      elsif node.choice
        choice_parts = []
        if node.choice.is_a?(Array)
          node.choice.each do |choice|
            choice_parts << build_pattern(choice)
          end
        else
          choice_parts << build_pattern(node.choice)
        end
        choice_parts.join(" | ")
      elsif node.group
        group_parts = []
        if node.group.is_a?(Array)
          node.group.each do |group|
            group_parts << build_pattern(group)
          end
        else
          group_parts << build_pattern(node.group)
        end
        "(" + group_parts.join(", ") + ")"
      elsif node.text
        "text"
      elsif node.empty
        "empty"
      else
        # Default case
        ""
      end
    end
  end
end
