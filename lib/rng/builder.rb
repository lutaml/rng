module Rng
  class Builder
    def build(schema, format:)
      case format
      when :rng
        build_rng(schema)
      when :rnc
        build_rnc(schema)
      else
        raise ArgumentError, "Unsupported format: #{format}"
      end
    end

    private

    def build_rng(schema)
      doc = Nokogiri::XML::Document.new
      doc.encoding = "UTF-8"

      if schema.is_a?(Rng::Schema)
        root = Nokogiri::XML::Node.new("grammar", doc)
        root["xmlns"] = "http://relaxng.org/ns/structure/1.0"
        doc.root = root

        start = Nokogiri::XML::Node.new("start", doc)
        root.add_child(start)

        if schema.start.ref
          ref = Nokogiri::XML::Node.new("ref", doc)
          ref["name"] = schema.start.ref
          start.add_child(ref)
        end

        schema.start.elements.each do |element|
          start.add_child(build_rng_element(element, doc))
        end

        schema.define&.each do |define|
          define_node = Nokogiri::XML::Node.new("define", doc)
          define_node["name"] = define.name
          define.elements.each do |element|
            define_node.add_child(build_rng_element(element, doc))
          end
          root.add_child(define_node)
        end
      elsif schema.is_a?(Rng::Element)
        el = build_rng_element(schema, doc)
        el["xmlns"] = "http://relaxng.org/ns/structure/1.0"
        doc.root = el
      end

      doc.to_xml
    end

    def build_rng_element(element, doc)
      if element.zero_or_more&.any?
        zero_or_more = Nokogiri::XML::Node.new("zeroOrMore", doc)
        el = Nokogiri::XML::Node.new("element", doc)
        el["name"] = element.name
        add_element_content(element, el, doc)
        zero_or_more.add_child(el)
        return zero_or_more
      elsif element.one_or_more&.any?
        one_or_more = Nokogiri::XML::Node.new("oneOrMore", doc)
        el = Nokogiri::XML::Node.new("element", doc)
        el["name"] = element.name
        add_element_content(element, el, doc)
        one_or_more.add_child(el)
        return one_or_more
      elsif element.optional&.any?
        optional = Nokogiri::XML::Node.new("optional", doc)
        el = Nokogiri::XML::Node.new("element", doc)
        el["name"] = element.name
        add_element_content(element, el, doc)
        optional.add_child(el)
        return optional
      else
        el = Nokogiri::XML::Node.new("element", doc)
        el["name"] = element.name
        add_element_content(element, el, doc)
        return el
      end
    end

    def add_element_content(element, el, doc)
      element.attributes&.each do |attr|
        attr_node = Nokogiri::XML::Node.new("attribute", doc)
        attr_node["name"] = attr.name
        if attr.type&.any?
          data = Nokogiri::XML::Node.new("data", doc)
          data["type"] = attr.type.first
          attr_node.add_child(data)
        else
          text = Nokogiri::XML::Node.new("text", doc)
          attr_node.add_child(text)
        end
        el.add_child(attr_node)
      end

      element.elements&.each do |child|
        el.add_child(build_rng_element(child, doc))
      end

      if element.text
        text = Nokogiri::XML::Node.new("text", doc)
        el.add_child(text)
      end
    end

    def build_rnc(schema)
      result = ""
      elements = schema.is_a?(Rng::Schema) ? schema.start.elements : [schema]
      elements.each do |element|
        result += build_rnc_element(element)
      end
      result
    end

    def build_rnc_element(element, indent = 0)
      return "" unless element # Handle nil elements

      result = "  " * indent
      result += "element #{element.name} {\n"

      element.attributes&.each do |attr|
        result += "  " * (indent + 1)
        result += "attribute #{attr.name} { text }"
        result += ",\n" unless element.attributes.last == attr && !element.elements&.any? && !element.text
      end

      element.elements&.each_with_index do |child, index|
        child_result = build_rnc_element(child, indent + 1)
        result += child_result
        result += "," unless index == element.elements.size - 1 && !element.text
        result += "\n"
      end

      if element.text
        result += "  " * (indent + 1)
        result += "text"
        result += "\n"
      end

      result += "  " * indent
      result += "}"

      if element.zero_or_more&.any?
        result += "*"
      elsif element.one_or_more&.any?
        result += "+"
      elsif element.optional&.any?
        result += "?"
      end

      result
    end
  end
end
