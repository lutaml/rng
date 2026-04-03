# frozen_string_literal: true

require 'nokogiri'
require 'uri'

module Rng
  # Raised when a schema violates RELAX NG structural rules
  class SchemaValidationError < StandardError
    attr_reader :xpath, :line

    def initialize(message, xpath: nil, line: nil)
      super(message)
      @xpath = xpath
      @line = line
    end

    def to_s
      location = [@xpath, @line].compact.join(':')
      base = super
      location.empty? ? base : "#{location}: #{base}"
    end
  end

  # Validates raw XML against RELAX NG structural rules.
  # Operates on the Nokogiri XML tree BEFORE Lutaml deserialization,
  # because Lutaml silently drops unmapped content.
  class SchemaValidator
    RNG_NS = 'http://relaxng.org/ns/structure/1.0'
    ANNOTATIONS_NS = 'http://relaxng.org/ns/compatibility/annotations/1.0'

    LEAF_ELEMENTS = %w[empty text notAllowed ref parentRef value].freeze
    OBSOLETE_ELEMENTS = %w[not difference key keyRef].freeze
    OBSOLETE_ATTRS = %w[key keyRef global].freeze
    NAME_REQUIRED = %w[element attribute].freeze
    CONTAINER_ELEMENTS = %w[group choice interleave optional zeroOrMore oneOrMore list mixed define start].freeze
    VALID_ROOT_ELEMENTS = %w[grammar element group choice interleave notAllowed externalRef data].freeze
    NO_ATTR_LEAF_ELEMENTS = %w[empty text notAllowed].freeze

    KNOWN_ATTRS = {
      'element' => %w[name ns],
      'attribute' => %w[name ns],
      'ref' => %w[name],
      'parentRef' => %w[name],
      'define' => %w[name combine],
      'data' => %w[type datatypeLibrary combine],
      'value' => %w[type datatypeLibrary combine],
      'list' => %w[datatypeLibrary combine],
      'externalRef' => %w[href ns],
      'include' => %w[href],
      'param' => %w[name],
      'grammar' => %w[ns datatypeLibrary],
      'start' => %w[combine],
      'anyName' => %w[],
      'nsName' => %w[ns],
      'except' => %w[]
    }.freeze
    VALID_UNPREFIXED_ATTRS = %w[name ns type datatypeLibrary combine href key keyRef global].freeze
    GENERIC_ATTRS = %w[name ns type datatypeLibrary combine href].freeze

    # Elements not allowed as content in attribute
    ATTR_DISALLOWED = %w[element attribute group interleave mixed].freeze
    # Elements not allowed in list content
    LIST_DISALLOWED = %w[element attribute list interleave mixed].freeze
    # Elements not allowed in data/except content
    DATA_EXCEPT_DISALLOWED = %w[element attribute text list interleave mixed group choice].freeze

    class << self
      def validate(xml_input)
        doc = Nokogiri::XML(xml_input)
        root = doc.root
        report_error('Document has no root element') unless root
        validator = new
        validator.validate_node(root)
        true
      end

      def validate_all(xml_input)
        doc = Nokogiri::XML(xml_input)
        root = doc.root
        return [SchemaValidationError.new('Document has no root element')] unless root

        validator = new(collect_all: true)
        begin
          validator.validate_node(root)
        rescue SchemaValidationError
          # Continue collecting
        end
        validator.errors
      end

      def valid?(xml_input)
        doc = Nokogiri::XML(xml_input)
        root = doc.root
        return false unless root

        validator = new
        validator.validate_node(root)
        true
      rescue SchemaValidationError
        false
      end

      def validate_with_location(xml_input)
        validate_all(xml_input)
      end
    end

    attr_reader :errors

    def initialize(collect_all: false)
      @errors = []
      @collect_all = collect_all
    end

    def validate_node(node, parent_context: nil)
      return unless node.is_a?(Nokogiri::XML::Element)

      ns = node.namespace&.href
      local_name = node.name
      is_root = node.parent&.document&.root == node
      xpath = node.path.delete_prefix('/')

      # For root elements, check validity first
      if is_root
        if ns != RNG_NS && !VALID_ROOT_ELEMENTS.include?(local_name)
          report_error("Invalid root element '#{local_name}'", xpath: xpath, node: node)
          return
        end
      else
        # Skip foreign elements (non-RNG namespace) for non-root elements
        return unless ns == RNG_NS || (ns.nil? && !local_name.empty?)
        return if ns == ANNOTATIONS_NS
      end

      # ---- Existing rules ----
      report_obsolete_element(local_name, xpath)
      report_invalid_root(local_name, node, xpath)
      validate_obsolete_attrs(node, xpath)
      validate_leaf_no_children(local_name, node, xpath)
      validate_required_attrs(local_name, node, xpath)
      validate_name_attr(local_name, node, xpath)
      validate_ncname_strict(node, xpath)
      validate_datatype_library(node, xpath)
      validate_href(node, xpath)
      validate_single_except(local_name, node, xpath)
      validate_container_children(local_name, node, xpath)
      validate_name_class_and_pattern(local_name, node, xpath)
      validate_content_model(node, xpath, parent_context)
      validate_context(local_name, node, xpath)
      validate_name_value_purity(local_name, node, xpath)
      validate_xmlns_restrictions(local_name, node, xpath)
      validate_name_class_except(local_name, node, xpath)
      validate_name_conflict(local_name, node, xpath)
      validate_group_content(local_name, node, xpath)
      validate_leaf_no_attrs(local_name, node, xpath)
      validate_unknown_attrs(node, xpath)
      validate_single_attribute_pattern(local_name, node, xpath)
      validate_no_duplicate_attribute_names(local_name, node, xpath)

      # ---- New rules for spectest coverage ----
      validate_except_not_empty(local_name, node, xpath)
      validate_xmlns_in_name_class(local_name, node, xpath)
      validate_xmlns_in_anyname_attribute(local_name, node, xpath)
      validate_xmlns_in_anyname_attribute(local_name, node, xpath)
      validate_name_not_empty(local_name, node, xpath)
      validate_grammar_structure(local_name, node, xpath)
      validate_define_combine(local_name, node, xpath)
      validate_combine_consistency(local_name, node, xpath)
      validate_attribute_name_class_overlap(local_name, node, xpath)
      validate_nsname_except_rules(local_name, node, xpath)
      validate_param_for_builtin_types(local_name, node, xpath)
      validate_data_except_strict(node, xpath)
      validate_attribute_choice_content(local_name, node, xpath)
      validate_interleave_attribute_overlap(local_name, node, xpath)
      validate_interleave_name_class_overlap(local_name, node, xpath)
      validate_list_content_strict(local_name, node, xpath)
      validate_element_attribute_overlap(local_name, node, xpath)
      validate_grammar_root_element(local_name, node, xpath)
      validate_grammar_must_have_start(local_name, node, xpath)
      validate_grammar_nesting(local_name, node, xpath)
      validate_ref_resolution(local_name, node, xpath)
      validate_recursive_ref(local_name, node, xpath)
      validate_xmlns_in_name_class_choice(local_name, node, xpath)
      validate_builtin_type(local_name, node, xpath)
      validate_datatype_library_empty(local_name, node, xpath)
      validate_start_content(local_name, node, xpath)
      validate_start_element_conflicts(local_name, node, xpath)
      validate_group_text_data(local_name, node, xpath)
      validate_data_except_content_types(local_name, node, xpath)
      validate_infinite_attribute_name_class(local_name, node, xpath)
      validate_oneOrMore_attribute_overlap(local_name, node, xpath)
      validate_oneOrMore_infinite_attribute_name(local_name, node, xpath)

      # Recurse
      node.element_children.each do |child|
        next if child.namespace&.href == ANNOTATIONS_NS

        validate_node(child, parent_context: context_for_child(local_name, node))
      end
    end

    def report_error(message, xpath: nil, node: nil)
      line = node&.line if node
      error = SchemaValidationError.new(message, xpath: xpath, line: line)
      raise error unless @collect_all

      @errors << error
      nil
    end

    private

    def rng_ns_children(node)
      node.element_children.select { |c| (c.namespace&.href == RNG_NS) || (c.namespace.nil? && !c.name.empty?) }
    end

    def context_for_child(parent_name, _parent_node)
      case parent_name
      when 'start', 'grammar', 'div', 'include' then :grammar
      when 'element', 'attribute' then :content
      when 'data', 'list', 'value' then :data
      end
    end

    # ---- Helper methods ----
    def find_ancestor(node, name)
      current = node.parent
      while current
        return current if current.name == name &&
                          (current.namespace&.href == RNG_NS || (current.namespace.nil? && !current.name.empty?))

        current = current.parent
      end
      nil
    end

    def collect_defines_in_grammar(grammar)
      names = []
      rng_ns_children(grammar).each do |child|
        case child.name
        when 'define'
          n = child['name']
          names << n if n && !n.strip.empty?
        when 'div'
          names.concat(collect_defines_in_grammar(child))
        when 'include'
          rng_ns_children(child).each do |inc_child|
            if inc_child.name == 'define'
              n = inc_child['name']
              names << n if n && !n.strip.empty?
            end
          end
        end
      end
      names
    end

    def collect_element_names_non_choice(nodes)
      names = []
      nodes.each do |node|
        case node.name
        when 'element'
          names << node['name'] if node['name']
        when 'choice'
          # Don't recurse - duplicates across branches OK
        when 'group', 'interleave', 'optional', 'zeroOrMore', 'oneOrMore', 'mixed'
          names.concat(collect_element_names_non_choice(rng_ns_children(node)))
        end
      end
      names
    end

    def collect_element_names_from_children(nodes)
      names = []
      nodes.each do |node|
        case node.name
        when 'element'
          names << node['name'] if node['name']
        when 'choice', 'group', 'interleave', 'optional', 'zeroOrMore', 'oneOrMore', 'mixed'
          names.concat(collect_element_names_from_children(rng_ns_children(node)))
        end
      end
      names
    end

    def collect_attribute_names_non_choice(nodes)
      names = []
      nodes.each do |node|
        case node.name
        when 'attribute'
          names << node['name'] if node['name']
        when 'choice'
          # Don't recurse - duplicates across branches OK
        when 'group', 'interleave', 'optional', 'zeroOrMore', 'oneOrMore', 'mixed'
          names.concat(collect_attribute_names_non_choice(rng_ns_children(node)))
        end
      end
      names
    end

    def get_attribute_name_class(attr_node)
      name = attr_node['name']
      return { type: :name, name: name, ns: attr_node['ns'] || '' } if name

      rng_ns_children(attr_node).each do |child|
        case child.name
        when 'name'
          return { type: :name, name: child.text.strip, ns: child['ns'] || '' }
        when 'anyName'
          return { type: :anyName, except: get_name_class_except(child) }
        when 'nsName'
          return { type: :nsName, ns: child['ns'] || '', except: get_name_class_except(child) }
        end
      end
      nil
    end

    def get_element_name_class(element_node)
      name = element_node['name']
      return { type: :name, name: name, ns: element_node['ns'] || '' } if name

      rng_ns_children(element_node).each do |child|
        case child.name
        when 'name'
          return { type: :name, name: child.text.strip, ns: child['ns'] || '' }
        when 'anyName'
          return { type: :anyName, except: get_name_class_except(child) }
        when 'nsName'
          return { type: :nsName, ns: child['ns'] || '', except: get_name_class_except(child) }
        end
      end
      nil
    end

    def get_name_class_except(node)
      rng_ns_children(node).find { |c| c.name == 'except' }
    end

    def collect_attribute_name_classes(nodes)
      result = []
      nodes.each do |node|
        case node.name
        when 'attribute'
          nc = get_attribute_name_class(node)
          result << nc if nc
        when 'group', 'choice', 'interleave', 'optional', 'zeroOrMore', 'oneOrMore', 'mixed'
          result.concat(collect_attribute_name_classes(rng_ns_children(node)))
        end
      end
      result
    end

    def name_classes_overlap?(nc1, nc2)
      return nc1[:name] == nc2[:name] && nc1[:ns] == nc2[:ns] if nc1[:type] == :name && nc2[:type] == :name
      return true if nc1[:type] == :anyName && nc2[:type] == :anyName
      return anyName_overlaps_with?(nc1, nc2) if nc1[:type] == :anyName
      return anyName_overlaps_with?(nc2, nc1) if nc2[:type] == :anyName
      return nc1[:ns] == nc2[:ns] if nc1[:type] == :nsName && nc2[:type] == :nsName
      return nc1[:ns] == nc2[:ns] if nc1[:type] == :nsName && nc2[:type] == :name
      return nc1[:ns] == nc2[:ns] if nc2[:type] == :nsName && nc1[:type] == :name

      false
    end

    def anyName_overlaps_with?(anyName_nc, other_nc)
      exc = anyName_nc[:except]
      return true unless exc

      case other_nc[:type]
      when :name
        !name_in_except?(other_nc[:name], other_nc[:ns], exc)
      when :nsName
        !nsName_fully_in_except?(other_nc[:ns], exc)
      when :anyName
        true
      else
        true
      end
    end

    def name_in_except?(name, ns, except_node)
      rng_ns_children(except_node).any? do |child|
        case child.name
        when 'name'
          child_ns = child['ns'] || ''
          child.text.strip == name && child_ns == ns
        when 'anyName'
          true
        when 'nsName'
          (child['ns'] || '') == ns
        when 'choice'
          rng_ns_children(child).any? { |gc| name_in_except?(name, ns, gc) }
        else
          false
        end
      end
    end

    def nsName_fully_in_except?(ns, except_node)
      rng_ns_children(except_node).any? do |child|
        case child.name
        when 'anyName' then true
        when 'nsName' then child['ns'] == ns
        else false
        end
      end
    end

    def element_name_classes_overlap?(nc1, nc2)
      name_classes_overlap?(nc1, nc2)
    end

    def contains_element_pattern?(node)
      rng_ns_children(node).any? do |c|
        case c.name
        when 'element', 'ref' then true
        when 'group', 'choice', 'interleave', 'optional', 'zeroOrMore', 'oneOrMore', 'mixed'
          contains_element_pattern?(c)
        else false
        end
      end
    end

    # ---- Existing validation rules ----
    def report_obsolete_element(local_name, xpath)
      return unless OBSOLETE_ELEMENTS.include?(local_name)

      report_error("Element '#{local_name}' is obsolete and not supported", xpath: xpath)
    end

    def report_invalid_root(local_name, node, xpath)
      return unless node.parent&.document&.root == node
      return if VALID_ROOT_ELEMENTS.include?(local_name)

      report_error("Invalid root element '#{local_name}'", xpath: xpath)
    end

    def validate_obsolete_attrs(node, xpath)
      node.attributes.each do |name, attr|
        attr_ns = attr.namespace&.href
        if attr_ns == RNG_NS && OBSOLETE_ATTRS.include?(name)
          report_error("Attribute '#{name}' on '#{node.name}' is obsolete",
                       xpath: xpath)
        end
        next unless attr_ns.nil? && attr.namespace&.prefix.nil?

        report_error("Attribute 'name' on 'start' is obsolete", xpath: xpath) if name == 'name' && node.name == 'start'
        if name == 'global' && node.name == 'attribute'
          report_error("Attribute 'global' on 'attribute' is obsolete",
                       xpath: xpath)
        end
        report_error("Attribute '#{name}' on 'data' is obsolete", xpath: xpath) if %w[key
                                                                                      keyRef].include?(name) && node.name == 'data'
      end
    end

    def validate_leaf_no_children(local_name, node, xpath)
      return unless LEAF_ELEMENTS.include?(local_name)

      rng_kids = rng_ns_children(node)
      return if rng_kids.empty?

      report_error("'#{local_name}' must not have child elements", xpath: xpath)
    end

    def validate_required_attrs(local_name, node, xpath)
      case local_name
      when 'define'
        report_error("'define' must have a 'name' attribute", xpath: xpath) unless node['name']
      when 'ref', 'parentRef'
        report_error("'#{local_name}' must have a 'name' attribute", xpath: xpath) unless node['name']
      when 'data'
        report_error("'data' must have a 'type' attribute", xpath: xpath) unless node['type']
      when 'externalRef', 'include'
        report_error("'#{local_name}' must have an 'href' attribute", xpath: xpath) unless node['href']
      when 'param'
        report_error("'param' must have a 'name' attribute", xpath: xpath) unless node['name']
      end
    end

    def validate_name_attr(local_name, node, xpath)
      name = node['name']
      return unless name

      case local_name
      when 'ref', 'parentRef', 'define'
        # ref, parentRef, and define names must be NCNames (no colons)
        validate_ncname(name, local_name, xpath)
      when 'element', 'attribute'
        # element and attribute names can be QNames (may contain colons)
        # Only validate NCName restrictions for the local part if needed
        validate_qname(name, local_name, xpath, node)
      end
    end

    def validate_ncname(value, context, xpath)
      return if value.nil? || value.empty?

      report_error("'#{context}' name '#{value}' must be an NCName (no colon)", xpath: xpath) if value.include?(':')
      return if valid_ncname_string?(value)

      report_error("'#{context}' name '#{value}' is not a valid NCName", xpath: xpath)
    end

    def validate_qname(value, context, xpath, node)
      return if value.nil? || value.empty?

      # QName may contain a colon, but both prefix and local part must be valid NCNames
      return unless value.include?(':')

      prefix, local = value.split(':', 2)
      if prefix && !prefix.empty? && !valid_ncname_string?(prefix)
        report_error("'#{context}' QName prefix '#{prefix}' must be an NCName",
                     xpath: xpath)
      end
      # Local part must exist and not be empty if colon is present
      if local.nil? || local.empty?
        report_error("'#{context}' QName '#{value}' must not have an empty local part", xpath: xpath)
      elsif !valid_ncname_string?(local)
        report_error("'#{context}' QName local part '#{local}' must be an NCName", xpath: xpath)
      end
      # Check that the prefix is declared (if present)
      return unless prefix && !prefix.empty? && !prefix_declared?(prefix, node)

      report_error("'#{context}' QName prefix '#{prefix}' is not declared", xpath: xpath)
    end

    def prefix_declared?(prefix, node)
      return false unless node

      current = node
      while current.is_a?(Nokogiri::XML::Element)
        current.namespace_definitions.each do |ns|
          return true if ns.prefix == prefix
        end
        current = current.parent
      end
      false
    end

    def valid_ncname_string?(value)
      return false if value.nil? || value.empty?

      cp = value.codepoints.first
      return false unless cp
      return false unless valid_name_start_char?(cp)

      # Check remaining characters are valid NameChars
      value.codepoints.drop(1).each do |c|
        return false unless valid_name_char?(c)
      end
      true
    end

    def validate_ncname_strict(node, xpath)
      # Only check name elements that are name classes (not <name> used for defines)
      return unless node.name == 'name'

      parent = node.parent
      # <name> as child of element/attribute is a name class - check NCName
      return unless parent && %w[element attribute].include?(parent.name)

      name_text = node.text.strip
      return if name_text.empty?

      # Check first character is a valid NameStartChar
      cp = name_text.codepoints.first
      return unless cp

      return if valid_name_start_char?(cp)

      report_error("Name '#{name_text}' is not a valid NCName: invalid start character", xpath: xpath)
    end

    def valid_name_start_char?(cp)
      cp.between?(0x41, 0x5A) || # A-Z
        cp.between?(0x61, 0x7A) || # a-z
        cp == 0x5F || # _
        cp.between?(0xC0, 0xD6) ||
        cp.between?(0xD8, 0xF6) ||
        cp.between?(0xF8, 0x2FF) ||
        cp.between?(0x370, 0x37D) ||
        cp.between?(0x37F, 0x1FFF) ||
        cp.between?(0x200C, 0x200D) ||
        cp.between?(0x2070, 0x218F) ||
        cp.between?(0x2C00, 0x2FEF) ||
        cp.between?(0x3001, 0xD7FF) ||
        cp.between?(0xF900, 0xFDCF) ||
        cp.between?(0xFDF0, 0xFFFD) ||
        cp.between?(0x10000, 0xEFFFF)
    end

    def valid_name_char?(cp)
      valid_name_start_char?(cp) ||
        cp.between?(0x30, 0x39) || # 0-9
        cp == 0x2D ||                    # -
        cp == 0x2E ||                    # .
        cp == 0xB7                       # middle dot
    end

    def validate_datatype_library(node, xpath)
      dtl = node['datatypeLibrary']
      return unless dtl && !dtl.empty?

      begin
        uri = URI.parse(dtl)
        report_error("datatypeLibrary '#{dtl}' must have a scheme", xpath: xpath) unless uri.scheme
        # Must have scheme-specific part after the colon
        # e.g., "foo:" has no scheme-specific part and is invalid
        after_scheme = dtl[(uri.scheme.length + 1)..]
        if !after_scheme || after_scheme.empty?
          report_error("datatypeLibrary '#{dtl}' must have a non-empty scheme-specific part",
                       xpath: xpath)
        end
        if uri.fragment || uri.query
          report_error("datatypeLibrary '#{dtl}' must not have fragment or query",
                       xpath: xpath)
        end
      rescue URI::InvalidURIError
        report_error("datatypeLibrary '#{dtl}' is not a valid URI", xpath: xpath)
      end
    end

    def validate_href(node, xpath)
      href = node['href']
      return unless href && node.name == 'externalRef'

      return unless href.include?('#')

      report_error("externalRef href '#{href}' must not contain a fragment identifier", xpath: xpath)
    end

    def validate_single_except(local_name, node, xpath)
      return unless %w[anyName nsName data].include?(local_name)

      count = rng_ns_children(node).count { |c| c.name == 'except' }
      report_error("'#{local_name}' must not have multiple 'except' children", xpath: xpath) if count > 1
    end

    def validate_container_children(local_name, node, xpath)
      return unless CONTAINER_ELEMENTS.include?(local_name)

      kids = rng_ns_children(node)
      report_error("'#{local_name}' must have at least one child pattern", xpath: xpath) if kids.empty?
      # start can only have one child
      return unless local_name == 'start' && kids.length > 1

      report_error("'start' must have exactly one child pattern", xpath: xpath)
    end

    def validate_name_class_and_pattern(local_name, node, xpath)
      return unless %w[element attribute].include?(local_name)

      kids = rng_ns_children(node)
      has_name_class = kids.any? { |c| %w[name anyName nsName].include?(c.name) }
      has_name_class ||= kids.any? { |c| c.name == 'choice' && choice_contains_name_class?(c) }
      has_name_class = true if node['name']
      has_name_class = true if kids.any? { |c| c.name == 'ref' }
      has_pattern = kids.any? { |c| !%w[name anyName nsName].include?(c.name) }

      # For elements: RELAX NG requires both name class AND pattern
      # For attributes: requires name class, but no pattern needed if only name attr
      report_error("'#{local_name}' must have a name class", xpath: xpath) unless has_name_class
      return unless local_name == 'element'
      return if has_pattern

      report_error("'#{local_name}' must have a pattern", xpath: xpath)
    end

    def choice_contains_name_class?(choice_node)
      return false unless choice_node.name == 'choice'

      rng_ns_children(choice_node).any? do |c|
        case c.name
        when 'name', 'anyName', 'nsName' then true
        when 'choice' then choice_contains_name_class?(c)
        else false
        end
      end
    end

    def validate_content_model(node, xpath, _parent_context)
      case node.name
      when 'attribute'
        validate_attribute_content(node, xpath)
      when 'list'
        validate_list_content(node, xpath)
      when 'except'
        validate_data_except_content(node, xpath) if node.parent&.name == 'data'
      when 'interleave'
        validate_interleave_content(node, xpath)
      when 'mixed'
        validate_mixed_content(node, xpath)
      end
    end

    def validate_attribute_content(node, xpath)
      rng_ns_children(node).each do |child|
        if ATTR_DISALLOWED.include?(child.name)
          report_error("'attribute' content must not contain '#{child.name}' pattern",
                       xpath: xpath)
        end
      end
    end

    def validate_list_content(node, xpath)
      rng_ns_children(node).each do |child|
        if LIST_DISALLOWED.include?(child.name)
          report_error("'list' content must not contain '#{child.name}'",
                       xpath: xpath)
        end
      end
    end

    def validate_data_except_content(node, xpath)
      rng_ns_children(node).each do |child|
        if DATA_EXCEPT_DISALLOWED.include?(child.name)
          report_error("'data/except' content must not contain '#{child.name}'",
                       xpath: xpath)
        end
      end
    end

    def validate_interleave_content(node, xpath)
      kids = rng_ns_children(node)
      report_error("'interleave' must not contain multiple 'text' patterns", xpath: xpath) if kids.count do |c|
        c.name == 'text'
      end > 1
      names = collect_element_names_non_choice(kids)
      dups = names.tally.select { |_, v| v > 1 }.keys
      return if dups.empty?

      report_error("'interleave' must not contain overlapping element names: #{dups.join(', ')}",
                   xpath: xpath)
    end

    def validate_mixed_content(node, xpath)
      return unless rng_ns_children(node).any? { |c| c.name == 'mixed' }

      report_error("'mixed' must not contain nested 'mixed'", xpath: xpath)
    end

    def validate_context(local_name, node, xpath)
      parent_local = node.parent&.name
      case local_name
      when 'define'
        report_error("'define' is not allowed inside '#{parent_local}'", xpath: xpath) unless %w[grammar div
                                                                                                 include].include?(parent_local)
      when 'start'
        report_error("'start' is not allowed inside '#{parent_local}'", xpath: xpath) unless %w[grammar
                                                                                                div].include?(parent_local)
      when 'include'
        report_error("'include' is not allowed inside '#{parent_local}'", xpath: xpath) unless %w[grammar
                                                                                                  div].include?(parent_local)
      end
    end

    def validate_name_value_purity(local_name, node, xpath)
      return unless %w[name value].include?(local_name)

      return unless node.element_children.any?

      report_error("'#{local_name}' must not contain child elements", xpath: xpath)
    end

    def validate_xmlns_restrictions(local_name, node, xpath)
      return unless local_name == 'attribute'

      name = node['name']
      report_error("Attribute name 'xmlns' is not allowed", xpath: xpath) if name && name.strip == 'xmlns'
      ns = node['ns']
      return unless ['http://www.w3.org/2000/xmlns', 'http://www.w3.org/2000/xmlns/'].include?(ns)

      report_error('Attribute with xmlns namespace is not allowed', xpath: xpath)
    end

    def validate_name_class_except(local_name, node, xpath)
      return unless local_name == 'except'

      parent = node.parent
      return unless %w[anyName nsName].include?(parent&.name)

      check_name_class_except_children(parent, rng_ns_children(node), xpath)
    end

    def check_name_class_except_children(parent, children, xpath)
      children.each do |child|
        targets = child.name == 'choice' ? rng_ns_children(child) : [child]
        targets.each do |target|
          if parent.name == 'anyName' && target.name == 'anyName'
            report_error("'anyName/except' must not contain 'anyName'",
                         xpath: xpath)
          end
          if parent.name == 'nsName' && target.name == 'nsName'
            parent_ns = parent['ns'] || ''
            child_ns = target['ns'] || ''
            if parent_ns == child_ns
              report_error("'nsName/except' must not contain 'nsName' with same namespace",
                           xpath: xpath)
            end
          end
          if parent.name == 'nsName' && target.name == 'anyName'
            report_error("'nsName/except' containing 'anyName' results in empty name class",
                         xpath: xpath)
          end
        end
      end
    end

    def validate_name_conflict(local_name, node, xpath)
      return unless %w[element attribute].include?(local_name)

      return unless node['name'] && rng_ns_children(node).any? { |c| c.name == 'name' }

      report_error("'#{local_name}' cannot have both a name attribute and a name child", xpath: xpath)
    end

    def validate_group_content(local_name, node, xpath)
      return unless local_name == 'group'

      rng_ns_children(node).each do |child|
        report_error("'group' must not contain a name class '#{child.name}'", xpath: xpath) if %w[name anyName
                                                                                                  nsName].include?(child.name)
      end
    end

    def validate_leaf_no_attrs(local_name, node, xpath)
      return unless NO_ATTR_LEAF_ELEMENTS.include?(local_name)

      node.attributes.each do |attr_name, attr|
        attr_ns = attr.namespace&.href
        next if attr_ns && attr_ns != RNG_NS
        next if attr_name == 'xmlns' || attr_name.start_with?('xmlns:')

        report_error("'#{local_name}' must not have attributes", xpath: xpath)
        return
      end
    end

    def validate_unknown_attrs(node, xpath)
      node.attributes.each do |attr_name, attr|
        next if attr_name == 'xmlns'

        attr_ns = attr.namespace&.href
        if (attr_ns == RNG_NS) && !known_rng_attr?(
          node.name, attr_name
        )
          report_error("Unknown attribute '#{attr_name}' on '#{node.name}'",
                       xpath: xpath)
        end
        next unless attr_ns.nil? && attr.namespace&.prefix.nil? && !known_unprefixed_attr?(
          node.name, attr_name
        )

        report_error("Unknown attribute '#{attr_name}' on '#{node.name}'",
                     xpath: xpath)
      end
    end

    def known_rng_attr?(element_name, attr_name)
      KNOWN_ATTRS.fetch(element_name, []).include?(attr_name) || GENERIC_ATTRS.include?(attr_name)
    end

    def known_unprefixed_attr?(element_name, attr_name)
      KNOWN_ATTRS.fetch(element_name, []).include?(attr_name) || VALID_UNPREFIXED_ATTRS.include?(attr_name)
    end

    def validate_single_attribute_pattern(local_name, node, xpath)
      return unless local_name == 'attribute'

      kids = rng_ns_children(node)
      # Name class elements that don't count as patterns
      name_class_exclusions = %w[name anyName nsName choice]
      pattern_count = kids.count { |c| !name_class_exclusions.include?(c.name) }
      report_error("'attribute' must not have multiple patterns", xpath: xpath) if pattern_count > 1
    end

    def validate_no_duplicate_attribute_names(local_name, node, xpath)
      return unless local_name == 'element'

      check_duplicate_attrs_in_children(rng_ns_children(node), xpath)
    end

    def check_duplicate_attrs_in_children(nodes, xpath)
      attr_names = []
      nodes.each do |n|
        case n.name
        when 'attribute'
          attr_names << n['name'] if n['name']
        when 'choice'
          # Don't recurse - duplicates across branches OK
        when 'group', 'interleave', 'optional', 'zeroOrMore', 'oneOrMore', 'mixed'
          check_duplicate_attrs_in_children(rng_ns_children(n), xpath)
        end
      end
      dups = attr_names.tally.select { |_, v| v > 1 }.keys
      return if dups.empty?

      report_error("'element' must not have duplicate attribute names: #{dups.join(', ')}",
                   xpath: xpath)
    end

    # ---- New validation rules for spectest coverage ----
    def validate_except_not_empty(local_name, node, xpath)
      return unless local_name == 'except'
      return unless rng_ns_children(node).empty?

      parent = node.parent
      return unless %w[anyName nsName data].include?(parent&.name)

      report_error("'#{parent.name}/except' must not be empty", xpath: xpath)
    end

    def validate_xmlns_in_name_class(local_name, node, xpath)
      return unless local_name == 'name'

      parent = node.parent
      return unless parent&.name == 'attribute'

      return unless node.text.strip == 'xmlns'

      ns = node['ns']
      return unless ns.nil? || ns == ''

      report_error("Attribute name 'xmlns' is not allowed", xpath: xpath)
    end

    def validate_xmlns_in_anyname_attribute(local_name, node, xpath)
      return unless local_name == 'anyName'

      # Walk up to find if we're inside an attribute
      p = node.parent
      return unless p && %w[choice attribute].include?(p.name)

      if p.name == 'choice'
        p = p.parent
        return unless p && p.name == 'attribute'
      end
      # anyName in attribute context must have except covering xmlns
      except_node = rng_ns_children(node).find { |c| c.name == 'except' }
      return unless except_node

      return if except_covers_xmlns?(except_node)

      report_error("'anyName' in attribute does not exclude xmlns namespace names", xpath: xpath)
    end

    # Check if except clause fully covers all xmlns-related names.
    # RELAX NG 4.16: attribute name class must not match:
    #   - xmlns (bare name in empty namespace)
    #   - any name in http://www.w3.org/2000/xmlns/ namespace (xmlns:*)
    # An except must exclude BOTH to be sufficient.
    def except_covers_xmlns?(except_node)
      covers_bare_xmlns = false
      covers_xmlns_ns = false
      rng_ns_children(except_node).each do |child|
        case child.name
        when 'anyName'
          # anyName in except excludes everything
          covers_bare_xmlns = true
          covers_xmlns_ns = true
        when 'nsName'
          ns = child['ns'] || ''
          covers_xmlns_ns = true if ns == 'http://www.w3.org/2000/xmlns/'
        when 'name'
          covers_bare_xmlns = true if child.text.strip == 'xmlns' && (child['ns'].nil? || child['ns'] == '')
        when 'choice'
          # For choice in except, if ANY alternative excludes a name, it IS excluded
          rng_ns_children(child).each do |gc|
            case gc.name
            when 'anyName'
              covers_bare_xmlns = true
              covers_xmlns_ns = true
            when 'nsName'
              covers_xmlns_ns = true if (gc['ns'] || '') == 'http://www.w3.org/2000/xmlns/'
            when 'name'
              covers_bare_xmlns = true if gc.text.strip == 'xmlns' && (gc['ns'].nil? || gc['ns'] == '')
            end
          end
        end
      end
      covers_bare_xmlns && covers_xmlns_ns
    end

    def validate_name_not_empty(local_name, node, xpath)
      return unless %w[element attribute ref parentRef define].include?(local_name)

      name = node['name']
      return unless name

      return unless name.strip.empty?

      report_error("'#{local_name}' name attribute must not be empty", xpath: xpath)
    end

    def validate_grammar_structure(local_name, node, xpath)
      return unless local_name == 'grammar'
      return unless node.parent&.document&.root == node

      kids = rng_ns_children(node)
      has_start = kids.any? { |c| c.name == 'start' }
      has_include = kids.any? { |c| c.name == 'include' }
      has_define = kids.any? { |c| c.name == 'define' }
      # A grammar must have start, include, or be non-empty with valid children
      return if has_start || has_include || has_define || kids.empty?

      report_error("'grammar' must have a 'start', 'include', or 'define' child", xpath: xpath)
    end

    def validate_define_combine(local_name, node, xpath)
      return unless local_name == 'grammar'

      defines = rng_ns_children(node).select { |c| c.name == 'define' }
      defines.group_by { |d| d['name'] }.each do |name, group|
        next unless group.length > 1

        without_combine = group.count { |d| d['combine'].nil? || d['combine'].strip.empty? }
        if without_combine > 1
          report_error("Multiple 'define' elements with name '#{name}' without 'combine' attribute",
                       xpath: xpath)
        end
      end
    end

    def validate_combine_consistency(local_name, node, xpath)
      return unless local_name == 'grammar'

      defines = rng_ns_children(node).select { |c| c.name == 'define' }
      defines.group_by { |d| d['name'] }.each do |name, group|
        next unless group.length > 1

        vals = group.filter_map { |d| d['combine'] }.map(&:strip).reject(&:empty?).uniq
        if vals.length > 1
          report_error("Inconsistent 'combine' values for define '#{name}': #{vals.join(', ')}",
                       xpath: xpath)
        end
      end
    end

    def validate_attribute_name_class_overlap(local_name, node, xpath)
      return unless local_name == 'element'

      ncs = collect_attribute_name_classes(rng_ns_children(node))
      ncs.each_with_index do |nc1, i|
        ncs.each_with_index do |nc2, j|
          next if j <= i

          if name_classes_overlap?(nc1, nc2)
            report_error("'element' contains overlapping attribute name classes", xpath: xpath)
            return
          end
        end
      end
    end

    def validate_nsname_except_rules(local_name, node, xpath)
      return unless local_name == 'except'

      parent = node.parent
      return unless %w[anyName nsName].include?(parent&.name)

      rng_ns_children(node).each do |child|
        targets = child.name == 'choice' ? rng_ns_children(child) : [child]
        targets.each do |target|
          if parent.name == 'nsName' && target.name == 'nsName' && ((parent['ns'] || '') == (target['ns'] || ''))
            report_error("'nsName/except' must not contain 'nsName' with the same namespace",
                         xpath: xpath)
          end
          if parent.name == 'nsName' && target.name == 'anyName'
            report_error("'nsName/except' containing 'anyName' results in empty name class",
                         xpath: xpath)
          end
        end
      end
    end

    def validate_param_for_builtin_types(local_name, node, xpath)
      return unless local_name == 'data'

      params = rng_ns_children(node).select { |c| c.name == 'param' }
      return if params.empty?

      dtl = node['datatypeLibrary']
      type = node['type']
      return unless (dtl.nil? || dtl.empty?) && %w[string token].include?(type)

      report_error("Built-in type '#{type}' does not support 'param' children", xpath: xpath)
    end

    def validate_data_except_strict(node, xpath)
      return unless node.name == 'except'
      return unless node.parent&.name == 'data'

      rng_ns_children(node).each do |child|
        report_error("'data/except' content must not contain 'oneOrMore'", xpath: xpath) if child.name == 'oneOrMore'
      end
    end

    def validate_attribute_choice_content(local_name, node, xpath)
      return unless local_name == 'attribute'

      rng_ns_children(node).each do |child|
        next unless child.name == 'choice'

        rng_ns_children(child).each do |gc|
          if gc.name == 'element'
            report_error("'attribute/choice' content must not contain 'element'", xpath: xpath)
          elsif gc.name == 'attribute'
            report_error("'attribute/choice' content must not contain 'attribute'", xpath: xpath)
          end
        end
      end
    end

    def validate_interleave_attribute_overlap(local_name, node, xpath)
      return unless local_name == 'interleave'

      attr_names = rng_ns_children(node).select { |c| c.name == 'attribute' }.filter_map { |a| a['name'] }
      dups = attr_names.tally.select { |_, v| v > 1 }.keys
      return if dups.empty?

      report_error("'interleave' must not contain overlapping attribute names: #{dups.join(', ')}",
                   xpath: xpath)
    end

    def validate_interleave_name_class_overlap(local_name, node, xpath)
      return unless local_name == 'interleave'

      ncs = rng_ns_children(node).select { |c| c.name == 'element' }.filter_map { |e| get_element_name_class(e) }
      ncs.each_with_index do |nc1, i|
        ncs.each_with_index do |nc2, j|
          next if j <= i

          if element_name_classes_overlap?(nc1, nc2)
            report_error("'interleave' must not contain overlapping element name classes", xpath: xpath)
            return
          end
        end
      end
    end

    def validate_list_content_strict(local_name, node, xpath)
      return unless local_name == 'list'

      rng_ns_children(node).each do |child|
        case child.name
        when 'interleave'
          report_error("'list' content must not contain 'interleave'", xpath: xpath)
        when 'text'
          report_error("'list' content must not contain 'text'", xpath: xpath)
        when 'choice'
          rng_ns_children(child).each do |gc|
            case gc.name
            when 'list'
              report_error("'list/choice' content must not contain nested 'list'", xpath: xpath)
            when 'element'
              report_error("'list/choice' content must not contain 'element'", xpath: xpath)
            when 'attribute'
              report_error("'list/choice' content must not contain 'attribute'", xpath: xpath)
            when 'text'
              report_error("'list/choice' content must not contain 'text'", xpath: xpath)
            when 'interleave'
              report_error("'list/choice' content must not contain 'interleave'", xpath: xpath)
            end
          end
        end
      end
    end

    def validate_element_attribute_overlap(local_name, node, xpath)
      return unless local_name == 'element'

      rng_ns_children(node).each do |child|
        next unless %w[oneOrMore zeroOrMore].include?(child.name)

        rng_ns_children(child).each do |gc|
          next unless %w[group interleave].include?(gc.name)

          attrs = rng_ns_children(gc).select { |c| c.name == 'attribute' }
          next unless attrs.length > 1

          ncs = attrs.filter_map { |a| get_attribute_name_class(a) }
          ncs.each_with_index do |nc1, i|
            ncs.each_with_index do |nc2, j|
              next if j <= i

              if name_classes_overlap?(nc1, nc2)
                report_error("Repeating #{gc.name} contains overlapping attribute name classes", xpath: xpath)
                return
              end
            end
          end
        end
      end
    end

    def validate_grammar_root_element(local_name, node, xpath)
      return unless local_name == 'grammar'
      return unless node.parent&.document&.root == node

      kids = rng_ns_children(node)
      return unless kids.any? { |c| c.name == 'element' } && kids.any? { |c| c.name == 'start' }

      report_error("'grammar' must not have both 'element' and 'start' as direct children", xpath: xpath)
    end

    # Grammar must have a start element (unless it has include which provides one)
    def validate_grammar_must_have_start(local_name, node, xpath)
      return unless local_name == 'grammar'

      kids = rng_ns_children(node)
      has_start = kids.any? { |c| c.name == 'start' }
      has_include = kids.any? { |c| c.name == 'include' }
      # Grammar with no start and no include must have no children that need start
      # But grammar with only defines is invalid (no start reachable)
      return if has_start || has_include

      # Check if grammar has any children at all (define/div only = no start)
      non_div_kids = kids.reject { |c| c.name == 'div' }
      if non_div_kids.any? && !non_div_kids.all? { |c| c.name == 'define' }
        # Has children but no start — could be grammar inside define
        # Top-level grammar with defines but no start is invalid
        report_error("'grammar' must have a 'start' child", xpath: xpath) if node.parent&.document&.root == node
      elsif non_div_kids.empty?
        # Empty grammar at top level
        report_error("'grammar' must have a 'start' child", xpath: xpath) if node.parent&.document&.root == node
      elsif node.parent&.document&.root == node
        # Grammar with only defines (no start, no include)
        report_error("'grammar' must have a 'start' child", xpath: xpath)
      end
    end

    # Grammar nested inside define/choice/group must have a start
    def validate_grammar_nesting(local_name, node, xpath)
      return unless local_name == 'grammar'

      kids = rng_ns_children(node)
      has_start = kids.any? { |c| c.name == 'start' }
      has_include = kids.any? { |c| c.name == 'include' }
      kids.any? { |c| c.name == 'define' }
      # Any grammar (including nested) must have start or include
      return if has_start || has_include

      report_error("'grammar' must have a 'start' or 'include' child", xpath: xpath)
    end

    # Every ref/parentRef must resolve to a define
    def validate_ref_resolution(local_name, node, xpath)
      return unless local_name == 'grammar'
      return unless node.parent&.document&.root == node

      # Skip if grammar has includes — refs may come from included files
      kids = rng_ns_children(node)
      return if kids.any? { |c| c.name == 'include' }

      # Collect all defines in this grammar (including nested grammars and divs)
      all_defines = collect_all_defines(node)
      # Collect all refs/parentRefs
      all_refs = collect_all_refs(node)
      # Check each ref has a matching define
      all_refs.each do |ref|
        name = ref[:name]
        unless all_defines.include?(name)
          report_error("'#{ref[:type]}' name '#{name}' has no matching 'define'",
                       xpath: xpath)
        end
      end
    end

    # Detect recursive refs (self-referencing defines)
    def validate_recursive_ref(local_name, node, xpath)
      return unless local_name == 'grammar'
      return unless node.parent&.document&.root == node

      # Collect all defines and their ref dependencies
      defines = collect_define_dependencies(node)
      # Check for cycles using DFS
      defines.each_key do |name|
        report_error("'define' name '#{name}' is recursive", xpath: xpath) if has_cycle?(name, defines, [])
      end
    end

    # xmlns in attribute name class choice
    def validate_xmlns_in_name_class_choice(local_name, node, xpath)
      return unless local_name == 'attribute'

      # Check all name class children recursively for xmlns
      check_name_class_for_xmlns(node, xpath)
    end

    # Built-in type validation (type must be valid)
    def validate_builtin_type(local_name, node, xpath)
      return unless %w[data value].include?(local_name)

      type = node['type']
      return unless type

      dtl = node['datatypeLibrary']
      # If no datatypeLibrary or empty, only built-in types allowed
      return unless dtl.nil? || dtl.empty?
      return if %w[string token].include?(type)

      report_error("Unknown built-in type '#{type}'; only 'string' and 'token' are built-in types", xpath: xpath)
    end

    # datatypeLibrary="" with non-built-in type
    def validate_datatype_library_empty(local_name, node, xpath)
      return unless %w[data value].include?(local_name)

      dtl = node['datatypeLibrary']
      type = node['type']
      return unless dtl == ''
      return unless type && !%w[string token].include?(type)

      report_error("datatypeLibrary must not be empty for non-built-in type '#{type}'", xpath: xpath)
    end

    # Start element content restrictions
    # start must contain only element patterns (not attribute/data/text/value/list/empty)
    def validate_start_content(local_name, node, xpath)
      return unless local_name == 'start'

      kids = rng_ns_children(node)
      first = kids.first
      return unless first

      check_start_pattern(first, xpath)
    end

    # Element name conflicts in start (group with duplicate element names)
    def validate_start_element_conflicts(local_name, node, xpath)
      return unless local_name == 'start'

      kids = rng_ns_children(node)
      return if kids.empty?

      check_start_element_overlap(kids.first, xpath)
    end

    # Group must not have multiple text/data patterns
    def validate_group_text_data(local_name, node, xpath)
      return unless %w[group interleave].include?(local_name)

      kids = rng_ns_children(node)
      data_count = kids.count { |c| %w[data value].include?(c.name) }
      text_count = kids.count { |c| c.name == 'text' }
      return unless data_count + text_count > 1

      report_error("'#{local_name}' must not contain multiple data/value/text patterns", xpath: xpath)
    end

    # data/except must not contain empty
    def validate_data_except_content_types(local_name, node, xpath)
      return unless local_name == 'except'
      return unless node.parent&.name == 'data'

      rng_ns_children(node).each do |child|
        report_error("'data/except' must not contain 'empty'", xpath: xpath) if child.name == 'empty'
      end
    end

    # Attribute with infinite name class (anyName without except, or nsName ns="")
    def validate_infinite_attribute_name_class(local_name, node, xpath)
      return unless local_name == 'attribute'

      nc = get_attribute_name_class(node)
      if nc
        # anyName without except is infinite
        if nc[:type] == :anyName && !nc[:except]
          report_error("'attribute' with 'anyName' (no except) matches infinite names",
                       xpath: xpath)
        end
        # nsName with ns="" is equivalent to anyName
        if nc[:type] == :nsName && (nc[:ns] == '' || nc[:ns].nil?)
          report_error("'attribute' with 'nsName' ns='' matches all names",
                       xpath: xpath)
        end
      end
      # Check choice name classes (even when nc is nil, e.g. when name class is a choice)
      rng_ns_children(node).each do |child|
        next unless child.name == 'choice'

        check_choice_for_infinite_attr_name_class(child, xpath)
      end
    end

    def collect_all_defines(grammar_node)
      names = Set.new
      rng_ns_children(grammar_node).each do |child|
        case child.name
        when 'define'
          n = child['name']
          names << n if n && !n.strip.empty?
        when 'div'
          names.merge(collect_all_defines(child))
        when 'include'
          rng_ns_children(child).each do |inc_child|
            if inc_child.name == 'define'
              n = inc_child['name']
              names << n if n && !n.strip.empty?
            end
          end
        end
      end
      names
    end

    def collect_all_refs(node)
      refs = []
      return refs unless node.is_a?(Nokogiri::XML::Element)

      ns = node.namespace&.href
      local = node.name
      if ns == RNG_NS || (ns.nil? && !local.empty?)
        case local
        when 'ref'
          refs << { name: node['name'], type: 'ref' } if node['name']
        when 'parentRef'
          refs << { name: node['name'], type: 'parentRef' } if node['name']
        end
        node.element_children.each do |child|
          refs.concat(collect_all_refs(child))
        end
      end
      refs
    end

    def collect_define_dependencies(grammar_node)
      deps = {}
      rng_ns_children(grammar_node).each do |child|
        case child.name
        when 'define'
          name = child['name']
          next unless name

          refs = collect_direct_refs(child)
          deps[name] = refs
        when 'div'
          deps.merge!(collect_define_dependencies(child))
        end
      end
      deps
    end

    def collect_direct_refs(node)
      refs = []
      return refs unless node.is_a?(Nokogiri::XML::Element)

      ns = node.namespace&.href
      local = node.name
      if ns == RNG_NS || (ns.nil? && !local.empty?)
        case local
        when 'ref'
          refs << node['name'] if node['name']
        when 'parentRef'
          refs << node['name'] if node['name']
        end
        node.element_children.each do |child|
          next if child.name == 'define' # Don't recurse into nested grammar's defines

          refs.concat(collect_direct_refs(child))
        end
      end
      refs
    end

    def has_cycle?(name, deps, visited)
      return false unless deps.key?(name)
      return true if visited.include?(name)

      visited << name
      deps[name]&.each do |dep|
        return true if has_cycle?(dep, deps, visited)
      end
      visited.delete(name)
      false
    end

    def check_name_class_for_xmlns(node, xpath)
      rng_ns_children(node).each do |child|
        case child.name
        when 'name'
          if child.text.strip == 'xmlns'
            ns = child['ns'] || ''
            report_error("Attribute name class contains 'xmlns'", xpath: xpath) if ns == ''
          end
        when 'choice'
          rng_ns_children(child).each do |gc|
            case gc.name
            when 'name'
              if gc.text.strip == 'xmlns'
                ns = gc['ns'] || ''
                report_error("Attribute name class contains 'xmlns'", xpath: xpath) if ns == ''
              end
            end
          end
        when 'anyName'
          # anyName in attribute context - handled by infinite name class rule
        when 'nsName'
          # Check except
          exc = rng_ns_children(child).find { |c| c.name == 'except' }
          check_name_class_for_xmlns(exc, xpath) if exc
        end
      end
    end

    def check_start_pattern(pattern, xpath)
      case pattern.name
      when 'attribute'
        report_error("'start' must not contain 'attribute'", xpath: xpath)
      when 'data', 'value'
        report_error("'start' must not contain '#{pattern.name}'", xpath: xpath)
      when 'text'
        report_error("'start' must not contain 'text'", xpath: xpath)
      when 'list'
        report_error("'start' must not contain 'list'", xpath: xpath)
      when 'empty'
        report_error("'start' must not contain 'empty'", xpath: xpath)
      when 'group', 'choice', 'interleave', 'optional', 'zeroOrMore', 'oneOrMore', 'mixed'
        rng_ns_children(pattern).each { |c| check_start_pattern(c, xpath) }
      end
    end

    def check_start_element_overlap(pattern, xpath)
      case pattern.name
      when 'group'
        names = collect_element_names_non_choice(rng_ns_children(pattern))
        dups = names.tally.select { |_, v| v > 1 }.keys
        unless dups.empty?
          report_error("'start' group must not have overlapping element names: #{dups.join(', ')}",
                       xpath: xpath)
        end
      when 'choice'
        # Check each branch independently
        rng_ns_children(pattern).each { |c| check_start_element_overlap(c, xpath) }
      when 'oneOrMore'
        # oneOrMore of element means it can match multiple times
        rng_ns_children(pattern).each do |c|
          check_start_element_overlap(c, xpath)
          # oneOrMore itself creates a duplicate with sibling patterns
          report_error("'start' oneOrMore of element allows multiple matches", xpath: xpath) if c.name == 'element'
        end
      when 'group', 'interleave'
        check_start_element_overlap_group(pattern, rng_ns_children(pattern), xpath)
      end
    end

    def check_start_element_overlap_group(_parent, children, xpath)
      names = collect_element_names_non_choice(children)
      dups = names.tally.select { |_, v| v > 1 }.keys
      return if dups.empty?

      report_error("'start' must not have overlapping element names: #{dups.join(', ')}", xpath: xpath)
    end

    # oneOrMore/zeroOrMore containing group/interleave with multiple attributes
    def validate_oneOrMore_attribute_overlap(local_name, node, xpath)
      return unless %w[oneOrMore zeroOrMore].include?(local_name)

      rng_ns_children(node).each do |child|
        next unless %w[group interleave].include?(child.name)

        attrs = rng_ns_children(child).select { |c| c.name == 'attribute' }
        next unless attrs.length >= 2

        report_error("'#{local_name}' with '#{child.name}' containing multiple attributes creates name overlap",
                     xpath: xpath)
      end
    end

    # oneOrMore/zeroOrMore of attribute with infinite name class
    def validate_oneOrMore_infinite_attribute_name(local_name, node, xpath)
      return unless %w[oneOrMore zeroOrMore].include?(local_name)

      rng_ns_children(node).each do |child|
        next unless child.name == 'attribute'

        nc = get_attribute_name_class(child)
        next unless nc

        if (nc[:type] == :anyName) && !nc[:except]
          # anyName attribute in oneOrMore = infinite match
          # But if there's an except, it might be OK
          report_error("'#{local_name}' of 'attribute' with 'anyName' creates infinite attribute matches", xpath: xpath)
        end
        # Check for choice name classes too
        rng_ns_children(child).each do |gc|
          next unless gc.name == 'choice'

          check_choice_for_infinite_attr_in_repeat(gc, xpath)
        end
      end
    end

    def check_choice_for_infinite_attr_in_repeat(choice_node, xpath)
      rng_ns_children(choice_node).each do |gc|
        case gc.name
        when 'anyName'
          report_error("Repeating attribute with choice containing 'anyName' creates infinite matches", xpath: xpath)
        when 'nsName'
          ns = gc['ns'] || ''
          if ns == ''
            report_error("Repeating attribute with choice containing 'nsName' ns='' creates infinite matches",
                         xpath: xpath)
          end
        end
      end
    end

    def check_choice_for_infinite_attr_name_class(choice_node, xpath)
      rng_ns_children(choice_node).each do |gc|
        case gc.name
        when 'anyName'
          report_error("'attribute' choice contains 'anyName' (infinite name class)", xpath: xpath)
        when 'nsName'
          ns = gc['ns'] || ''
          report_error("'attribute' choice contains 'nsName' ns='' (infinite name class)", xpath: xpath) if ns == ''
        end
      end
    end
  end
end
