require "nokogiri"
require_relative "schema"
require_relative "element"

module Rng
  class RngParser
    RELAXNG_NS = "http://relaxng.org/ns/structure/1.0"

    def parse(input)
      doc = Nokogiri::XML(input)
      doc.remove_namespaces! # This simplifies namespace handling

      root = doc.root
      case root.name
      when "grammar"
        parse_grammar(doc)
      when "element"
        parse_element(doc)
      else
        raise Rng::Error, "Unexpected root element: #{root.name}"
      end
    end

    private

    def parse_grammar(doc)
      Schema.new(
        start: parse_start(doc.at_xpath("//start")),
        define: doc.xpath("//define").map { |define| parse_define(define) },
      )
    end

    def parse_start(node)
      return nil unless node

      Start.new(
        ref: node.at_xpath(".//ref")&.attr("name"),
        elements: node.xpath(".//element").map { |element| parse_element(element) },
      )
    end

    def parse_define(node)
      Define.new(
        name: node["name"],
        elements: node.xpath(".//element").map { |element| parse_element(element) },
      )
    end

    def parse_element(node)
      Element.new(
        name: node["name"],
        attributes: node.xpath(".//attribute").map { |attr| parse_attribute(attr) },
        elements: node.xpath("./element").map { |el| parse_element(el) },
        text: !node.xpath(".//text").empty?,
        zero_or_more: parse_zero_or_more(node),
        one_or_more: parse_one_or_more(node),
        optional: parse_optional(node),
        choice: parse_choice(node),
      )
    end

    def parse_attribute(node)
      Attribute.new(
        name: node["name"],
        type: node.xpath(".//data").map { |data| data["type"] },
      )
    end

    def parse_zero_or_more(node)
      node.xpath(".//zeroOrMore/element").map { |el| parse_element(el) }
    end

    def parse_one_or_more(node)
      node.xpath(".//oneOrMore/element").map { |el| parse_element(el) }
    end

    def parse_optional(node)
      node.xpath(".//optional/element").map { |el| parse_element(el) }
    end

    def parse_choice(node)
      node.xpath(".//choice/element").map { |el| parse_element(el) }
    end
  end
end
