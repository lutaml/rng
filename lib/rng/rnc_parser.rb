require "parslet"
require_relative "schema"

module Rng
  class RncParser < Parslet::Parser
    rule(:space) { match('\s').repeat(1) }
    rule(:space?) { space.maybe }
    rule(:newline) { (str("\r").maybe >> str("\n")).repeat(1) }
    rule(:newline?) { newline.maybe }
    rule(:comma) { str(",") >> space? >> newline? }
    rule(:comma?) { comma.maybe }

    rule(:identifier) { match("[a-zA-Z0-9_]").repeat(1) }

    rule(:element_def) {
      str("element") >> space >>
      identifier.as(:name) >> space? >>
      str("{") >> space? >> newline? >>
      content.as(:content).maybe >> space? >> newline? >>
      str("}") >>
      (str("*") | str("+") | str("?")).maybe.as(:occurrence)
    }

    rule(:attribute_def) {
      str("attribute") >> space >>
      identifier.as(:name) >> space? >>
      str("{") >> space? >>
      str("text") >>
      space? >> str("}")
    }

    rule(:text_def) { str("text") }

    rule(:content_item) {
      (element_def | attribute_def | text_def | optional) >> comma?
    }

    rule(:content) { content_item.repeat(1) }

    rule(:optional) {
      (element_def | attribute_def).as(:optional) >> str("?")
    }

    rule(:grammar) { element_def.as(:element) }

    root(:grammar)

    def parse(input)
      tree = super(input)
      build_schema(tree)
    end

    private

    def build_schema(tree)
      Rng::Schema.new(
        start: Rng::Start.new(
          elements: [build_element(tree[:element])],
        ),
      )
    end

    def build_element(element)
      Rng::Element.new(
        name: element[:name].to_s,
        elements: build_content(element[:content]),
        zero_or_more: element[:occurrence] == "*" ? [Rng::Element.new] : nil,
        one_or_more: element[:occurrence] == "+" ? [Rng::Element.new] : nil,
        optional: element[:occurrence] == "?" ? [Rng::Element.new] : nil,
      )
    end

    def build_content(content)
      return [] if content.nil?

      content.map do |item|
        case item
        when Hash
          if item[:optional]
            build_optional(item[:optional])
          elsif item.key?(:name)
            if item[:content]&.include?("text")
              Rng::Element.new(name: item[:name].to_s, text: true)
            else
              build_element(item)
            end
          end
        when String
          if item == "text"
            Rng::Element.new(text: true)
          end
        end
      end.compact
    end

    def build_optional(item)
      element = if item.key?(:content)
          build_element(item)
        else
          Rng::Element.new(name: item[:name].to_s, text: true)
        end
      element.optional = [element.dup]
      element
    end
  end
end
