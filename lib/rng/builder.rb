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
      schema.to_xml
    end

    def build_rnc(schema)
      result = ""
      schema.start.elements.each do |element|
        result += build_rnc_element(element)
      end
      result
    end

    def build_rnc_element(element, indent = 0)
      result = "  " * indent
      result += "element #{element.name} {\n"

      element.attributes&.each do |attr|
        result += "  " * (indent + 1)
        result += "attribute #{attr.name} { text }\n"
      end

      element.elements&.each do |child|
        result += build_rnc_element(child, indent + 1)
      end

      if element.text
        result += "  " * (indent + 1)
        result += "text\n"
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

      result += "\n"
      result
    end
  end
end
