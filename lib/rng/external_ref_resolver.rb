# frozen_string_literal: true

module Rng
  # Resolves external href references in RNG schemas.
  #
  # This class handles two types of external references:
  # 1. `<include href="uri"/>` at grammar level - merges definitions from external grammar
  # 2. `<externalRef href="uri"/>` at pattern level - replaces ref with external pattern
  #
  # @example Parse with external resolution
  #   Rng.parse(rng_xml, location: "/path/to/schema.rng", resolve_external: true)
  #
  class ExternalRefResolver
    # Error raised when external reference resolution fails
    class ExternalRefResolutionError < Error
      attr_reader :href, :cause

      def initialize(message, href: nil, cause: nil)
        super(message)
        @href = href
        @cause = cause
      end
    end

    # Initialize the resolver
    #
    # @param grammar [Grammar] The grammar to resolve external refs in
    # @param location [String, nil] Base location for resolving relative hrefs
    def initialize(grammar, location: nil)
      @grammar = grammar
      @location = location
    end

    # Resolve all external references in the grammar
    #
    # @return [Grammar] The resolved grammar
    def resolve
      visited_files = Set.new
      build_resolved_grammar(@grammar, @location, visited_files)
    end

    private

    # Build a new resolved grammar (doesn't modify original)
    #
    # @param grammar [Grammar] Grammar to resolve
    # @param location [String, nil] Base location for href resolution
    # @param visited_files [Set] Set of visited file paths for cycle detection
    # @return [Grammar] New grammar with resolved external refs
    def build_resolved_grammar(grammar, location, visited_files)
      return grammar unless grammar

      base_dir = location ? File.dirname(File.expand_path(location)) : Dir.pwd

      # Create new grammar with namespace and datatypeLibrary
      new_grammar = Grammar.new
      new_grammar.ns = grammar.ns if grammar.ns && grammar.ns != :omitted
      new_grammar.datatypeLibrary = grammar.datatypeLibrary if grammar.datatypeLibrary

      # Process includes and build the new grammar's content
      include_results = resolve_includes!(grammar, base_dir, visited_files)

      if include_results.empty?
        # No includes - copy original content with externalRef resolution
        copy_grammar_content!(new_grammar, grammar, base_dir, visited_files)
      else
        # Has includes - merge the resolved included content
        include_results.each do |resolved|
          merge_grammar_content!(new_grammar, resolved, base_dir, visited_files)
        end
      end

      new_grammar
    end

    # Copy grammar content when there are no includes
    #
    # @param new_grammar [Grammar] Target grammar to copy into
    # @param grammar [Grammar] Source grammar
    # @param base_dir [String] Base directory
    # @param visited_files [Set] Set of visited file paths
    def copy_grammar_content!(new_grammar, grammar, base_dir, visited_files)
      # Copy start pattern
      if grammar.start && !grammar.start.empty?
        new_grammar.start = grammar.start.filter_map do |s|
          resolved = resolve_pattern(deep_dup(s), base_dir, visited_files)
          clear_element_order!(resolved)
          resolved
        end
      end

      # Copy define patterns
      if grammar.define && !grammar.define.empty?
        new_grammar.define = grammar.define.filter_map do |d|
          resolved = resolve_pattern(deep_dup(d), base_dir, visited_files)
          clear_element_order!(resolved)
          resolved
        end
      end

      # Copy div elements
      return unless grammar.div && !grammar.div.empty?

      new_grammar.div = grammar.div.filter_map do |div|
        resolved_div = resolve_div(deep_dup(div), base_dir, visited_files)
        clear_element_order!(resolved_div)
        resolved_div
      end
    end

    # Recursively clear element_order on an object and its children
    # This forces to_xml to use Ruby attributes instead of stale XML nodes
    #
    # @param obj [Object] Object to clear element_order on
    def clear_element_order!(obj)
      return obj unless obj

      obj.instance_variable_set(:@element_order, nil)

      # Recursively clear on children based on type
      case obj
      when Start
        %i[element choice group interleave mixed optional zeroOrMore
           oneOrMore text empty value data list parentRef notAllowed grammar].each do |attr|
          children = obj.send(attr)
          next if children.nil? || (children.respond_to?(:empty?) && children.empty?)

          Array(children).each { |c| clear_element_order!(c) }
        end
      when Define
        %i[ref element choice group interleave mixed optional zeroOrMore
           oneOrMore text empty value data list notAllowed attribute grammar].each do |attr|
          children = obj.send(attr)
          next if children.nil? || (children.respond_to?(:empty?) && children.empty?)

          Array(children).each { |c| clear_element_order!(c) }
        end
      when Element
        %i[attribute ref choice group interleave mixed optional zeroOrMore
           oneOrMore anyName text empty value data list notAllowed element grammar].each do |attr|
          children = obj.send(attr)
          next if children.nil? || (children.respond_to?(:empty?) && children.empty?)

          Array(children).each { |c| clear_element_order!(c) }
        end
      when Group
        %i[attribute ref choice group interleave mixed optional zeroOrMore
           oneOrMore text empty value data list notAllowed].each do |attr|
          children = obj.send(attr)
          next if children.nil? || (children.respond_to?(:empty?) && children.empty?)

          Array(children).each { |c| clear_element_order!(c) }
        end
      when Div
        obj.div&.each { |d| clear_element_order!(d) }
        %i[start define].each do |attr|
          children = obj.send(attr)
          next if children.nil? || (children.respond_to?(:empty?) && children.empty?)

          Array(children).each { |c| clear_element_order!(c) }
        end
      end

      obj
    end

    # Resolve includes and return array of resolved grammars/content
    #
    # @param grammar [Grammar] Grammar containing includes
    # @param base_dir [String] Base directory for relative path resolution
    # @param visited_files [Set] Set of visited file paths
    # @return [Array] Array of content to merge (grammars or defines)
    def resolve_includes!(grammar, base_dir, visited_files)
      return [] unless grammar.include && !grammar.include.empty?

      results = []
      grammar.include.each do |include_directive|
        next unless include_directive.href

        begin
          resolved = resolve_include(include_directive, base_dir, visited_files)
          results << resolved if resolved
        rescue ExternalRefResolutionError => e
          warn "Warning: Failed to resolve include '#{include_directive.href}': #{e.message}" if ENV['RNG_VERBOSE']
        end
      end
      results
    end

    # Merge content into new grammar
    #
    # @param new_grammar [Grammar] Target grammar to merge into
    # @param resolved [Grammar] Resolved included grammar
    # @param base_dir [String] Base directory
    # @param visited_files [Set] Set of visited file paths
    def merge_grammar_content!(new_grammar, resolved, _base_dir, _visited_files)
      return unless resolved

      # Merge datatypeLibrary if not set
      new_grammar.datatypeLibrary = resolved.datatypeLibrary if new_grammar.datatypeLibrary.nil? || new_grammar.datatypeLibrary == :omitted

      # Merge start pattern if new_grammar has no start
      if (new_grammar.start.nil? || new_grammar.start.empty?) && resolved.start && !resolved.start.empty?
        new_grammar.start = resolved.start.map do |s|
          deep_dup(s)
        end
      end

      # Merge definitions
      return unless resolved.define

      resolved.define.each do |ext_define|
        add_or_replace_define(new_grammar, deep_dup(ext_define))
      end
    end

    # Deep dup a pattern object
    #
    # Uses recursive copying instead of Marshal to handle objects
    # containing Nokogiri::XML::Element nodes (stored in element_order
    # by lutaml-model), which cannot be serialized by Marshal.
    #
    # @param obj [Object] Object to deep copy
    # @return [Object] Deep copy of object
    def deep_dup(obj)
      case obj
      when Lutaml::Model::Serializable
        result = obj.class.new
        obj.class.attributes.each_key do |attr_name|
          value = obj.public_send(attr_name)
          result.public_send(:"#{attr_name}=", deep_dup(value))
        end
        result
      when Array
        obj.map { |o| deep_dup(o) }
      when Hash
        obj.each_with_object({}) { |(k, v), h| h[deep_dup(k)] = deep_dup(v) }
      when NilClass, Symbol, Numeric, TrueClass, FalseClass
        obj
      else
        obj.dup
      end
    end

    # Resolve a single include directive
    #
    # @param include_directive [Include] Include element with href
    # @param base_dir [String] Base directory for resolution
    # @param visited_files [Set] Set of visited file paths
    # @return [Grammar, nil] Resolved grammar or nil on error
    def resolve_include(include_directive, base_dir, visited_files)
      href = include_directive.href
      resolved_path = resolve_href(href, base_dir, visited_files)

      # Mark this file as visited BEFORE processing to detect circular refs
      visited_files << resolved_path

      # Parse the external grammar file
      external_grammar = Grammar.from_xml(File.read(resolved_path))

      # Recursively resolve external refs in the included grammar
      build_resolved_grammar(external_grammar, resolved_path, visited_files)
    end

    # Add or replace a definition in grammar
    #
    # @param grammar [Grammar] Grammar to modify
    # @param define [Define] Definition to add or replace
    def add_or_replace_define(grammar, define)
      return unless define&.name

      grammar.define ||= []
      existing = grammar.define.find { |d| d.name == define.name }
      if existing
        # Replace existing definition
        idx = grammar.define.index(existing)
        grammar.define[idx] = define
      else
        # Add new definition
        grammar.define << define
      end
    end

    # Resolve external refs in a div element
    #
    # @param div [Div] Div element
    # @param base_dir [String] Base directory for resolution
    # @param visited_files [Set] Set of visited file paths
    def resolve_div(div, base_dir, visited_files)
      return unless div

      # Resolve includes within div
      div.div&.each do |nested_div|
        resolve_div(nested_div, base_dir, visited_files)
      end

      div.start&.each { |s| resolve_pattern(s, base_dir, visited_files) if s }

      return unless div.define

      div.define.each { |d| resolve_pattern(d, base_dir, visited_files) if d }
    end

    # Resolve external refs in a pattern
    #
    # @param pattern [Object] Pattern object (Start, Define, Element, Group, etc.)
    # @param base_dir [String] Base directory for resolution
    # @param visited_files [Set] Set of visited file paths
    def resolve_pattern(pattern, base_dir, visited_files)
      return unless pattern

      # Handle Element pattern
      case pattern
      when Element
        resolve_element_external_ref!(pattern, base_dir, visited_files)

        # Recursively resolve in Element's children
        resolve_element_children!(pattern, base_dir, visited_files)
      # Handle Group pattern
      when Group
        resolve_group_external_ref!(pattern, base_dir, visited_files)

        # Recursively resolve in Group's children
        resolve_group_children!(pattern, base_dir, visited_files)
      # Handle Define pattern
      when Define
        resolve_define_children!(pattern, base_dir, visited_files)
      # Handle Start pattern
      when Start
        resolve_start_children!(pattern, base_dir, visited_files)
      when Start
        resolve_pattern_children!(pattern, base_dir, visited_files)
      end

      pattern
    end

    # Resolve external ref in an Element
    #
    # @param element [Element] Element with external_ref
    # @param base_dir [String] Base directory
    # @param visited_files [Set] Set of visited file paths
    def resolve_element_external_ref!(element, base_dir, visited_files)
      return unless element.external_ref

      href = element.external_ref.href
      return unless href

      begin
        resolved_path = resolve_href(href, base_dir, visited_files)
        external_grammar = Grammar.from_xml(File.read(resolved_path))
        resolved_grammar = build_resolved_grammar(external_grammar, resolved_path, visited_files)

        # Get the start pattern from the external grammar
        if resolved_grammar.start && !resolved_grammar.start.empty?
          start_pattern = resolved_grammar.start.first

          # Copy attributes from external ref's ns to override namespace
          if element.external_ref.ns && !element.external_ref.ns.empty? &&
             element.external_ref.ns != :omitted && element.external_ref.ns != :empty && element.external_ref.ns != :empty
            start_pattern.ns = element.external_ref.ns
          end

          # Replace the external_ref with the start pattern's content
          replace_element_external_ref!(element, start_pattern)
        end
      rescue ExternalRefResolutionError => e
        warn "Warning: Failed to resolve externalRef '#{href}': #{e.message}" if ENV['RNG_VERBOSE']
      rescue StandardError => e
        warn "Warning: Error resolving externalRef '#{href}': #{e.message}" if ENV['RNG_VERBOSE']
      end
    end

    # Replace external_ref in element with resolved pattern
    #
    # @param element [Element] Element containing external_ref
    # @param start_pattern [Object] Resolved start pattern
    def replace_element_external_ref!(element, start_pattern)
      # Clear external_ref
      element.external_ref = nil

      # Copy all pattern content from start_pattern to element
      copy_pattern_content(element, start_pattern)
    end

    # Copy pattern content from source to target
    #
    # @param target [Object] Target pattern (Element, Group, etc.)
    # @param source [Object] Source pattern
    def copy_pattern_content(target, source)
      case source
      when Start
        # Start pattern - copy its content (element, choice, group, etc.)
        copy_children(target, source, %i[element choice group interleave mixed optional
                                         zeroOrMore oneOrMore text empty value data
                                         list parentRef notAllowed grammar])
      when Element
        target.attr_name = source.attr_name if source.attr_name
        target.ns = source.ns if source.ns
        copy_children(target, source, %i[attribute ref choice group interleave mixed
                                         optional zeroOrMore oneOrMore anyName
                                         text empty value data list notAllowed element])
      when Group
        copy_children(target, source, %i[attribute ref choice group interleave mixed
                                         optional zeroOrMore oneOrMore text empty
                                         value data list notAllowed externalRef])
      when Choice
        target.choice = source.choice if source.choice
      when Group
        target.group = source.group if source.group
      when Interleave
        target.interleave = source.interleave if source.interleave
      when Optional
        target.optional = source.optional if source.optional
      when ZeroOrMore
        target.zeroOrMore = source.zeroOrMore if source.zeroOrMore
      when OneOrMore
        target.oneOrMore = source.oneOrMore if source.oneOrMore
      when Mixed
        target.mixed = source.mixed if source.mixed
      when Text
        target.text = source.text if source.text
      when Empty
        target.empty = source.empty if source.empty
      when Value
        target.value = source.value if source.value
      when Data
        target.data = source.data if source.data
      when List
        target.list = source.list if source.list
      when NotAllowed
        target.notAllowed = source.notAllowed if source.notAllowed
      end
    end

    # Copy child collections from source to target
    #
    # @param target [Object] Target pattern
    # @param source [Object] Source pattern
    # @param attrs [Array<Symbol>] Attribute names to copy
    def copy_children(target, source, attrs)
      attrs.each do |attr|
        value = source.send(attr)
        next if value.nil? || (value.respond_to?(:empty?) && value.empty?)

        target.send("#{attr}=", value) if target.respond_to?("#{attr}=")
      end
    end

    # Resolve external ref in a Group
    #
    # @param group [Group] Group with externalRef
    # @param base_dir [String] Base directory
    # @param visited_files [Set] Set of visited file paths
    def resolve_group_external_ref!(group, base_dir, visited_files)
      return unless group.externalRef

      href = group.externalRef.href
      return unless href

      begin
        resolved_path = resolve_href(href, base_dir, visited_files)
        external_grammar = Grammar.from_xml(File.read(resolved_path))
        resolved_grammar = build_resolved_grammar(external_grammar, resolved_path, visited_files)

        if resolved_grammar.start && !resolved_grammar.start.empty?
          start_pattern = resolved_grammar.start.first

          # Handle ns attribute override
          if group.externalRef.ns && !group.externalRef.ns.empty? &&
             group.externalRef.ns != :omitted && group.externalRef.ns != :empty && group.externalRef.ns != :empty
            start_pattern.ns = group.externalRef.ns
          end

          replace_group_external_ref!(group, start_pattern)
        end
      rescue ExternalRefResolutionError => e
        warn "Warning: Failed to resolve externalRef '#{href}': #{e.message}" if ENV['RNG_VERBOSE']
      rescue StandardError => e
        warn "Warning: Error resolving externalRef '#{href}': #{e.message}" if ENV['RNG_VERBOSE']
      end
    end

    # Replace externalRef in group with resolved pattern
    #
    # @param group [Group] Group containing externalRef
    # @param start_pattern [Object] Resolved start pattern
    def replace_group_external_ref!(group, start_pattern)
      group.externalRef = nil
      copy_pattern_content(group, start_pattern)
    end

    # Recursively resolve children of an Element
    #
    # @param element [Element] Element to resolve children in
    # @param base_dir [String] Base directory
    # @param visited_files [Set] Set of visited file paths
    def resolve_element_children!(element, base_dir, visited_files)
      %i[attribute ref choice group interleave mixed optional zeroOrMore
         oneOrMore anyName text empty value data list notAllowed element grammar].each do |attr|
        children = element.send(attr)
        next if children.nil? || (children.respond_to?(:empty?) && children.empty?)

        Array(children).each do |child|
          resolve_pattern(child, base_dir, visited_files)
        end
      end
    end

    # Recursively resolve children of a Group
    #
    # @param group [Group] Group to resolve children in
    # @param base_dir [String] Base directory
    # @param visited_files [Set] Set of visited file paths
    def resolve_group_children!(group, base_dir, visited_files)
      %i[attribute ref choice group interleave mixed optional zeroOrMore
         oneOrMore text empty value data list notAllowed].each do |attr|
        children = group.send(attr)
        next if children.nil? || (children.respond_to?(:empty?) && children.empty?)

        Array(children).each do |child|
          resolve_pattern(child, base_dir, visited_files)
        end
      end
    end

    # Recursively resolve children of a Start pattern
    #
    # @param start [Start] Start pattern to resolve children in
    # @param base_dir [String] Base directory
    # @param visited_files [Set] Set of visited file paths
    def resolve_start_children!(start, base_dir, visited_files)
      # Start has: element, choice, group, interleave, mixed, optional,
      #            zeroOrMore, oneOrMore, text, empty, value, data, list,
      #            parentRef, notAllowed, grammar
      %i[element choice group interleave mixed optional zeroOrMore
         oneOrMore text empty value data list parentRef notAllowed grammar].each do |attr|
        children = start.send(attr)
        next if children.nil? || (children.respond_to?(:empty?) && children.empty?)

        Array(children).each do |child|
          resolve_pattern(child, base_dir, visited_files)
        end
      end
    end

    # Recursively resolve children of a Define
    #
    # @param define [Define] Define to resolve children in
    # @param base_dir [String] Base directory
    # @param visited_files [Set] Set of visited file paths
    def resolve_define_children!(define, base_dir, visited_files)
      # Define has: ref, element, choice, group, interleave, mixed, optional,
      #            zeroOrMore, oneOrMore, text, empty, value, data, list,
      #            notAllowed, attribute, grammar
      %i[ref element choice group interleave mixed optional zeroOrMore
         oneOrMore text empty value data list notAllowed attribute grammar].each do |attr|
        children = define.send(attr)
        next if children.nil? || (children.respond_to?(:empty?) && children.empty?)

        Array(children).each do |child|
          resolve_pattern(child, base_dir, visited_files)
        end
      end
    end

    # Resolve href to absolute path with cycle detection
    #
    # @param href [String] Relative or absolute href
    # @param base_dir [String] Base directory for relative resolution
    # @param visited_files [Set] Set of visited file paths for cycle detection
    # @return [String] Absolute path
    def resolve_href(href, base_dir, visited_files)
      # Resolve relative to base_dir
      resolved = if base_dir && !base_dir.empty?
                   File.expand_path(href, base_dir)
                 else
                   File.expand_path(href)
                 end

      # Check for cycle
      if visited_files.include?(resolved)
        raise ExternalRefResolutionError.new(
          "Circular reference detected: #{href}",
          href: href,
          cause: :circular
        )
      end

      # Check file exists
      unless File.exist?(resolved)
        raise ExternalRefResolutionError.new(
          "External file not found: #{href}",
          href: href,
          cause: Errno::ENOENT
        )
      end

      resolved
    end
  end
end
