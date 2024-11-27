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
      return nil unless node["name"]

      element = Element.new(
        name: node["name"],
        attributes: [],
        elements: [],
        text: false,
      )

      node.children.each do |child|
        parse_child(child, element)
      end

      element
    end

    def parse_child(node, element)
      case node.name
      when "attribute"
        element.attributes << parse_attribute(node)
      when "element"
        element.elements << parse_element(node)
      when "text"
        element.text = true
      when "zeroOrMore"
        parse_zero_or_more(node).each { |el| element.zero_or_more << el }
      when "oneOrMore"
        parse_one_or_more(node).each { |el| element.one_or_more << el }
      when "optional"
        parse_optional(node).each { |el| element.optional << el }
      end
    end

    def parse_attribute(node)
      data_node = node.at_xpath(".//data")
      Attribute.new(
        name: node["name"],
        type: data_node ? [data_node["type"]] : ["string"],
      )
    end

    def parse_zero_or_more(node)
      node.xpath("./element").map { |el| parse_element(el) }
    end

    def parse_one_or_more(node)
      node.xpath("./element").map { |el| parse_element(el) }
    end

    def parse_optional(node)
      node.xpath("./element").map { |el| parse_element(el) }
    end

    def parse_choice(node)
      node.xpath(".//choice/element").map { |el| parse_element(el) }
    end
  end
end
