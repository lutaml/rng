# frozen_string_literal: true

require "parslet"
require "nokogiri"
require "lutaml/model"
require "lutaml/model/xml/nokogiri_adapter"
require "set"
require_relative "grammar"
require_relative "rnc_builder"
require_relative "rnc_to_rng_converter"
require_relative "include_processor"
require_relative "parse_tree_processor"

# Configure Nokogiri adapter for XML parsing
Lutaml::Model::Config.configure do |config|
  config.xml_adapter = Lutaml::Model::Xml::NokogiriAdapter
end

module Rng
  class RncParser < Parslet::Parser
    # Helper method to extract clean string without Parslet position markers
    def self.extract_string(obj)
      if obj.respond_to?(:str)
        # Parslet::Slice - use .str to get clean string
        obj.str
      elsif obj.is_a?(String)
        obj
      else
        obj.to_s
      end
    end

    # Comments
    # Regular comment: single #
    rule(:comment) { str("#") >> str("#").absent? >> match('[^\n]').repeat >> (str("\n") | any.absent?) }
    rule(:comment?) { comment.maybe }
    
    # Documentation comment: ##
    rule(:doc_comment) { str("##") >> match('[^\n]').repeat.as(:doc_line) >> (str("\n") | any.absent?) }
    rule(:doc_comments) { (doc_comment >> (whitespace.maybe >> doc_comment).repeat).as(:documentation) }
    
    # Whitespace (including comments)
    rule(:space) { match('\s').repeat(1) }
    rule(:space?) { space.maybe }
    rule(:newline) { (str("\r").maybe >> str("\n")).repeat(1) }
    rule(:newline?) { newline.maybe }
    # Only regular comments in whitespace - doc comments are captured by pattern rules
    rule(:whitespace) { (space | newline | comment).repeat }
    rule(:comma) { str(",") }
    rule(:comma?) { (whitespace >> comma >> whitespace).maybe }

    # Escape sequences support
    # Unicode code point: \x{HHHHHH} (1-6 hex digits)
    rule(:hex_escape) do
      str("\\x{") >> match('[0-9a-fA-F]').repeat(1, 6).as(:hex) >> str("}")
    end

    # Character escapes for strings: \", \\, \n, \r, \t
    rule(:char_escape) do
      str("\\") >> match('["\\\\ntr]').as(:char)
    end

    # Identifier can contain regular chars or hex escapes
    rule(:identifier_char) do
      hex_escape.as(:hex_escape) | match("[a-zA-Z0-9_-]").as(:char)
    end

    rule(:identifier) { identifier_char.repeat(1).as(:identifier_parts) }
    rule(:namespace_prefix) { identifier.as(:prefix) >> str(":") }
    rule(:namespace_prefix?) { namespace_prefix.maybe }
    rule(:qualified_name) { namespace_prefix? >> identifier.as(:local_name) }

    # Name wildcards for anyName and nsName patterns

    # anyName wildcard: *  or  * - exceptName
    rule(:any_name_pattern) do
      str("*") >>
        (space >> str("-") >> space >> name_class_except).maybe.as(:except)
    end

    # nsName wildcard: prefix:*  or  prefix:* - exceptName
    rule(:ns_name_pattern) do
      namespace_prefix >> str("*") >>
        (space >> str("-") >> space >> name_class_except).maybe.as(:except)
    end

    # Except clause can be a single name or multiple names in parentheses
    rule(:name_class_except) do
      (str("(") >> space? >> qualified_name >>
       (space? >> str("|") >> space? >> qualified_name).repeat >>
       space? >> str(")")) |
        qualified_name
    end

    # Name_class rule is useful for EBNF generation of a name_class.
    # It can parse a qualified name or the anyName/namespaceRef/externalRef patterns.
    # !!!!!!!!!
    # GENERAL RULE WALKING TO ANY BYTES WILL CONSUME FROM INPUT; ALL RULER CALLS (HIERARCHY) SHOULD FINALIZE
    #     OTHERWISE THE BACKPROP TO DISQUALIFY THE PATTERN WONT WORK.
    # !!!!!!!!!
    # Try wildcards first (more specific), then fall back to qualified names
    rule(:name_class) do
      ns_name_pattern.as(:ns_name) |
        any_name_pattern.as(:any_name) |
        qualified_name.as(:name)
    end

    # Datatype library declaration (same as datatype_library but different name for clarity)
    rule(:datatype_decl) {
      str("datatypes") >> space >>
      identifier.as(:prefix) >> space? >>
      str("=") >> space? >>
      string_literal.as(:uri)
    }

    # String literal with optional concatenation using ~ operator
    # Supports escape sequences: \x{HEX}, \", \\, \n, \r, \t
    # Control characters (0x00-0x1F, 0x7F) must be escaped
    rule(:string_char) do
      hex_escape.as(:hex_escape) |
        char_escape.as(:char_escape) |
        (str('\\').absent? >> str('"').absent? >>
         match('[\u0000-\u001F\u007F]').absent? >> any)
    end

    rule(:string_literal) do
      first_string = str('"') >> string_char.repeat.as(:string_parts) >> str('"')
      concat_part = whitespace >> str('~') >> whitespace >>
                    str('"') >> string_char.repeat.as(:concat_string_parts) >> str('"')
      
      first_string >> concat_part.repeat.maybe.as(:concatenations)
    end

    # Value pattern for literal values
    rule(:value_literal) { string_literal.as(:value) }

    # Mixed content pattern
    rule(:mixed_pattern) do
      str("mixed") >> whitespace >> str("{") >> whitespace >>
        content.as(:mixed_content) >> whitespace >> str("}")
    end

    # Namespace declarations
    # Default namespace (unprefixed): default namespace = "uri"
    rule(:default_namespace_decl) do
      str("default") >> space >> str("namespace") >> space? >>
        str("=") >> space? >> string_literal.as(:uri)
    end

    # Default namespace (prefixed): default namespace prefix = "uri"
    rule(:default_prefixed_namespace_decl) do
      str("default") >> space >> str("namespace") >> space >>
        identifier.as(:prefix) >> space? >>
        str("=") >> space? >> string_literal.as(:uri)
    end

    # Prefixed namespace: namespace prefix = "uri"
    rule(:prefixed_namespace_decl) do
      str("namespace") >> space >>
        identifier.as(:prefix) >> space? >>
        str("=") >> space? >> string_literal.as(:uri)
    end

    # Any namespace declaration
    rule(:namespace_decl) do
      default_prefixed_namespace_decl.as(:default_prefixed_ns) |
        default_namespace_decl.as(:default_ns) |
        prefixed_namespace_decl.as(:prefixed_ns)
    end

    rule(:element_def) do
      (doc_comments >> whitespace).maybe.as(:docs) >>
        str("element") >> space >>
        name_class.as(:name) >>
        whitespace >>
        str("{") >> whitespace >>
        content.maybe.as(:content) >> whitespace >>
        str("}") >> (str("*") | str("+") | str("?")).maybe.as(:occurrence)
    end

    rule(:attribute_def) do
      (doc_comments >> whitespace).maybe.as(:docs) >>
        str("attribute") >> space >>
        name_class.as(:name) >>
        whitespace >>
        str("{") >>
        whitespace >>
        attribute_content.as(:type) >>
        whitespace >>
        str("}") >>
        (str("*") | str("+") | str("?")).maybe.as(:occurrence)
    end

    # Attribute content can be: parenthesized choice, datatype_ref, text, value literal, or choice of values
    rule(:attribute_content) do
      # Parenthesized choice: ( "a" | "b" | "c" ) or ( ref1 | ref2 )
      (str("(") >> whitespace >>
       (value_literal | identifier.as(:ref)) >>
       (whitespace >> str("|") >> whitespace >> (value_literal | identifier.as(:ref))).repeat(1) >>
       whitespace >> str(")")).as(:paren_choice) |
      # Non-parenthesized choice of value literals: "a" | "b" | "c"
      (value_literal >> (whitespace >> str("|") >> whitespace >> value_literal).repeat(1).as(:value_choice)) |
        value_literal |
        datatype_ref |
        str("text").as(:text_type) |
        identifier.as(:ref)
    end

    rule(:datatype_ref) do
      identifier.as(:prefix) >> str(":") >> identifier.as(:type) >>
        (whitespace >> str("{") >> whitespace >>
         param_list.as(:params) >> whitespace >> str("}")).maybe
    end

    # Parameter list for datatypes (e.g., pattern = "value", minLength = "1")
    rule(:param_list) do
      param_item >> (whitespace >> param_item).repeat
    end

    # Single parameter (e.g., pattern = "value")
    rule(:param_item) do
      identifier.as(:param_name) >> whitespace >> str("=") >> whitespace >>
        string_literal.as(:param_value)
    end

    # Word boundary - ensure keywords are not followed by identifier characters
    # This prevents "text" from matching "textarea", etc.
    rule(:word_boundary) { match("[a-zA-Z0-9_-]").absent? }
    
    # Keyword patterns with word boundaries
    rule(:text_def) { (str("text") >> word_boundary).as(:text) }
    rule(:empty_def) { (str("empty") >> word_boundary).as(:empty) }
    rule(:not_allowed_def) { (str("notAllowed") >> word_boundary).as(:not_allowed) }

    rule(:list_pattern) do
      str("list") >> whitespace >> str("{") >> whitespace >>
        list_content.as(:list_content) >> whitespace >> str("}")
    end

    rule(:parent_ref) do
      str("parent") >> space >> identifier.as(:parent_pattern)
    end

    rule(:external_ref) do
      str("external") >> space >> string_literal.as(:external_href)
    end

    # List content can be: text, datatype references, or other patterns with occurrence markers
    rule(:list_content_item) do
      (datatype_ref | text_def | identifier.as(:ref)) >>
        (str("*") | str("+") | str("?")).maybe.as(:occurrence)
    end

    rule(:list_content) do
      list_content_item.as(:first) >>
        (comma? >> list_content_item).repeat.as(:sequence_items).maybe
    end

    rule(:group_def) do
      str("(") >>
        whitespace >>
        content.as(:group) >>
        whitespace >>
        str(")") >> (str("*") | str("+") | str("?")).maybe.as(:occurrence)
    end

    # Named pattern definition (e.g., "myPattern = element foo { text }")
    rule(:named_pattern) do
      (doc_comments >> whitespace).maybe.as(:docs) >>
        identifier.as(:name) >> whitespace >>
        (str("|=") | str("&=") | str("=")).as(:operator) >> whitespace >>
        pattern_list.as(:pattern)
    end

    # Start pattern definition
    rule(:start_def) do
      (doc_comments >> whitespace).maybe.as(:docs) >>
        str("start") >> whitespace >>
        (str("|=") | str("&=") | str("=")).as(:operator) >> whitespace >>
        pattern_list.as(:start_pattern)
    end

    # Pattern list - similar to content but without being wrapped in element/attribute
    rule(:pattern_list) do
      content_item.as(:first) >>
        (
          (whitespace >> str("|") >> whitespace >> content_item).repeat(1).as(:choice_items) |
          (comma? >> content_item).repeat(1).as(:sequence_items)
        ).maybe
    end

    # Choice is handled at content level, not as separate pattern
    rule(:content_item) do
      element_def | attribute_def | text_def | empty_def | not_allowed_def |
        list_pattern | parent_ref | external_ref | group_def | mixed_pattern |
        value_literal | datatype_ref |
        (identifier.as(:ref) >> (str("*") | str("+") | str("?")).maybe.as(:occurrence))
    end

    # Content can be a sequence with commas, or alternatives with |
    rule(:content) do
      content_item.as(:first) >>
        (
          (whitespace >> str("|") >> whitespace >> content_item).repeat(1).as(:choice_items) |
          (comma? >> content_item).repeat(1).as(:sequence_items)
        ).maybe
    end

    # Parse balanced braces content - matches everything inside {} including nested {}
    rule(:balanced_braces) do
      (
        (str("{") >> balanced_braces >> str("}")) |
        (str("{").absent? >> str("}").absent? >> any)
      ).repeat
    end

    # Include directive - capture override as raw text to avoid backtracking
    # Will be parsed with proper scoping in post-processing
    rule(:include_directive) do
      str("include") >> space >> string_literal.as(:href) >> whitespace >>
        (str("{") >> whitespace >>
         balanced_braces.as(:raw_override) >>
         whitespace >> str("}")).maybe.as(:override)
    end

    # Include directive - legacy layout with start_def first
    rule(:include_directive_legacy) do
      str("include") >> space >> string_literal.as(:href) >> whitespace >>
        start_def.maybe.as(:start) >> whitespace >>
        (named_pattern | element_def.as(:top_element)).repeat.as(:definitions)
    end

    # Div block for documentation and grouping
    rule(:div_block) do
      str("div") >> whitespace >> str("{") >> whitespace >>
        (start_def.maybe.as(:start) >>
         whitespace >>
         (include_directive >> whitespace).repeat.as(:includes) >>
         ((named_pattern | div_block.as(:nested_div) | element_def.as(:top_element)) >> whitespace).repeat.as(:patterns)) >>
        whitespace >> str("}")
    end

    # Standalone pattern - like content_item but without element_def/attribute_def/value_literal
    # These are patterns that can appear at grammar level without being definitions
    # Note: value_literal (strings) should only appear inside elements/attributes
    rule(:standalone_pattern) do
      text_def | empty_def | not_allowed_def |
        list_pattern | parent_ref | external_ref | group_def | mixed_pattern |
        datatype_ref |
        (identifier.as(:ref) >> (str("*") | str("+") | str("?")).maybe.as(:occurrence))
    end

    # Grammar can have optional datatype library, start, then multiple named patterns and elements
    # Allow standalone patterns (like 'foo', 'text', 'empty', etc.) as a fallback
    rule(:grammar) do
      start_def.maybe.as(:start) >>
        whitespace >>
        (include_directive >> whitespace).repeat.as(:includes) >>
        ((named_pattern | div_block.as(:div) | element_def.as(:top_element) |
          standalone_pattern.as(:standalone)) >> whitespace).repeat.as(:patterns)
    end

    # Grammar block wrapper - capture content as raw text to avoid backtracking
    # Will be parsed with proper scoping in post-processing
    rule(:grammar_block) do
      str("grammar") >> whitespace >> str("{") >> whitespace >>
        balanced_braces.as(:raw_grammar) >>
        whitespace >> str("}")
    end

    # Included file - more flexible than grammar_wrapper
    # Can be:
    # 1. Just a flat grammar (patterns only)
    # 2. Grammar block
    # 3. Grammar block with trailing definitions
    # 4. Preamble + grammar/grammar_block
    # 5. Empty file
    rule(:included_file) do
      whitespace >>
        preamble.maybe >>
        whitespace >>
        (
          # Grammar block with optional trailing definitions
          grammar_block.as(:inner_grammar) >>
          (whitespace >> (named_pattern | element_def.as(:top_element))).repeat.as(:trailing_definitions) |
          # Flat grammar (no wrapper)
          grammar |
          # Empty file is also valid
          str("")
        ) >>
        whitespace
    end

    # Schema preamble - multiple namespace and datatype declarations
    rule(:preamble_item) do
      (namespace_decl | datatype_decl) >> whitespace
    end

    rule(:preamble) do
      preamble_item.repeat.as(:preamble_items)
    end

    # Root can be a grammar block with optional definitions after, OR plain grammar (for flat RNC files), with optional preamble at top
    root(:grammar_wrapper)
    rule(:grammar_wrapper) do
      whitespace >>
        preamble.maybe >>
        whitespace >>
        (
          # Try in order from most specific to least specific
          # 1. Grammar block (starts with literal "grammar {")
          (grammar_block.as(:inner_grammar) >>
           (whitespace >> (named_pattern | element_def.as(:top_element))).repeat.as(:trailing_definitions)) |
          # 2. Top-level includes (for Metanorma-style schemas) - use raw capture for trailing
          ((include_directive >> whitespace).repeat(1).as(:top_includes) >>
           whitespace >> any.repeat.as(:raw_trailing)) |
          # 3. Flat grammar (default - most flexible) - raw_patterns handled internally
          grammar
        ) >>
        whitespace
    end

    # Class method to parse a file with include resolution
    def self.parse_file(file_path, base_dir = nil, visited_files = Set.new)
      IncludeProcessor.new.parse_file(file_path, base_dir, visited_files)
    end

    def self.parse(input)
      parser = new
      tree = parser.parse(input.strip)

      # Normalize parse tree
      processor = ParseTreeProcessor.new(tree)
      normalized = processor.normalize

      # Convert to RNG XML and Grammar object
      rng_xml = convert_to_rng(normalized.grammar_tree)
      Grammar.from_xml(rng_xml)
    end

    # Convert RNG schema to RNC
    def self.to_rnc(schema)
      RncBuilder.new.build(schema)
    end

    # Convert parse tree to RNG XML
    def self.convert_to_rng(tree)
      RncToRngConverter.new.convert(tree)
    end
  end
end