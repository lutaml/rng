require "parslet"
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

    rule(:element_def) {
      str("element") >> space >>
      identifier >>
      whitespace >>
      str("{") >>
      whitespace >>
      content.maybe.as(:content) >>
      whitespace >>
      str("}") >>
      (str("*") | str("+") | str("?")).maybe.as(:occurrence)
    }

    rule(:attribute_def) {
      str("attribute") >> space >>
      identifier.as(:name) >>
      whitespace >>
      str("{") >>
      whitespace >>
      (str("text")).as(:type) >>
      whitespace >>
      str("}")
    }

    rule(:text_def) { str("text").as(:text) }

    rule(:content_item) {
      ((element_def | attribute_def | text_def).as(:item) >> comma?).repeat(1).as(:items)
    }

    rule(:content) { content_item }

    rule(:grammar) { whitespace >> element_def.as(:element) >> whitespace }

    root(:grammar)

    def parse(input)
      tree = super(input.strip)
      build_schema(tree)
    end

    private

    def build_schema(tree)
      element = tree[:element]
      Schema.new(
        start: Start.new(
          elements: [build_element(element)],
        ),
      )
    end

    def build_element(element)
      name = element[:identifier].to_s
      content = element[:content]&.[](:items)
      occurrence = element[:occurrence]

      # Create base element
      el = Element.new(
        name: name,
        attributes: [],
        elements: [],
        text: false,
      )

      if content
        current_elements = []
        current_attributes = []

        content.each do |item|
          case
          when item[:item][:name] || (item[:item][:identifier] && item[:item][:type])
            attr_name = item[:item][:name] || item[:item][:identifier]
            attr = Attribute.new(
              name: attr_name.to_s,
              type: ["string"],
            )
            current_attributes << attr
          when item[:item][:identifier]
            current_elements << build_element(item[:item])
          when item[:item][:text]
            el.text = true
          end
        end

        el.attributes = current_attributes
        el.elements = current_elements
      end

      # Handle occurrence modifiers
      result = el
      case occurrence
      when "*"
        result = Element.new(
          name: el.name,
          attributes: el.attributes,
          elements: el.elements,
          text: el.text,
        )
        result.zero_or_more = [el]
      when "+"
        result = Element.new(
          name: el.name,
          attributes: el.attributes,
          elements: el.elements,
          text: el.text,
        )
        result.one_or_more = [el]
      when "?"
        result = Element.new(
          name: el.name,
          attributes: el.attributes,
          elements: el.elements,
          text: el.text,
        )
        result.optional = [el]
      end

      result
    end
  end
end
