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
      identifier >>
      whitespace >>
      str("{") >>
      whitespace >>
      (str("text")).as(:type) >>
      whitespace >>
      str("}")
    }

    rule(:text_def) { str("text").as(:text) }

    rule(:content_item) {
      (element_def | attribute_def | text_def).as(:item) >> comma?
    }

    rule(:content) { content_item.repeat(1) }

    rule(:grammar) { whitespace >> element_def.as(:element) >> whitespace }

    root(:grammar)

    def parse(input)
      tree = super(input.strip)
      build_schema(tree)
    end

    private

    def build_schema(tree)
      element = tree[:element]
      Rng::Schema.new(
        start: Rng::Start.new(
          elements: [build_element(element)],
        ),
      )
    end

    def build_element(element)
      name = element[:identifier].to_s
      content = element[:content]
      occurrence = element[:occurrence]

      el = Rng::Element.new(
        name: name,
        attributes: [],
        elements: [],
        text: false,
      )

      if content
        content.each do |item|
          case
          when item[:item][:identifier] && item[:item][:type]
            el.attributes << Rng::Attribute.new(
              name: item[:item][:identifier].to_s,
              type: ["string"],
            )
          when item[:item][:identifier]
            el.elements << build_element(item[:item])
          when item[:item][:text]
            el.text = true
          end
        end
      end

      case occurrence
      when "*"
        el.zero_or_more = [el.dup]
      when "+"
        el.one_or_more = [el.dup]
      when "?"
        el.optional = [el.dup]
      end

      el
    end
  end
end
