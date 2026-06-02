# frozen_string_literal: true

require 'parslet'
require 'nokogiri'
require 'set'

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
    rule(:comment) { str('#') >> str('#').absent? >> match('[^\n]').repeat >> (str("\n") | any.absent?) }
    rule(:comment?) { comment.maybe }

    # Documentation comment: ##
    rule(:doc_comment) { str('##') >> match('[^\n]').repeat.as(:doc_line) >> (str("\n") | any.absent?) }
    rule(:doc_comments) { (doc_comment >> (whitespace.maybe >> doc_comment).repeat).as(:documentation) }

    # Whitespace (including comments)
    rule(:space) { match('\s').repeat(1) }
    rule(:space?) { space.maybe }
    rule(:newline) { (str("\r").maybe >> str("\n")).repeat(1) }
    rule(:newline?) { newline.maybe }
    # Only regular comments in whitespace - doc comments are captured by pattern rules
    rule(:whitespace) { (space | newline | comment).repeat }
    rule(:comma) { str(',') }
    rule(:comma?) { (whitespace >> comma >> whitespace).maybe }

    # Escape sequences support
    # Unicode code point: \x{HHHHHH} (1-6 hex digits)
    rule(:hex_escape) do
      str('\\x{') >> match('[0-9a-fA-F]').repeat(1, 6).as(:hex) >> str('}')
    end

    # Match a keyword that may contain hex escapes
    # Hex escapes are resolved in pre-processing, so keywords match literally here
    # But we still need to handle the case where pre-processing didn't happen
    def keyword(kw)
      str(kw)
    end

    # Character escapes for strings: \", \\, \n, \r, \t, and RELAX NG class escapes: \i, \c, \d, \w
    # Any other \X sequence is preserved literally (e.g., \+, \-, \. in regex patterns)
    rule(:char_escape) do
      str('\\') >> (match('["\\\\ntricdw]') | match('[^x]')).as(:char)
    end

    # Identifier can contain regular chars, dots, hex escapes, or backslash escapes
    rule(:identifier_char) do
      hex_escape.as(:hex_escape) |
        (str('\\') >> str('\\').as(:escaped_backslash)).as(:backslash_escape) |
        (str('\\') >> (match('[a-zA-Z0-9_.-]').as(:escaped_char) | match('[a-zA-Z]').as(:escaped_keyword))).as(:backslash_escape) |
        match('[a-zA-Z0-9_.-]').as(:char)
    end

    rule(:identifier) { identifier_char.repeat(1).as(:identifier_parts) }
    rule(:namespace_prefix) { identifier.as(:prefix) >> str(':') }
    rule(:namespace_prefix?) { namespace_prefix.maybe }
    rule(:qualified_name) { namespace_prefix? >> identifier.as(:local_name) }

    # Name wildcards for anyName and nsName patterns

    # anyName wildcard: *  or  * - exceptName
    rule(:any_name_pattern) do
      str('*') >>
        (space >> str('-') >> space >> name_class_except).maybe.as(:except)
    end

    # nsName wildcard: prefix:*  or  prefix:* - exceptName
    rule(:ns_name_pattern) do
      namespace_prefix >> str('*') >>
        (space >> str('-') >> space >> name_class_except).maybe.as(:except)
    end

    # Except clause can be a single name or multiple names in parentheses
    rule(:name_class_except) do
      (str('(') >> space? >> name_class >>
       (space? >> str('|') >> space? >> name_class).repeat >>
       space? >> str(')')) |
        name_class
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
        (qualified_name >> (space? >> str('|') >> space? >> qualified_name).repeat(1).as(:name_choice_items)).as(:name_choice) |
        qualified_name.as(:name)
    end

    # Datatype library declaration (same as datatype_library but different name for clarity)
    rule(:datatype_decl) do
      keyword('datatypes') >> space >>
        identifier.as(:prefix) >> space? >>
        str('=') >> space? >>
        string_literal.as(:uri)
    end

    # String literal with optional concatenation using ~ operator
    # Supports escape sequences: \x{HEX}, \", \\, \n, \r, \t
    # Control characters (0x00-0x1F, 0x7F) must be escaped
    rule(:string_char) do
      hex_escape.as(:hex_escape) |
        char_escape.as(:char_escape) |
        (str('\\').absent? >> str('"').absent? >>
         match('[\u0000-\u001F\u007F]').absent? >> any).as(:char)
    end

    # String chars for single-quote strings (same escapes, different delimiter)
    rule(:single_string_char) do
      hex_escape.as(:hex_escape) |
        char_escape.as(:char_escape) |
        (str('\\').absent? >> str("'").absent? >>
         match('[\u0000-\u001F\u007F]').absent? >> any).as(:char)
    end

    rule(:string_literal) do
      # Multi-line strings: """...""" (can span multiple lines)
      # Content is any char except """
      # Use a helper: char is content if """ is NOT at this position
      multi_line_double = str('"""') >>
                          (str('"""').absent? >> any).repeat.as(:multi_line_parts) >>
                          str('"""')
      # Multi-line strings: '''...''' (can span multiple lines)
      multi_line_single = str("'''") >>
                          (str("'''").absent? >> any).repeat.as(:multi_line_parts) >>
                          str("'''")
      # Single-line double-quote strings with concatenation: "..." ~ "..."
      double_string = str('"') >> string_char.repeat.as(:string_parts) >> str('"')
      # Single-line single-quote strings with concatenation: '...' ~ '...'
      single_string = str("'") >> single_string_char.repeat.as(:string_parts) >> str("'")
      concat_part = whitespace >> str('~') >> whitespace >>
                    str('"') >> string_char.repeat.as(:concat_string_parts) >> str('"')
      single_concat_part = whitespace >> str('~') >> whitespace >>
                           str("'") >> single_string_char.repeat.as(:concat_string_parts) >> str("'")

      multi_line_concat_double = whitespace >> str('~') >> whitespace >>
                                 str('"""') >>
                                 (str('"""').absent? >> any).repeat.as(:concat_multi_line_parts) >>
                                 str('"""')
      multi_line_concat_single = whitespace >> str('~') >> whitespace >>
                                 str("'''") >>
                                 (str("'''").absent? >> any).repeat.as(:concat_multi_line_parts) >>
                                 str("'''")

      # Ordered choice: try with concatenation first, then bare multi-line fallback
      (multi_line_double >> (concat_part | single_concat_part | multi_line_concat_double | multi_line_concat_single).repeat.maybe.as(:concatenations)) |
        (multi_line_single >> (concat_part | single_concat_part | multi_line_concat_double | multi_line_concat_single).repeat.maybe.as(:concatenations)) |
        (double_string >> (concat_part | single_concat_part | multi_line_concat_double | multi_line_concat_single).repeat.maybe.as(:concatenations)) |
        (single_string >> (concat_part | single_concat_part | multi_line_concat_double | multi_line_concat_single).repeat.maybe.as(:concatenations))
    end

    # Value pattern for literal values
    rule(:value_literal) { string_literal.as(:value) }

    # Mixed content pattern
    rule(:mixed_pattern) do
      keyword('mixed') >> whitespace >> str('{') >> whitespace >>
        content.as(:mixed_content) >> whitespace >> str('}')
    end

    # Namespace declarations
    # Default namespace (unprefixed): default namespace = "uri"
    rule(:default_namespace_decl) do
      keyword('default') >> space >> keyword('namespace') >> space? >>
        str('=') >> space? >> string_literal.as(:uri)
    end

    # Default namespace (prefixed): default namespace prefix = "uri"
    rule(:default_prefixed_namespace_decl) do
      keyword('default') >> space >> keyword('namespace') >> space >>
        identifier.as(:prefix) >> space? >>
        str('=') >> space? >> string_literal.as(:uri)
    end

    # Prefixed namespace: namespace prefix = "uri"
    rule(:prefixed_namespace_decl) do
      keyword('namespace') >> space >>
        identifier.as(:prefix) >> space? >>
        str('=') >> space? >> string_literal.as(:uri)
    end

    # Any namespace declaration
    rule(:namespace_decl) do
      default_prefixed_namespace_decl.as(:default_prefixed_ns) |
        default_namespace_decl.as(:default_ns) |
        prefixed_namespace_decl.as(:prefixed_ns)
    end

    # Annotation element inner content (recursive for nested brackets)
    rule(:annotation_inner_content) do
      (
        # Nested annotation brackets
        (str('[') >> annotation_inner_content >> str(']')) |
        # String literal (don't let brackets inside strings confuse us)
        string_literal |
        # Any char that's not a bracket, quote
        (str('[').absent? >> str(']').absent? >> str('"').absent? >> str("'").absent? >>
         any)
      ).repeat
    end

    # Annotation attribute: prefix:local = "value" or local = "value"
    rule(:annotation_attr) do
      (((namespace_prefix >> identifier) | identifier).as(:ann_name) >>
        whitespace >> str('=') >> whitespace >>
        string_literal.as(:attr_value)).as(:ann_attr)
    end

    # Annotation element: prefix:local [ content ] or local [ content ]
    rule(:annotation_elem) do
      (((namespace_prefix >> identifier) | identifier).as(:elem_name) >>
        whitespace >> str('[') >> whitespace >>
        annotation_inner_content.as(:inner_content) >> whitespace >>
        str(']')).as(:ann_elem)
    end

    # A single annotation item (attribute or element)
    rule(:annotation_item) do
      annotation_elem | annotation_attr
    end

    # Annotation content: sequence of annotation items OR empty OR raw content (comments, etc.)
    # Raw content matches any character that is NOT a bracket or quote
    rule(:annotation_content) do
      (annotation_item >> (whitespace >> annotation_item).repeat >> whitespace).as(:ann_items) |
        (str('[').absent? >> str(']').absent? >> str('"').absent? >> str("'").absent? >> any).repeat.as(:raw_content) |
        whitespace
    end

    # Single annotation: [ content ] where content can contain nested brackets, strings, etc.
    # Appears before patterns, definitions, and within annotation elements
    # Handles both empty [] and content-bearing [x = "y"] annotations
    rule(:annotation) do
      str('[') >> whitespace >>
        (
          (annotation_content >> whitespace >> str(']')).as(:ann) |
          str(']').as(:ann)
        )
    end

    # One or more annotations preceding a pattern
    rule(:annotations) do
      (whitespace >> annotation).repeat(1)
    end

    # Notation/annotation: [ key = "value" ] or just [ ... ]
    # Notations are only valid when attached to patterns using >>, not as standalone preamble items
    rule(:notation) do
      annotation
    end

    rule(:element_def) do
      (doc_comments >> whitespace).maybe.as(:docs) >>
        annotations.maybe.as(:annotations) >>
        keyword('element') >> whitespace >>
        name_class.as(:name) >>
        whitespace >>
        str('{') >> whitespace >>
        content.maybe.as(:content) >> whitespace >>
        str('}') >> (str('*') | str('+') | str('?')).maybe.as(:occurrence)
    end

    rule(:attribute_def) do
      (doc_comments >> whitespace).maybe.as(:docs) >>
        annotations.maybe.as(:annotations) >>
        keyword('attribute') >> whitespace >>
        name_class.as(:name) >>
        whitespace >>
        str('{') >>
        whitespace >>
        attribute_content.as(:type) >>
        whitespace >>
        str('}') >>
        (str('*') | str('+') | str('?')).maybe.as(:occurrence)
    end

    # Attribute content can be: parenthesized choice, datatype_ref, text, value literal, or choice of values
    rule(:attribute_content) do
      # Parenthesized choice: ( "a" | "b" | "c" ) or ( ref1 | ref2 )
      (str('(') >> whitespace >>
       (value_literal | identifier.as(:ref)) >>
       (whitespace >> str('|') >> whitespace >> (value_literal | identifier.as(:ref))).repeat(1) >>
       whitespace >> str(')')).as(:paren_choice) |
        # Datatype except: prefix:type - ( "a" | "b" ) or type - ( "a" | "b" )
        (identifier.as(:datatype_prefix) >> str(':') >> identifier.as(:datatype_type) >>
          whitespace >> str('-') >> whitespace >>
          str('(') >> whitespace >>
          value_literal >>
          (whitespace >> str('|') >> whitespace >> value_literal).repeat(1) >>
          whitespace >> str(')')).as(:datatype_except) |
        (identifier.as(:datatype_type) >>
          whitespace >> str('-') >> whitespace >>
          str('(') >> whitespace >>
          value_literal >>
          (whitespace >> str('|') >> whitespace >> value_literal).repeat(1) >>
          whitespace >> str(')')).as(:datatype_except) |
        # Non-parenthesized choice of items: "a" | "b", text | "a", "a" | ref, text | ref
        (attribute_choice_item >> (whitespace >> str('|') >> whitespace >> attribute_choice_item).repeat(1).as(:attribute_choice)) |
        value_literal |
        datatype_ref |
        keyword('text').as(:text_type) |
        identifier.as(:ref)
    end

    rule(:attribute_choice_item) do
      keyword('text').as(:text_type) | value_literal | identifier.as(:ref)
    end

    rule(:datatype_ref) do
      identifier.as(:prefix) >> str(':') >> identifier.as(:type) >>
        (whitespace >> str('{') >> whitespace >>
         param_list.as(:params) >> whitespace >> str('}')).maybe
    end

    # Parameter list for datatypes (e.g., pattern = "value", minLength = "1")
    rule(:param_list) do
      param_item >> (whitespace >> param_item).repeat
    end

    # Single parameter (e.g., pattern = "value")
    rule(:param_item) do
      identifier.as(:param_name) >> whitespace >> str('=') >> whitespace >>
        string_literal.as(:param_value)
    end

    # Word boundary - ensure keywords are not followed by identifier characters
    # This prevents "text" from matching "textarea", etc.
    rule(:word_boundary) { match('[a-zA-Z0-9_-]').absent? }

    # Keyword patterns with word boundaries
    rule(:text_def) { (keyword('text') >> word_boundary).as(:text) }
    rule(:empty_def) { (keyword('empty') >> word_boundary).as(:empty) }
    rule(:not_allowed_def) { (keyword('notAllowed') >> word_boundary).as(:not_allowed) }

    rule(:list_pattern) do
      keyword('list') >> whitespace >> str('{') >> whitespace >>
        list_content.as(:list_content) >> whitespace >> str('}')
    end

    rule(:parent_ref) do
      keyword('parent') >> whitespace >> identifier.as(:parent_pattern)
    end

    rule(:external_ref) do
      keyword('external') >> space >> string_literal.as(:external_href)
    end

    # List content can be: text, datatype references, or other patterns with occurrence markers
    rule(:list_content_item) do
      (datatype_ref | text_def | identifier.as(:ref)) >>
        (str('*') | str('+') | str('?')).maybe.as(:occurrence)
    end

    rule(:list_content) do
      list_content_item.as(:first) >>
        (comma? >> list_content_item).repeat.as(:sequence_items).maybe
    end

    rule(:group_def) do
      str('(') >>
        whitespace >>
        content.as(:group) >>
        whitespace >>
        str(')') >> (str('*') | str('+') | str('?')).maybe.as(:occurrence)
    end

    # Named pattern definition (e.g., "myPattern = element foo { text }")
    rule(:named_pattern) do
      (doc_comments >> whitespace).maybe.as(:docs) >>
        annotations.maybe >>
        identifier.as(:name) >> whitespace >>
        (str('|=') | str('&=') | str('=')).as(:operator) >> whitespace >>
        pattern_list.as(:pattern)
    end

    # Start pattern definition
    rule(:start_def) do
      (doc_comments >> whitespace).maybe.as(:docs) >>
        annotations.maybe >>
        keyword('start') >> whitespace >>
        (str('|=') | str('&=') | str('=')).as(:operator) >> whitespace >>
        pattern_list.as(:start_pattern)
    end

    # Pattern list - similar to content but without being wrapped in element/attribute
    rule(:pattern_list) do
      content_item.as(:first) >>
        (
          (whitespace >> str('&') >> whitespace >> content_item).repeat(1).as(:interleave_items) |
          (whitespace >> str('|') >> whitespace >> content_item).repeat(1).as(:choice_items) |
          (comma? >> content_item).repeat(1).as(:sequence_items)
        ).maybe
    end

    # Choice is handled at content level, not as separate pattern
    rule(:content_item) do
      (doc_comments >> whitespace).maybe >>
        annotations.maybe >>
        (element_def | attribute_def |
          # Datatype subtraction: identifier - ( value|identifier|choice|annotated )
          (identifier.as(:datatype_name) >>
            whitespace >> str('-') >> whitespace >>
            str('(') >> whitespace >>
            datatype_except_value >>
            (whitespace >> str('|') >> whitespace >> datatype_except_value).repeat.as(:more_except) >>
            whitespace >> str(')')).as(:datatype_subtraction) |
          (text_def >> (str('*') | str('+') | str('?')).maybe.as(:occurrence)) |
          (empty_def >> (str('*') | str('+') | str('?')).maybe.as(:occurrence)) |
          (not_allowed_def >> (str('*') | str('+') | str('?')).maybe.as(:occurrence)) |
          list_pattern | parent_ref | external_ref | group_def | mixed_pattern |
          grammar_block.as(:grammar_block) |
          (value_literal >> (str('*') | str('+') | str('?')).maybe.as(:occurrence)) |
          (datatype_ref >> (str('*') | str('+') | str('?')).maybe.as(:occurrence)) |
          (identifier.as(:ref) >> (str('*') | str('+') | str('?')).maybe.as(:occurrence)))
    end

    # Value that can appear in a datatype except clause
    # Includes string literals, identifiers (for datatype names), annotated values,
    # and parenthesized content (for nested groups with annotations)
    rule(:datatype_except_value) do
      # Annotated parenthesized content: group_def >> annotation
      (group_def >>
        whitespace >> str('>>') >> whitespace >>
        (foreign_element | annotation).as(:annotation)).as(:annotated_except_value) |
        # Annotated value: value_literal >> identifier [] or value_literal >> [ ... ]
        ((value_literal | identifier.as(:datatype_name)) >>
          whitespace >> str('>>') >> whitespace >>
          (foreign_element | annotation).as(:annotation)).as(:annotated_except_value) |
        # Regular parenthesized content (without annotation)
        group_def |
        # Regular value literal or identifier
        value_literal |
        identifier.as(:datatype_name)
    end

    # Content can be interleaved with &, a sequence with commas, or alternatives with |
    rule(:content) do
      content_item.as(:first) >>
        (
          # Annotation attachment: pattern >> identifier [] or pattern >> [ content ]
          (whitespace >> str('>>') >> whitespace >> (foreign_element | annotation).as(:annotation_attached)).repeat(1).as(:annotation_chain) |
          (whitespace >> str('&') >> whitespace >> content_item).repeat(1).as(:interleave_items) |
          (whitespace >> str('|') >> whitespace >> content_item).repeat(1).as(:choice_items) |
          (comma? >> content_item).repeat(1).as(:sequence_items)
        ).maybe
    end

    # Parse balanced braces content - matches everything inside {} including nested {}
    rule(:balanced_braces) do
      (
        (str('{') >> balanced_braces >> str('}')) |
        (str('{').absent? >> str('}').absent? >> any)
      ).repeat
    end

    # Include directive - capture override as raw text to avoid backtracking
    # Will be parsed with proper scoping in post-processing
    rule(:include_directive) do
      keyword('include') >> space >> string_literal.as(:href) >> whitespace >>
        (str('{') >> whitespace >>
         balanced_braces.as(:raw_override) >>
         whitespace >> str('}')).maybe.as(:override)
    end

    # Include directive - legacy layout with start_def first
    rule(:include_directive_legacy) do
      keyword('include') >> space >> string_literal.as(:href) >> whitespace >>
        start_def.maybe.as(:start) >> whitespace >>
        (named_pattern | element_def.as(:top_element)).repeat.as(:definitions)
    end

    # Foreign element at grammar/div level: name [annotation-content]
    # e.g., foo [] or rng:foo [ "val" ] or foo [ bar [ "baz" ] ]
    # These are annotation elements that appear as standalone items
    rule(:foreign_element) do
      ((namespace_prefix >> identifier) | identifier).as(:foreign_name) >>
        whitespace >> annotation.as(:foreign_annotation)
    end

    # Div block for documentation and grouping
    rule(:div_block) do
      keyword('div') >> whitespace >> str('{') >> whitespace >>
        (start_def.maybe.as(:start) >>
         whitespace >>
         (include_directive >> whitespace).repeat.as(:includes) >>
         ((named_pattern | foreign_element | div_block.as(:nested_div) | element_def.as(:top_element)) >> whitespace).repeat.as(:patterns)) >>
        whitespace >> str('}')
    end

    # Standalone pattern - like content_item but without element_def/attribute_def
    # These are patterns that can appear at grammar level without being definitions
    rule(:standalone_pattern) do
      text_def | empty_def | not_allowed_def |
        list_pattern | parent_ref | external_ref | group_def | mixed_pattern |
        datatype_ref |
        value_literal |
        (identifier.as(:ref) >> (str('*') | str('+') | str('?')).maybe.as(:occurrence)) |
        (str('*') >> (str('-') >> space >> name_class).maybe.as(:any_name_except)).as(:bare_any_name)
    end

    # Grammar-level choice: allows element foo { empty } | element bar { empty }
    # at the top level of a grammar
    rule(:grammar_choice) do
      (element_def | standalone_pattern).as(:first) >>
        (whitespace >> str('|') >> whitespace >>
         (element_def | standalone_pattern)).repeat(1).as(:choice_items)
    end

    # Grammar can have optional datatype library, start, then multiple named patterns and elements
    # Allow standalone patterns (like 'foo', 'text', 'empty', etc.) as a fallback
    # Allow grammar-level choice: element foo { empty } | element bar { empty }
    rule(:grammar) do
      start_def.maybe.as(:start) >>
        whitespace >>
        (include_directive >> whitespace).repeat.as(:includes) >>
        ((named_pattern | foreign_element | div_block.as(:div) | grammar_choice.as(:top_choice) |
          element_def.as(:top_element) |
          standalone_pattern.as(:standalone)) >> whitespace).repeat.as(:patterns)
    end

    # Grammar block wrapper - capture content as raw text to avoid backtracking
    # Will be parsed with proper scoping in post-processing
    rule(:grammar_block) do
      keyword('grammar') >> whitespace >> str('{') >> whitespace >>
        balanced_braces.as(:raw_grammar) >>
        whitespace >> str('}')
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
          (grammar_block.as(:inner_grammar) >>
          (whitespace >> (named_pattern | element_def.as(:top_element))).repeat.as(:trailing_definitions)) |
          # Flat grammar (no wrapper)
          grammar |
          # Empty file is also valid
          str('')
        ) >>
        whitespace
    end

    # Schema preamble - namespace and datatype declarations
    # Annotations [ key = "value" ] are also allowed in preamble for documentation
    rule(:preamble_item) do
      (namespace_decl | datatype_decl | notation) >> whitespace
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

    # Pre-process RNC input to resolve hex escapes (\x{HHHHHH})
    # outside of string literals. This allows keywords to contain hex escapes
    # (e.g., \x{65}l\x{00065}ment = "element").
    # String literals keep their hex escapes for the parser to handle,
    # because control characters like \x{A} (newline) are forbidden inside
    # single-line quoted strings and must remain escaped.
    def self.preprocess_hex_escapes(input)
      result = +''
      i = 0
      while i < input.length
        # Triple-quoted strings: copy verbatim
        if input[i, 3] == '"""'
          end_idx = input.index('"""', i + 3)
          end_idx ||= input.length - 3
          result << input[i..(end_idx + 2)]
          i = end_idx + 3
        elsif input[i, 3] == "'''"
          end_idx = input.index("'''", i + 3)
          end_idx ||= input.length - 3
          result << input[i..(end_idx + 2)]
          i = end_idx + 3
        # Single-line double-quoted string: copy verbatim
        elsif input[i] == '"'
          j = i + 1
          while j < input.length && input[j] != '"'
            j += 1 if input[j] == '\\' && j + 1 < input.length # skip escaped char
            j += 1
          end
          result << input[i..j]
          i = j + 1
        # Single-line single-quoted string: copy verbatim
        elsif input[i] == "'"
          j = i + 1
          while j < input.length && input[j] != "'"
            j += 1 if input[j] == '\\' && j + 1 < input.length # skip escaped char
            j += 1
          end
          result << input[i..j]
          i = j + 1
        # Comment: copy verbatim to end of line
        elsif input[i] == '#'
          j = input.index("\n", i) || input.length
          result << input[i...j]
          i = j
        # Hex escape outside string: decode it
        elsif input[i] == '\\' && input[i + 1] == 'x' && input[i + 2] == '{'
          end_brace = input.index('}', i + 3)
          if end_brace
            hex = input[(i + 3)...end_brace]
            if hex.match?(/\A[0-9a-fA-F]{1,6}\z/)
              code_point = hex.to_i(16)
              if code_point <= 0x10FFFF && !code_point.between?(0xD800, 0xDFFF) &&
                 code_point >= 0x20 # Reject control characters outside strings
                result << [code_point].pack('U')
                i = end_brace + 1
                next
              end
            end
          end
          # Not a valid hex escape, copy as-is
          result << input[i]
          i += 1
        else
          result << input[i]
          i += 1
        end
      end
      result
    end

    def self.parse(input)
      parser = new
      preprocessed = preprocess_hex_escapes(input.strip)
      tree = parser.parse(preprocessed)

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
